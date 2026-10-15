import Foundation

/// Fetches Mojang's version manifest and per-version JSON.
final class VersionManifestService {

    static let manifestURL = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!

    private let session: URLSession
    private let cacheURL: URL

    init(session: URLSession = .shared) {
        self.session = session
        let dir = LauncherPaths.root
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheURL = dir.appendingPathComponent("version_manifest_v2.json")
    }

    /// Returns the cached manifest when offline, otherwise refreshes it.
    func loadManifest(allowCache: Bool = true) async throws -> VersionManifest {
        do {
            let (data, _) = try await session.data(from: Self.manifestURL)
            try? data.write(to: cacheURL)
            return try JSONDecoder().decode(VersionManifest.self, from: data)
        } catch {
            if allowCache, let data = try? Data(contentsOf: cacheURL) {
                return try JSONDecoder().decode(VersionManifest.self, from: data)
            }
            throw error
        }
    }

    /// Downloads (or reads the cached) detail JSON for one version.
    func loadDetail(for version: MinecraftVersion) async throws -> VersionDetail {
        let cached = LauncherPaths.versionDir(version.id).appendingPathComponent("\(version.id).json")
        if FileManager.default.fileExists(atPath: cached.path),
           let data = try? Data(contentsOf: cached),
           let detail = try? JSONDecoder().decode(VersionDetail.self, from: data) {
            return detail
        }
        let (data, _) = try await session.data(from: URL(string: version.url)!)
        try? FileManager.default.createDirectory(at: cached.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: cached)
        return try JSONDecoder().decode(VersionDetail.self, from: data)
    }
}
