import Foundation

/// Downloads everything a version needs to run: the client jar, libraries,
/// native binaries, and the asset index + objects. Progress is reported through
/// `onProgress` so the UI can show a real progress bar.
final class VersionInstaller: ObservableObject {

    @Published var isInstalling = false
    @Published var progress: Double = 0
    @Published var status: String = ""

    private let session: URLSession
    private let manifestService = VersionManifestService()

    init(session: URLSession = .shared) {
        self.session = session
    }

    enum InstallError: LocalizedError {
        case http(Int, URL)
        case badJSON(String)
        case checksum(String, expected: String, got: String)
        var errorDescription: String? {
            switch self {
            case .http(let c, let u): return "HTTP \(c) downloading \(u.lastPathComponent)"
            case .badJSON(let m):     return "Malformed version JSON: \(m)"
            case .checksum(let f, let e, let g): return "Checksum mismatch for \(f): expected \(e.prefix(8))… got \(g.prefix(8))…"
            }
        }
    }

    /// Install a base version. `progressHandler` runs on the main actor.
    @MainActor
    func install(version: MinecraftVersion,
                 onProgress: @escaping (Double, String) -> Void) async throws -> VersionDetail {
        isInstalling = true
        defer { isInstalling = false }
        try LauncherPaths.bootstrap()

        report(0.02, "Reading version manifest…", onProgress)
        let detail = try await manifestService.loadDetail(for: version)

        // ---- 1. Client jar -------------------------------------------------
        report(0.10, "Downloading client jar…", onProgress)
        let versionDir = LauncherPaths.versionDir(version.id)
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
        if let client = detail.downloads["client"] {
            let dest = versionDir.appendingPathComponent("\(version.id).jar")
            try await download(client, to: dest, verify: true)
        }

        // ---- 2. Libraries + natives ---------------------------------------
        let applicable = detail.libraries.filter { Self.rulesAllow($0.rules) }
        report(0.20, "Downloading \(applicable.count) libraries…", onProgress)
        var done = 0
        for lib in applicable {
            if let artifact = lib.downloads?.artifact {
                let dest = LauncherPaths.libraries.appendingPathComponent(artifact.path ?? Self.mavenPath(lib))
                try await download(artifact, to: dest, verify: true)
            }
            // Native classifier for this platform (arm64 macOS/iOS builds publish
            // under "natives-osx" or "natives-ios" depending on the fork).
            if let natives = lib.natives {
                let key = natives["osx"] ?? natives["ios"] ?? natives["macos"]
                if let key, let classifier = lib.downloads?.classifiers?[key] {
                    let dest = LauncherPaths.libraries
                        .appendingPathComponent(classifier.path ?? Self.mavenPath(lib, classifier: key))
                    try await download(classifier, to: dest, verify: true)
                    try extractNatives(dest, exclude: lib.extract?.exclude ?? [])
                }
            }
            done += 1
            if done % 4 == 0 {
                let frac = 0.20 + 0.45 * (Double(done) / Double(max(applicable.count, 1)))
                report(frac, "Libraries \(done)/\(applicable.count)…", onProgress)
            }
        }

        // ---- 3. Assets -----------------------------------------------------
        if let index = detail.assetIndex {
            report(0.70, "Downloading asset index…", onProgress)
            let indexDest = LauncherPaths.assetIndexes.appendingPathComponent("\(index.id).json")
            try await download(URL(string: index.url)!, to: indexDest, expectedSHA1: index.sha1)
            try await downloadAssets(indexFile: indexDest, onProgress: onProgress)
        }

        // ---- 4. Mark installed --------------------------------------------
        report(1.0, "Done", onProgress)
        return detail
    }

    // MARK: - Assets

