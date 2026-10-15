import Foundation

/// One entry from Mojang's `version_manifest_v2.json`.
struct MinecraftVersion: Identifiable, Codable, Hashable {
    let id: String
    let type: String          // "release" | "snapshot" | "old_beta" | "old_alpha"
    let url: String           // per-version JSON
    let time: String?
    let releaseTime: String?
    let sha1: String?
    let complianceLevel: Int?

    var isRelease: Bool { type == "release" }
    var isSnapshot: Bool { type == "snapshot" }

    /// Human-friendly type badge.
    var typeLabel: String {
        switch type {
        case "release":   return "Release"
        case "snapshot":  return "Snapshot"
        case "old_beta":  return "Beta"
        case "old_alpha": return "Alpha"
        default:          return type.capitalized
        }
    }
}

/// The version manifest itself.
struct VersionManifest: Codable {
    let latest: Latest
    let versions: [MinecraftVersion]

    struct Latest: Codable {
        let release: String
        let snapshot: String
    }
}

/// The per-version JSON (downloads, libraries, asset index, main class, args).
/// Only the parts the launcher actually reads are modelled.
struct VersionDetail: Codable {
    let id: String
    let type: String?
    let mainClass: String
    let assets: String?
    let assetIndex: AssetIndex?
    let downloads: [String: DownloadEntry]
    let libraries: [Library]
    let javaVersion: JavaVersion?
    /// Legacy (≤1.12) argument form.
    let minecraftArguments: String?
    /// Modern (≥1.13) argument form.
    let arguments: Arguments?

    struct AssetIndex: Codable {
        let id: String
        let sha1: String
        let size: Int
        let totalSize: Int?
        let url: String
    }

    struct JavaVersion: Codable {
        let component: String?
        let majorVersion: Int
    }

    struct Arguments: Codable {
        let game: [ArgumentValue]?
        let jvm: [ArgumentValue]?
    }

    /// An argument is either a bare string or a conditional object.
    enum ArgumentValue: Codable, Hashable {
        case string(String)
        case conditional(rules: [Rule], value: RuleValue)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) {
                self = .string(s)
                return
            }
            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            let rules = try keyed.decodeIfPresent([Rule].self, forKey: .rules) ?? []
            let value = try keyed.decode(RuleValue.self, forKey: .value)
            self = .conditional(rules: rules, value: value)
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .string(let s):
                var c = encoder.singleValueContainer(); try c.encode(s)
            case .conditional(let rules, let value):
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(rules, forKey: .rules)
                try c.encode(value, forKey: .value)
            }
        }

        enum CodingKeys: String, CodingKey { case rules, value }
    }

    enum RuleValue: Codable, Hashable {
        case single(String)
        case many([String])

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .single(s); return }
            self = .many(try c.decode([String].self))
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .single(let s): try c.encode(s)
            case .many(let a):   try c.encode(a)
            }
        }

        var values: [String] {
            switch self {
            case .single(let s): return [s]
            case .many(let a):   return a
            }
        }
    }

    struct Rule: Codable, Hashable {
        let action: String            // "allow" | "disallow"
        let os: OS?
        let features: [String: Bool]?

        struct OS: Codable, Hashable {
            let name: String?
            let version: String?
            let arch: String?
        }
    }

    struct DownloadEntry: Codable {
        let sha1: String?
        let size: Int?
        let url: String
    }

    struct Library: Codable {
        let name: String
        let downloads: Downloads?
        let natives: [String: String]?
        let rules: [Rule]?
        let extract: Extract?
        let url: String?

        struct Downloads: Codable {
            let artifact: Artifact?
            let classifiers: [String: Artifact]?
        }

        struct Artifact: Codable {
            let path: String?
            let sha1: String?
            let size: Int?
            let url: String
        }

        struct Extract: Codable {
            let exclude: [String]?
        }

        /// Maven coordinate helpers: group:artifact:version
        var groupId: String    { name.components(separatedBy: ":")[safe: 0] ?? "" }
        var artifactId: String { name.components(separatedBy: ":")[safe: 1] ?? "" }
        var version: String    { name.components(separatedBy: ":")[safe: 2] ?? "" }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
