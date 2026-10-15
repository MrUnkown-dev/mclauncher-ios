import Foundation

/// Persists accounts. Non-secret fields live in UserDefaults as JSON; access and
/// refresh tokens are mirrored into the Keychain so a plain backup / plist dump
/// does not leak a live session.
final class AccountStore: ObservableObject {

    @Published private(set) var accounts: [Account] = []
    @Published var selectedAccountID: UUID?

    private static let accountsKey = "mcl.accounts.v1"
    private static let selectionKey = "mcl.selectedAccount"

    init() {
        load()
    }

    // MARK: - Public API

    var selectedAccount: Account? {
        guard let id = selectedAccountID else { return accounts.first }
        return accounts.first { $0.id == id } ?? accounts.first
    }

    /// Create an offline ("cracked") account. No network, works forever.
    @discardableResult
    func addOfflineAccount(username: String) -> Account {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = Account(
            type: .offline,
            username: trimmed,
            uuid: Crypto.offlineUUID(for: trimmed)
        )
        accounts.append(account)
        if selectedAccountID == nil { selectedAccountID = account.id }
        persist()
        return account
    }

    /// Store / replace a Microsoft account returned by `MicrosoftAuth`.
    func upsertMicrosoftAccount(_ account: Account) {
        if let idx = accounts.firstIndex(where: { $0.uuid == account.uuid && $0.type == .microsoft }) {
            var merged = account
            merged.id = accounts[idx].id
            accounts[idx] = merged
        } else {
            accounts.append(account)
        }
        persist()
    }

    func update(_ account: Account) {
        guard let idx = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[idx] = account
        persist()
    }

    func remove(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        if selectedAccountID == account.id { selectedAccountID = accounts.first?.id }
        Keychain.delete(service: Self.tokenService, account: account.uuid)
        persist()
    }

    func select(_ account: Account) {
        selectedAccountID = account.id
        UserDefaults.standard.set(account.id.uuidString, forKey: Self.selectionKey)
    }

    // MARK: - Persistence

    private static let tokenService = "com.example.mclauncher.tokens"

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.accountsKey),
           let decoded = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = decoded.map { acct in
                var a = acct
                if let blob = Keychain.load(service: Self.tokenService, account: acct.uuid),
                   let tokens = try? JSONDecoder().decode(StoredTokens.self, from: blob) {
                    a.accessToken = tokens.accessToken
                    a.refreshToken = tokens.refreshToken
                }
                return a
            }
        }
        if let s = UserDefaults.standard.string(forKey: Self.selectionKey),
           let id = UUID(uuidString: s), accounts.contains(where: { $0.id == id }) {
            selectedAccountID = id
        } else {
            selectedAccountID = accounts.first?.id
        }
    }

    private func persist() {
        // Strip tokens from the JSON copy; they go to the Keychain instead.
        let sanitized = accounts.map { acct -> Account in
            var a = acct
            a.accessToken = nil
            a.refreshToken = nil
            return a
        }
        if let data = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(data, forKey: Self.accountsKey)
        }
        for acct in accounts where acct.type == .microsoft {
            let tokens = StoredTokens(accessToken: acct.accessToken, refreshToken: acct.refreshToken)
            if let blob = try? JSONEncoder().encode(tokens) {
                Keychain.save(service: Self.tokenService, account: acct.uuid, data: blob)
            }
        }
    }

    private struct StoredTokens: Codable {
        let accessToken: String?
        let refreshToken: String?
    }
}
