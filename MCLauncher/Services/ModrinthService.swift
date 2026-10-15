import Foundation

/// Modrinth API v2 client plus the install logic for mods, resource packs,
/// shaders, datapacks and modpacks.
///
/// Every install targets a specific instance's own game directory, so content
/// never leaks between instances. Modpacks go further: they create a brand new
/// instance (their own `minecraft/instances/<slug>` folder) with the right game
/// and loader versions already set.
final class ModrinthService {

    static let shared = ModrinthService()

    private static let base = URL(string: "https://api.modrinth.com/v2")!

    /// Modrinth asks clients to identify themselves with a descriptive
    /// User-Agent. Sending one is a requirement, not a nicety.
    private static let userAgent = "MCLauncher/1.0.0 (iOS Minecraft launcher; +https://github.com/)"

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    enum ModrinthError: LocalizedError {
        case http(Int, String)
        case badResponse(String)
        case noFiles
        case invalidModpack(String)
        case checksum(String)
        case noInstance

        var errorDescription: String? {
            switch self {
            case .http(let code, let body):   return "Modrinth HTTP \(code): \(body.prefix(160))"
            case .badResponse(let what):      return "Unexpected Modrinth response: \(what)"
            case .noFiles:                    return "This version has no downloadable files."
            case .invalidModpack(let why):    return "Invalid modpack: \(why)"
            case .checksum(let file):         return "Checksum mismatch for \(file) — the download may be corrupt."
            case .noInstance:                 return "No instance selected."
            }
        }
    }

    // MARK: - Search

