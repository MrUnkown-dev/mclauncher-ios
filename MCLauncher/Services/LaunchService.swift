import Foundation
import UIKit

/// Assembles the full JVM command line for a launch and hands it to `JVMBridge`.
/// This is where the launcher, the version JSON and the user's settings meet.
final class LaunchService {

    enum LaunchError: LocalizedError {
        case runtimeMissing
        case versionNotInstalled(String)
        case noAccount
        case missingClient(String)
        var errorDescription: String? {
            switch self {
            case .runtimeMissing:            return "The Java runtime is not installed in this build. See BUILD.md → Adding the JRE."
            case .versionNotInstalled(let v):return "Version \(v) is not installed. Install it first."
            case .noAccount:                 return "No account selected."
            case .missingClient(let v):      return "Client jar for \(v) is missing."
            }
        }
    }

    private let manifestService = VersionManifestService()
    private let auth = MicrosoftAuth()

    // MARK: - Entry point

    /// Prepares and runs a launch. Calls `onLog` with every line the JVM emits
    /// (via the console pipe set up in `jvm_bridge.m`).
    @MainActor
    func launch(instance: Instance,
                account: Account,
                settings: LauncherSettings,
                onLog: @escaping (String) -> Void) async throws -> LaunchResult {
        guard JVMBridge.isRuntimeAvailable else { throw LaunchError.runtimeMissing }
        try LauncherPaths.bootstrap()

        var acct = account
        if acct.type == .microsoft && acct.needsRefresh {
            onLog("[launcher] Refreshing Microsoft session…")
            acct = try await auth.refresh(account: acct)
        }

        let detail = try await detailFor(instance: instance)
        let clientJar = LauncherPaths.versionDir(instance.gameVersion)
            .appendingPathComponent("\(instance.gameVersion).jar")
        guard FileManager.default.fileExists(atPath: clientJar.path) else {
            throw LaunchError.missingClient(instance.gameVersion)
        }

        let args = try buildArguments(instance: instance,
                                      detail: detail,
                                      account: acct,
                                      settings: settings)
        onLog("[launcher] java \(args.dropFirst().joined(separator: " "))")

        let env = environment(for: settings)

        let started = Date()
        let code: Int32 = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = JVMBridge.launch(arguments: args, environment: env)
                continuation.resume(returning: result)
            }
        }
        return LaunchResult(exitCode: code,
                            duration: Date().timeIntervalSince(started),
                            instanceName: instance.name)
    }

    /// Resolves the version detail, layering a mod loader on top when needed.
    private func detailFor(instance: Instance) async throws -> VersionDetail {
        let manifest = try await manifestService.loadManifest()
        guard let entry = manifest.versions.first(where: { $0.id == instance.gameVersion }) else {
            throw LaunchError.versionNotInstalled(instance.gameVersion)
        }
        let base = try await manifestService.loadDetail(for: entry)
        guard instance.loader != .vanilla else { return base }
        return try await ModLoaderService.apply(loader: instance.loader,
                                                loaderVersion: instance.loaderVersion,
                                                base: base,
                                                gameVersion: instance.gameVersion)
    }

    // MARK: - Argument assembly

    /// Builds `argv` for the JVM. Mirrors the official launcher's ordering:
    ///   java [jvm args] -cp <classpath> <mainClass> [game args]
    func buildArguments(instance: Instance,
                        detail: VersionDetail,
                        account: Account,
                        settings: LauncherSettings) throws -> [String] {
        let gameDir = LauncherPaths.instanceDir(instance.gameDirectory)
        try? FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
        // Ensure mods/, resourcepacks/, datapacks/, … exist so anything the user
        // added through the in-app file manager is picked up by the game.
        InstanceFileManager.bootstrap(instance: instance)

        let renderer: Renderer = settings.autoRenderer
            ? SettingsStore.suggestedRenderer(for: instance.gameVersion)
            : settings.renderer

        // ---- JVM arguments ------------------------------------------------
        var jvm: [String] = [
            "-Xmx\(settings.allocatedRAMmb)M",
            "-Xms\(max(256, settings.allocatedRAMmb / 2))M",
            "-Djava.library.path=\(LauncherPaths.root.path)/natives",
            "-Dorg.lwjgl.librarypath=\(LauncherPaths.root.path)/natives",
            "-Dfabric.gameVersion=\(instance.gameVersion)",
            "-Dminecraft.launcher.brand=MCLauncher",
            "-Dminecraft.launcher.version=1.0.0"
        ]
        if !settings.preferJIT {
            jvm.append("-Xint")   // interpreter only — slower, but needs no JIT entitlement
        }
        jvm.append(contentsOf: settings.extraJVMArgs.split(separator: " ").map(String.init))

        // Renderer selection via environment-style system properties.
        switch renderer {
        case .gl4es: jvm.append("-Dmcl.renderer=gl4es")
        case .angle: jvm.append("-Dmcl.renderer=angle")
        case .zink:  jvm.append("-Dmcl.renderer=zink")
        }

        // ---- Classpath ----------------------------------------------------
        let cp = try classpath(detail: detail)
        jvm.append(contentsOf: ["-cp", cp])

        // ---- Main class ---------------------------------------------------
        var tail: [String] = [detail.mainClass]

        // ---- Game arguments ----------------------------------------------
        tail.append(contentsOf: gameArguments(detail: detail,
                                              instance: instance,
                                              account: account,
                                              gameDir: gameDir,
                                              settings: settings))

        return ["java"] + jvm + tail
    }

    /// Builds the colon-separated classpath: client jar + every applicable library.
    func classpath(detail: VersionDetail) throws -> String {
        var entries: [String] = []
        let versionDir = LauncherPaths.versionDir(detail.id)
        let clientJar = versionDir.appendingPathComponent("\(detail.id).jar")
        if FileManager.default.fileExists(atPath: clientJar.path) {
            entries.append(clientJar.path)
        }
        for lib in detail.libraries where VersionInstaller.rulesAllow(lib.rules) {
            guard let artifact = lib.downloads?.artifact else { continue }
            let path = LauncherPaths.libraries
                .appendingPathComponent(artifact.path ?? VersionInstaller.mavenPath(lib))
            if FileManager.default.fileExists(atPath: path.path) {
                entries.append(path.path)
            }
        }
        return entries.joined(separator: ":")
    }

    /// Expands `${...}` placeholders used by both the legacy and modern forms.
    func gameArguments(detail: VersionDetail,
                       instance: Instance,
                       account: Account,
                       gameDir: URL,
                       settings: LauncherSettings) -> [String] {
        let nativesDir = LauncherPaths.root.appendingPathComponent("natives")
        let assetsIndex = detail.assetIndex?.id ?? detail.assets ?? "legacy"

        let substitutions: [String: String] = [
            "auth_player_name": account.username,
            "version_name": detail.id,
            "game_directory": gameDir.path,
            "assets_root": LauncherPaths.assets.path,
            "assets_index_name": assetsIndex,
            "auth_uuid": account.uuidUndashed,
            "auth_access_token": account.accessToken ?? "0",
            "auth_session": account.accessToken.map { "token:\($0)" } ?? "-",
            "user_type": account.type == .microsoft ? "msa" : "legacy",
            "user_properties": "{}",
            "clientid": Crypto.randomClientToken(),
            "auth_xuid": account.xuid ?? "",
            "version_type": detail.type ?? "release",
            "natives_directory": nativesDir.path,
            "launcher_name": "MCLauncher",
            "launcher_version": "1.0.0",
            "classpath": (try? classpath(detail: detail)) ?? "",
            "resolution_width": "\(Int(UIScreen.main.bounds.width * settings.resolutionScale))",
            "resolution_height": "\(Int(UIScreen.main.bounds.height * settings.resolutionScale))"
        ]

        var out: [String] = []

        if let legacy = detail.minecraftArguments, detail.arguments?.game == nil {
            // ≤1.12 form: a single template string.
            for token in legacy.split(separator: " ").map(String.init) {
                out.append(substitute(token, substitutions))
            }
        } else if let game = detail.arguments?.game {
            for arg in game {
                switch arg {
                case .string(let s):
                    out.append(substitute(s, substitutions))
                case .conditional(let rules, let value):
                    guard VersionInstaller.rulesAllow(rules) else { continue }
                    out.append(contentsOf: value.values.map { substitute($0, substitutions) })
                }
            }
        }

        // Launcher-side extras that aren't part of the vanilla JSON.
        if account.type == .offline {
            // Offline sessions still want a deterministic client token.
            out.append("--clientToken"); out.append(Crypto.randomClientToken())
        }
        if settings.maxFPS > 0 {
            out.append("--maxFps"); out.append("\(settings.maxFPS)")
        }
        return out
    }

    private func substitute(_ token: String, _ map: [String: String]) -> String {
        var result = token
        for (key, value) in map {
            result = result.replacingOccurrences(of: "${\(key)}", with: value)
        }
        return result
    }

    /// Environment variables that steer the graphics translation layer.
    private func environment(for settings: LauncherSettings) -> [String: String] {
        var env: [String: String] = [
            "LIBGL_ES": "2",
            "LIBGL_GL": "21"
        ]
        if settings.useMetalLayer {
            env["MCL_METAL_LAYER"] = "1"
        }
        switch settings.renderer {
        case .angle:
            env["MCL_ANGLE"] = "1"
        case .zink:
            env["MESA_LOADER_DRIVER_OVERRIDE"] = "zink"
            env["GALLIUM_DRIVER"] = "zink"
        case .gl4es:
            break
        }
        return env
    }
}
