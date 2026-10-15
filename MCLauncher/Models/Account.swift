import Foundation

/// How an account authenticates.
enum AccountType: String, Codable, CaseIterable, Identifiable {
    /// Local-only account. Joins servers in `online-mode=false` and singleplayer.
    case offline
    /// Real Microsoft / Xbox Live account, joins online-mode servers.
    case microsoft

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .offline:   return "Offline (cracked)"
        case .microsoft: return "Microsoft"
        }
    }
}

/// A single launcher account. Tokens are stored in the Keychain by `AccountStore`
/// and are kept out of the persisted JSON where possible.
struct Account: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: AccountType
    /// In-game player name (for offline accounts this is what the user typed).
    var username: String
    /// Canonical dashed UUID string, e.g. "069a79f4-44e9-4726-a5be-fca90e38aaf5".
    var uuid: String
    /// Mojang-issued Minecraft access token (online accounts only).
    var accessToken: String?
    /// Microsoft OAuth refresh token (online accounts only).
    var refreshToken: String?
    /// When `accessToken` stops being valid.
    var expiresAt: Date?
    /// Xbox user id, used for telemetry + some mod loaders.
    var xuid: String?
    /// Xbox gamertag (may differ from `username`).
    var xboxGamertag: String?
    /// True for the account the launcher should preselect.
    var isDefault: Bool = false

    var uuidUndashed: String { uuid.replacingOccurrences(of: "-", with: "") }

    var needsRefresh: Bool {
        guard type == .microsoft else { return false }
        guard let expiresAt else { return true }
        return expiresAt.timeIntervalSinceNow < 60
    }

    /// Skins come from Mojang's public session server for online accounts.
    var skinURL: URL? {
        URL(string: "https://crafatar.com/skins/\(uuidUndashed)")
    }
}
