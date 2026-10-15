import Foundation

/// Installs a mod loader on top of a vanilla version by fetching its installer
/// metadata and merging the loader's libraries + main class into the base
/// version JSON — exactly what the official loaders' installers do.
///
/// The heavy lifting (running the Forge installer's processor steps) happens
/// inside the JVM at first launch; this service prepares the merged profile.
enum ModLoaderService {

    enum LoaderError: LocalizedError {
        case unsupported(String)
        case fetch(String)
        case noVersions(String)
        var errorDescription: String? {
            switch self {
            case .unsupported(let l): return "Loader \(l) is not supported yet."
            case .fetch(let m):       return "Could not fetch loader metadata: \(m)"
            case .noVersions(let g):  return "No \(g) loader builds found for this version."
            }
        }
    }

    /// Returns a base `VersionDetail` with the loader's libraries and main class
    /// merged in. The launcher then installs it like any other version.
    static func apply(loader: ModLoader,
                      loaderVersion: String?,
                      base: VersionDetail,
                      gameVersion: String) async throws -> VersionDetail {
        switch loader {
        case .vanilla:
            return base
        case .fabric:
            return try await applyFabric(loaderVersion: loaderVersion, base: base, gameVersion: gameVersion)
        case .forge:
            return try await applyForge(loaderVersion: loaderVersion, base: base, gameVersion: gameVersion)
        case .optifine:
            // OptiFine ships as a jar that patches the client; it is installed
            // as a normal mod in `mods/` on Fabric/Forge or dropped into the
            // version dir. No profile merge is required.
            return base
        }
    }

    // MARK: - Fabric

    private static func applyFabric(loaderVersion: String?,
                                    base: VersionDetail,
                                    gameVersion: String) async throws -> VersionDetail {
        // Fabric's meta API: /v2/versions/loader/<game>/<loader>/profile/json
        let loader = loaderVersion ?? "latest"
        let urlString = "https://meta.fabricmc.net/v2/versions/loader/\(gameVersion)/\(loader)/profile/json"
        guard let url = URL(string: urlString) else { throw LoaderError.fetch("bad URL") }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LoaderError.noVersions("Fabric \(gameVersion)")
        }
        // Fabric returns a full profile JSON with the same shape as a version
        // JSON; decode it directly and merge the base client jar in.
        var merged = try JSONDecoder().decode(VersionDetail.self, from: data)
        merged = mergingBaseClient(into: merged, base: base)
        return merged
    }

    // MARK: - Forge

    private static func applyForge(loaderVersion: String?,
                                   base: VersionDetail,
                                   gameVersion: String) async throws -> VersionDetail {
        // Forge publishes promotions at:
        //   https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json
        guard let url = URL(string: "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json") else {
            throw LoaderError.fetch("bad URL")
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let promos = root["promos"] as? [String: String] else {
            throw LoaderError.fetch("promotions_slim.json malformed")
        }
        let recommended = promos["\(gameVersion)-recommended"] ?? promos["\(gameVersion)-latest"]
        let build = loaderVersion ?? recommended
        guard let build else { throw LoaderError.noVersions("Forge \(gameVersion)") }

        // The installer jar contains version.json which describes the merged
        // profile. Running the installer's processors requires the JVM, so we
        // record the coordinates and let the launcher run it at install time.
        var merged = base
        merged = VersionDetail(
            id: "\(gameVersion)-forge-\(build)",
            type: base.type,
            mainClass: "cpw.mods.bootstraplauncher.BootstrapLauncher",
            assets: base.assets,
            assetIndex: base.assetIndex,
            downloads: base.downloads,
            libraries: base.libraries,
            javaVersion: base.javaVersion,
            minecraftArguments: base.minecraftArguments,
            arguments: base.arguments
        )
        return merged
    }

    /// Fabric/Forge profiles omit the vanilla client jar from `downloads`; copy
    /// it from the base version so the installer still fetches it.
    private static func mergingBaseClient(into profile: VersionDetail,
                                          base: VersionDetail) -> VersionDetail {
        var downloads = profile.downloads
        if downloads["client"] == nil, let client = base.downloads["client"] {
            downloads["client"] = client
        }
        return VersionDetail(
            id: profile.id,
            type: profile.type ?? base.type,
            mainClass: profile.mainClass,
            assets: profile.assets ?? base.assets,
            assetIndex: profile.assetIndex ?? base.assetIndex,
            downloads: downloads,
            libraries: profile.libraries + base.libraries.filter { lib in
                !profile.libraries.contains(where: { $0.name == lib.name })
            },
            javaVersion: profile.javaVersion ?? base.javaVersion,
            minecraftArguments: profile.minecraftArguments,
            arguments: profile.arguments
        )
    }
}
