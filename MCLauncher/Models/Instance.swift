import Foundation

/// A game profile the user can launch: a version, optional mod loader, its own
/// game directory, and any loader-specific settings.
struct Instance: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// Base Minecraft version id, e.g. "1.20.4".
    var gameVersion: String
    /// Which loader to install on top of the vanilla version.
    var loader: ModLoader = .vanilla
    /// Exact loader build, e.g. "0.15.11" for Fabric or "47.2.0" for Forge.
    var loaderVersion: String?
    /// Whether the version files have finished downloading.
    var isInstalled: Bool = false
    /// Relative folder under the launcher's `instances/` root.
    var gameDirectory: String
    /// Optional icon (system symbol name).
    var iconName: String = "cube.fill"

    init(name: String,
         gameVersion: String,
         loader: ModLoader = .vanilla,
         loaderVersion: String? = nil,
         gameDirectory: String? = nil) {
        self.name = name
        self.gameVersion = gameVersion
        self.loader = loader
        self.loaderVersion = loaderVersion
        self.gameDirectory = gameDirectory ?? Instance.slug(name)
    }

    static func slug(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return s.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars.filter { allowed.contains($0) }
            .map(String.init)
            .joined()
    }

    /// Fabric's version id is `<game>-fabric-<loader>`; Forge uses `<game>-forge-<build>`.
    var resolvedVersionId: String {
        switch loader {
        case .vanilla: return gameVersion
        case .fabric:  return "\(gameVersion)-fabric-\(loaderVersion ?? "latest")"
        case .forge:   return "\(gameVersion)-forge-\(loaderVersion ?? "latest")"
        case .optifine:return "\(gameVersion)-OptiFine"
        }
    }
}

/// Supported mod loaders.
enum ModLoader: String, Codable, CaseIterable, Identifiable {
    case vanilla
    case fabric
    case forge
    case optifine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vanilla:  return "Vanilla"
        case .fabric:   return "Fabric"
        case .forge:    return "Forge"
        case .optifine: return "OptiFine"
        }
    }

    var iconName: String {
        switch self {
        case .vanilla:  return "cube.fill"
        case .fabric:   return "square.stack.3d.up.fill"
        case .forge:    return "hammer.fill"
        case .optifine: return "sparkles"
        }
    }
}

/// Result of a finished game session, used for the session summary UI.
struct LaunchResult {
    let exitCode: Int32
    let duration: TimeInterval
    let instanceName: String

    var succeeded: Bool { exitCode == 0 }
}