    /// Search Modrinth. `gameVersion` and `loader` narrow results to what the
    /// target instance can actually run.
    func search(query: String,
                type: ModrinthProjectType,
                gameVersion: String? = nil,
                loader: String? = nil,
                offset: Int = 0,
                limit: Int = 20) async throws -> ModrinthSearchResult {

        var facets: [[String]] = [["project_type:\(type.rawValue)"]]
        if let gameVersion, !gameVersion.isEmpty {
            facets.append(["versions:\(gameVersion)"])
        }
        if type.usesLoaderFilter, let loader, !loader.isEmpty {
            facets.append(["categories:\(loader)"])
        }

        let facetData = try JSONSerialization.data(withJSONObject: facets)
        let facetString = String(decoding: facetData, as: UTF8.self)

        var components = URLComponents(url: Self.base.appendingPathComponent("search"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "facets", value: facetString),
            URLQueryItem(name: "index", value: query.isEmpty ? "downloads" : "relevance"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]

        let data = try await get(components.url!)
        return try decode(ModrinthSearchResult.self, from: data)
    }

    // MARK: - Versions

    /// All versions of a project, filtered to the instance's game version and
    /// loader so the list only shows things that will actually work.
    func versions(projectID: String,
                  gameVersion: String? = nil,
                  loader: String? = nil) async throws -> [ModrinthVersion] {

        var components = URLComponents(
            url: Self.base.appendingPathComponent("project/\(projectID)/version"),
            resolvingAgainstBaseURL: false)!

        var items: [URLQueryItem] = []
        if let gameVersion, !gameVersion.isEmpty {
            items.append(URLQueryItem(name: "game_versions", value: "[\"\(gameVersion)\"]"))
        }
        if let loader, !loader.isEmpty {
            items.append(URLQueryItem(name: "loaders", value: "[\"\(loader)\"]"))
        }
        if !items.isEmpty { components.queryItems = items }

        let data = try await get(components.url!)
        return try decode([ModrinthVersion].self, from: data)
    }

    // MARK: - Installing a single file into an instance

    /// Download one version's primary file into the instance's category folder.
    /// Returns the written URL.
    @discardableResult
    func install(version: ModrinthVersion,
                 into instance: Instance,
                 as category: InstanceFileManager.FileCategory,
                 onProgress: @escaping (Double) -> Void = { _ in }) async throws -> URL {

        guard let file = version.primaryFile, let url = URL(string: file.url) else {
            throw ModrinthError.noFiles
        }
        let directory = InstanceFileManager.categoryURL(category, instance: instance)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = InstanceFileManager.uniqueDestination(for: file.filename, in: directory)
        onProgress(0.1)
        try await download(url, to: destination, expectedSHA1: file.sha1)
        onProgress(1.0)
        return destination
    }

    // MARK: - Installing a modpack

    struct ModpackResult {
        let instance: Instance
        let downloadedFiles: Int
        let skippedFiles: Int
    }

    /// Install a `.mrpack`: create a new instance, download every file the index
    /// lists into that instance, then lay its overrides on top.
    func installModpack(version: ModrinthVersion,
                        name: String,
                        onProgress: @escaping (String, Double) -> Void) async throws -> ModpackResult {

        guard let file = version.primaryFile, let url = URL(string: file.url) else {
            throw ModrinthError.noFiles
        }

        // 1. Fetch the .mrpack to a temporary file.
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(file.filename)")
        defer { try? FileManager.default.removeItem(at: temp) }
        onProgress("Downloading modpack…", 0.02)
        try await download(url, to: temp, expectedSHA1: file.sha1)

        // 2. Read modrinth.index.json out of the archive.
        let archive = try Data(contentsOf: temp, options: .mappedIfSafe)
        let entries = try ZipArchive.entries(in: archive)
        guard let indexEntry = entries.first(where: { $0.path == "modrinth.index.json" }) else {
            throw ModrinthError.invalidModpack("modrinth.index.json is missing")
        }
        let indexData = try ZipArchive.extract(indexEntry, from: archive)
        let index = try decode(ModrinthIndex.self, from: indexData)

        // 3. Build the instance from the pack's dependencies.
        let gameVersion = index.dependencies["minecraft"] ?? "1.20.1"
        let loader = ModLoader.fromModrinth(index.dependencies)
        let loaderVersion = index.dependencies["fabric-loader"]
            ?? index.dependencies["quilt-loader"]
            ?? index.dependencies["forge"]
            ?? index.dependencies["neoforge"]

        var instance = Instance(name: name.isEmpty ? index.name : name,
                                gameVersion: gameVersion,
                                loader: loader,
                                loaderVersion: loaderVersion)
        // Never collide with an existing instance's folder.
        instance.gameDirectory = uniqueInstanceSlug(from: instance.gameDirectory)

        InstanceFileManager.bootstrap(instance: instance)
        let root = InstanceFileManager.instanceURL(instance)

        // 4. Download every indexed file into the instance.
        let total = max(index.files.count, 1)
        var downloaded = 0
        var skipped = 0

        for (offset, entry) in index.files.enumerated() {
            // Respect the pack's client/server side markers.
            if entry.env?["client"] == "unsupported" {
                skipped += 1
                continue
            }
            guard let downloadURL = entry.downloads.first.flatMap(URL.init(string:)) else {
                skipped += 1
                continue
            }
            let destination = try safeInstancePath(root: root, relative: entry.path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                skipped += 1
                continue
            }
            try await download(downloadURL, to: destination, expectedSHA1: entry.hashes["sha1"])
            downloaded += 1
            onProgress("Downloading files \(offset + 1)/\(index.files.count)…",
                       0.05 + 0.90 * (Double(offset + 1) / Double(total)))
        }

        // 5. Overlay the pack's overrides (and client-overrides) on top.
        onProgress("Applying overrides…", 0.97)
        try ZipArchive.extract(from: temp, entriesMatching: "overrides/",
                               strippingPrefix: true, to: root)
        try ZipArchive.extract(from: temp, entriesMatching: "client-overrides/",
                               strippingPrefix: true, to: root)

        // Make sure the standard folders exist even if the pack omitted them.
        InstanceFileManager.bootstrap(instance: instance)

        onProgress("Done", 1.0)
        return ModpackResult(instance: instance, downloadedFiles: downloaded, skippedFiles: skipped)
    }

    // MARK: - Networking

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data)
        return data
    }

    private func download(_ url: URL, to destination: URL, expectedSHA1: String?) async throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (temporary, response) = try await session.download(for: request)
        try Self.check(response, nil)

        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try? fm.removeItem(at: destination)
        }
        try fm.moveItem(at: temporary, to: destination)

        if let expectedSHA1, !expectedSHA1.isEmpty {
            let actual = try Crypto.sha1(of: destination)
            guard actual.caseInsensitiveCompare(expectedSHA1) == .orderedSame else {
                try? fm.removeItem(at: destination)
                throw ModrinthError.checksum(destination.lastPathComponent)
            }
        }
    }

    private static func check(_ response: URLResponse, _ body: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let text = body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw ModrinthError.http(http.statusCode, text)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ModrinthError.badResponse(String(describing: error))
        }
    }

    // MARK: - Helpers

    /// Reject `..` traversal from an untrusted modpack index.
    private func safeInstancePath(root: URL, relative: String) throws -> URL {
        let normalized = relative.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true)
        guard !normalized.hasPrefix("/"), !parts.contains("..") else {
            throw ModrinthError.invalidModpack("unsafe path \(relative)")
        }
        return root.appendingPathComponent(normalized)
    }

    private func uniqueInstanceSlug(from base: String) -> String {
        let fm = FileManager.default
        var candidate = base
        var index = 1
        while fm.fileExists(atPath: LauncherPaths.instanceDir(candidate).path) {
            candidate = "\(base)-\(index)"
            index += 1
        }
        return candidate
    }
}

// MARK: - Loader mapping

extension ModLoader {
    /// The loader name Modrinth uses in search facets and version filters.
    var modrinthLoader: String? {
        switch self {
        case .vanilla:  return nil
        case .fabric:   return "fabric"
        case .forge:    return "forge"
        case .optifine: return nil
        }
    }

    /// Infer a loader from a modpack's dependency map.
    static func fromModrinth(_ dependencies: [String: String]) -> ModLoader {
        if dependencies["fabric-loader"] != nil { return .fabric }
        // Quilt is Fabric-compatible for our purposes; the loader install step
        // will fetch Quilt's own profile when present.
        if dependencies["quilt-loader"] != nil { return .fabric }
        if dependencies["forge"] != nil { return .forge }
        if dependencies["neoforge"] != nil { return .forge }
        return .vanilla
    }
}