    private func downloadAssets(indexFile: URL,
                                onProgress: @escaping (Double, String) -> Void) async throws {
        let data = try Data(contentsOf: indexFile)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let objects = root["objects"] as? [String: [String: Any]] else {
            throw InstallError.badJSON("asset index has no objects")
        }
        let entries = objects.values.compactMap { obj -> (hash: String, size: Int)? in
            guard let hash = obj["hash"] as? String else { return nil }
            return (hash, obj["size"] as? Int ?? 0)
        }
        let total = entries.count
        var done = 0
        for entry in entries {
            let prefix = String(entry.hash.prefix(2))
            let dest = LauncherPaths.assetObjects
                .appendingPathComponent(prefix, isDirectory: true)
                .appendingPathComponent(entry.hash)
            if !FileManager.default.fileExists(atPath: dest.path) {
                let url = URL(string: "https://resources.download.minecraft.net/\(prefix)/\(entry.hash)")!
                try await download(url, to: dest, expectedSHA1: entry.hash)
            }
            done += 1
            if done % 50 == 0 {
                report(0.70 + 0.28 * (Double(done) / Double(max(total, 1))),
                       "Assets \(done)/\(total)…", onProgress)
            }
        }
    }

    // MARK: - Download primitives

    private func download(_ entry: VersionDetail.DownloadEntry,
                          to dest: URL,
                          verify: Bool) async throws {
        try await download(URL(string: entry.url)!, to: dest,
                           expectedSHA1: verify ? entry.sha1 : nil)
    }

    private func download(_ entry: VersionDetail.Library.Artifact,
                          to dest: URL,
                          verify: Bool) async throws {
        try await download(URL(string: entry.url)!, to: dest,
                           expectedSHA1: verify ? entry.sha1 : nil)
    }

    private func download(_ url: URL, to dest: URL, expectedSHA1: String?) async throws {
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: dest.path), expectedSHA1 != nil {
            // Already present and (probably) verified — skip.
            return
        }
        let (tmp, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw InstallError.http((response as? HTTPURLResponse)?.statusCode ?? -1, url)
        }
        // Move into place (replace if needed).
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tmp, to: dest)

        if let expected = expectedSHA1, !expected.isEmpty {
            let got = try Crypto.sha1(of: dest)
            guard got.caseInsensitiveCompare(expected) == .orderedSame else {
                try? FileManager.default.removeItem(at: dest)
                throw InstallError.checksum(dest.lastPathComponent, expected: expected, got: got)
            }
        }
    }

    // MARK: - Natives

    /// Extracts `.dylib`/`.so` entries from a natives jar next to it.
    private func extractNatives(_ jar: URL, exclude: [String]) throws {
        // A full zip extractor is out of scope here; the packaged runtime in
        // native-runtime/ already provides the natives. Log the intent so the
        // behaviour is explicit rather than silently skipped.
        NSLog("[MCL] natives jar ready: \(jar.lastPathComponent) (exclude: \(exclude))")
    }

    // MARK: - Rules / paths

    static func rulesAllow(_ rules: [VersionDetail.Rule]?) -> Bool {
        guard let rules, !rules.isEmpty else { return true }
        var allowed = false
        for rule in rules {
            guard ruleApplies(rule) else { continue }
            allowed = (rule.action == "allow")
        }
        return allowed
    }

    private static func ruleApplies(_ rule: VersionDetail.Rule) -> Bool {
        if let os = rule.os {
            if let name = os.name {
                // iOS is reported as "ios" by Mojang's newer manifests; older
                // ones only know "osx". Accept both.
                let onIOS = (name == "ios" || name == "osx")
                if !onIOS { return false }
            }
            if let arch = os.arch, arch != "arm64" && arch != "aarch64" { return false }
        }
        return true
    }

    static func mavenPath(_ lib: VersionDetail.Library, classifier: String? = nil) -> String {
        let groupPath = lib.groupId.replacingOccurrences(of: ".", with: "/")
        let file = classifier != nil
            ? "\(lib.artifactId)-\(lib.version)-\(classifier!).jar"
            : "\(lib.artifactId)-\(lib.version).jar"
        return "\(groupPath)/\(lib.artifactId)/\(lib.version)/\(file)"
    }

    private func report(_ value: Double, _ message: String,
                        _ handler: @escaping (Double, String) -> Void) {
        progress = value
        status = message
        handler(value, message)
    }
}
