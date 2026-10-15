import Foundation
import SwiftUI

/// Central observable state. One instance is created at app start and injected
/// into the environment. Owns accounts, instances, settings, the install
/// pipeline and the live console buffer.
@MainActor
final class LauncherModel: ObservableObject {

    @Published var accounts = AccountStore()
    @Published var settings = SettingsStore()
    @Published var instances: [Instance] = []
    @Published var consoleLines: [String] = []
    @Published var isLaunching = false
    @Published var installProgress: Double = 0
    @Published var installStatus: String = ""
    @Published var lastResult: LaunchResult?
    @Published var banner: String?

    private let installer = VersionInstaller()
    private let launchService = LaunchService()
    private let manifestService = VersionManifestService()

    private static let instancesKey = "mcl.instances.v1"

    init() {
        try? LauncherPaths.bootstrap()
        loadInstances()
    }

    // MARK: - Accounts

    func addOfflineAccount(_ name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            banner = "Enter a username."
            return
        }
        let account = accounts.addOfflineAccount(username: name)
        accounts.select(account)
        banner = "Offline account '\(account.username)' added."
    }

    func signInMicrosoft() async {
        let auth = MicrosoftAuth()
        do {
            let device = try await auth.requestDeviceCode()
            // Present the code to the user; they complete sign-in in Safari.
            UIPasteboard.general.string = device.userCode
            banner = "Code \(device.userCode) copied. Opening \(device.verificationURI.host ?? "microsoft.com")…"
            await UIApplication.shared.open(device.verificationURI)

            let tokens = try await auth.pollForTokens(deviceCode: device,
                                                      isCancelled: { false },
                                                      onTick: { [weak self] msg in
                Task { @MainActor in self?.banner = msg }
            })
            let account = try await auth.buildAccount(microsoftAccessToken: tokens.accessToken,
                                                      refreshToken: tokens.refreshToken)
            accounts.upsertMicrosoftAccount(account)
            accounts.select(account)
            banner = "Signed in as \(account.username)."
        } catch {
            banner = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Instances

    func createInstance(name: String, version: String, loader: ModLoader) {
        let instance = Instance(name: name, gameVersion: version, loader: loader)
        instances.append(instance)
        // Create the game directory and the standard content folders (mods,
        // resourcepacks, …) immediately so the Files tab has somewhere to drop
        // things even before the version is downloaded.
        InstanceFileManager.bootstrap(instance: instance)
        saveInstances()
        banner = "Created instance '\(name)'."
    }

    func deleteInstance(_ instance: Instance) {
        instances.removeAll { $0.id == instance.id }
        saveInstances()
    }

    func markInstalled(_ instance: Instance) {
        guard let idx = instances.firstIndex(where: { $0.id == instance.id }) else { return }
        instances[idx].isInstalled = true
        saveInstances()
    }

    /// Register an instance that was created outside the New Instance sheet —
    /// currently by the Modrinth modpack installer.
    func addInstalledInstance(_ instance: Instance) {
        guard !instances.contains(where: { $0.id == instance.id }) else { return }
        instances.append(instance)
        InstanceFileManager.bootstrap(instance: instance)
        saveInstances()
    }

    /// Look up an instance's game version in Mojang's manifest and download it.
    /// Used by the install button and after a modpack creates an instance.
    func installGameFiles(for instance: Instance) async {
        do {
            let manifest = try await manifestService.loadManifest()
            guard let version = manifest.versions.first(where: { $0.id == instance.gameVersion }) else {
                banner = "Version \(instance.gameVersion) not found in the manifest."
                return
            }
            await install(instance, version: version)
        } catch {
            banner = "Install failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Install

    func install(_ instance: Instance, version: MinecraftVersion) async {
        do {
            _ = try await installer.install(version: version) { [weak self] value, message in
                Task { @MainActor in
                    self?.installProgress = value
                    self?.installStatus = message
                }
            }
            markInstalled(instance)
            banner = "Installed \(version.id)."
        } catch {
            banner = "Install failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Launch

    func launch(_ instance: Instance) async {
        guard let account = accounts.selectedAccount else {
            banner = "Add an account first."
            return
        }
        guard JVMBridge.isRuntimeAvailable else {
            banner = "Java runtime not installed in this build — see BUILD.md."
            return
        }
        isLaunching = true
        consoleLines.removeAll()
        defer { isLaunching = false }

        // Tail the JVM log file while the game runs.
        let tailTask = Task { await self.tailLog() }

        do {
            let result = try await launchService.launch(instance: instance,
                                                        account: account,
                                                        settings: settings.settings) { [weak self] line in
                Task { @MainActor in self?.append(line) }
            }
            lastResult = result
            banner = result.succeeded ? "Game exited normally." : "Game exited with code \(result.exitCode)."
        } catch {
            banner = "Launch failed: \(error.localizedDescription)"
        }
        tailTask.cancel()
    }

    private func append(_ line: String) {
        consoleLines.append(line)
        if consoleLines.count > 2000 { consoleLines.removeFirst(500) }
    }

    /// Polls `.minecraft/latest.log` and streams new lines into `consoleLines`.
    private func tailLog() async {
        let logURL = LauncherPaths.root.appendingPathComponent("latest.log")
        var offset: UInt64 = 0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let handle = try? FileHandle(forReadingFrom: logURL) else { continue }
            defer { try? handle.close() }
            try? handle.seek(toOffset: offset)
            if let data = try? handle.readToEnd(), !data.isEmpty {
                offset += UInt64(data.count)
                let text = String(decoding: data, as: UTF8.self)
                for line in text.split(separator: "\n") { append(String(line)) }
            }
        }
    }

    // MARK: - Persistence

    private func loadInstances() {
        if let data = UserDefaults.standard.data(forKey: Self.instancesKey),
           let decoded = try? JSONDecoder().decode([Instance].self, from: data) {
            instances = decoded
        }
    }

    private func saveInstances() {
        if let data = try? JSONEncoder().encode(instances) {
            UserDefaults.standard.set(data, forKey: Self.instancesKey)
        }
    }
}
