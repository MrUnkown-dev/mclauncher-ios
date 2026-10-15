import Foundation

// MARK: - Project types

/// The kinds of content Modrinth hosts that this launcher installs.
enum ModrinthProjectType: String, CaseIterable, Identifiable {
    case mod
    case resourcepack
    case shader
    case datapack
    case modpack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mod:          return "Mods"
        case .resourcepack: return "Resource Packs"
        case .shader:       return "Shaders"
        case .datapack:     return "Datapacks"
        case .modpack:      return "Modpacks"
        }
    }

    var singularName: String {
        switch self {
        case .mod:          return "mod"
        case .resourcepack: return "resource pack"
        case .shader:       return "shader"
        case .datapack:     return "datapack"
        case .modpack:      return "modpack"
        }
    }

    var systemImage: String {
        switch self {
        case .mod:          return "shippingbox.fill"
        case .resourcepack: return "paintpalette.fill"
        case .shader:       return "sparkles"
        case .datapack:     return "square.stack.3d.down.right.fill"
        case .modpack:      return "shippingbox.and.arrow.backward.fill"
        }
    }

    /// Where a downloaded file lands inside an instance. `nil` for modpacks,
    /// which create a whole new instance instead.
    var destinationCategory: InstanceFileManager.FileCategory? {
        switch self {
        case .mod:          return .mods
        case .resourcepack: return .resourcepacks
        case .shader:       return .shaderpacks
        case .datapack:     return .datapacks
        case .modpack:      return nil
        }
    }

    /// Whether a loader filter makes sense (mods and modpacks are loader-specific).
    var usesLoaderFilter: Bool { self == .mod || self == .modpack }
}

// MARK: - Search

struct ModrinthSearchResult: Codable {
    let hits: [ModrinthProject]
    let offset: Int
    let limit: Int
    let total_hits: Int
}

/// A project as returned by `/search`. Field names mirror the API verbatim.
struct ModrinthProject: Codable, Identifiable, Hashable {
    let project_id: String
    let project_type: String
    let slug: String
    let author: String
    let title: String
    let description: String
    let categories: [String]
    let display_categories: [String]?
    let versions: [String]
    let downloads: Int
    let follows: Int
    let icon_url: String?
    let date_created: String
    let date_modified: String
    let latest_version: String?
    let license: String
    let client_side: String
    let server_side: String
    let color: Int?

    var id: String { project_id }

    var iconURL: URL? { icon_url.flatMap(URL.init(string:)) }

    var downloadsText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: downloads)) ?? "\(downloads)"
    }

    /// Modrinth's brand colour, used for a subtle accent.
    var accent: String { color.map { String(format: "#%06X", $0) } ?? "#1BD96A" }

    static func == (lhs: ModrinthProject, rhs: ModrinthProject) -> Bool {
        lhs.project_id == rhs.project_id
    }

    func hash(into hasher: inout Hasher) { hasher.combine(project_id) }
}

// MARK: - Versions

struct ModrinthVersion: Codable, Identifiable, Hashable {
    let id: String
    let project_id: String
    let name: String
    let version_number: String
    let version_type: String        // release | beta | alpha
    let game_versions: [String]
    let loaders: [String]
    let downloads: Int
    let date_published: String
    let files: [ModrinthFile]
    let dependencies: [ModrinthDependency]

    /// The file the launcher should download (Modrinth marks one as primary).
    var primaryFile: ModrinthFile? {
        files.first { $0.primary } ?? files.first
    }

    var publishedDate: Date? {
        ISO8601DateFormatter().date(from: date_published)
    }

    var typeLabel: String {
        switch version_type {
        case "release": return "Release"
        case "beta":    return "Beta"
        case "alpha":   return "Alpha"
        default:        return version_type.capitalized
        }
    }

    static func == (lhs: ModrinthVersion, rhs: ModrinthVersion) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ModrinthFile: Codable, Hashable {
    let hashes: [String: String]
    let url: String
    let filename: String
    let primary: Bool
    let size: Int
    let file_type: String?

    var sha1: String? { hashes["sha1"] }
}

struct ModrinthDependency: Codable, Hashable {
    let version_id: String?
    let project_id: String?
    let dependency_type: String    // required | optional | incompatible | embedded
}

// MARK: - Modpack index (`modrinth.index.json` inside a .mrpack)

/// The manifest at the root of a `.mrpack`. Everything needed to build an
/// instance lives here: the game/loader versions, the files to download, and
/// the dependency map.
struct ModrinthIndex: Codable {
    let formatVersion: Int
    let game: String
    let versionId: String
    let name: String
    let summary: String?
    let files: [IndexFile]
    /// e.g. ["minecraft": "1.20.1", "fabric-loader": "0.15.11"]
    let dependencies: [String: String]

    struct IndexFile: Codable {
        /// Path relative to the instance directory, e.g. "mods/sodium.jar".
        let path: String
        let hashes: [String: String]
        /// e.g. ["client": "required", "server": "unsupported"]
        let env: [String: String]?
        let downloads: [String]
        let fileSize: Int
    }
}
