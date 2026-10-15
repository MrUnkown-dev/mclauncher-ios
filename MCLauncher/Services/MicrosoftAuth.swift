import Foundation

/// Microsoft → Xbox Live → Minecraft authentication, using the OAuth 2.0
/// **device code** flow. Device code is used (instead of an embedded web view)
/// because it needs no redirect URI and therefore works with a free Apple ID
/// signing profile — there is no associated-domain or URL-scheme requirement.
///
/// Flow:
///   1. Ask Microsoft for a device code, show `userCode` + `verificationUri`.
///   2. Poll the token endpoint until the user finishes signing in.
///   3. Trade the Microsoft token for an Xbox Live token, then an XSTS token.
///   4. Trade the XSTS token for a Minecraft access token.
///   5. Fetch the Minecraft profile (name + uuid).
final class MicrosoftAuth {

    /// Public client id used by the official Minecraft launcher. It is not a
    /// secret — it identifies the *application*, and users authenticate in their
    /// own browser, so it is safe to ship.
    static let clientID = "00000000402b5328"
    static let scope = "XboxLive.signin offline_access"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    enum AuthError: LocalizedError {
        case http(Int, String)
        case missingField(String)
        case xbox(String)
        case noMinecraftOwnership
        case cancelled

        var errorDescription: String? {
            switch self {
            case .http(let code, let body): return "HTTP \(code): \(body.prefix(200))"
            case .missingField(let f):      return "Auth response missing \(f)"
            case .xbox(let msg):            return "Xbox Live: \(msg)"
            case .noMinecraftOwnership:     return "This Microsoft account does not own Minecraft: Java Edition."
            case .cancelled:                return "Sign-in cancelled."
            }
        }
    }

    // MARK: - Step 1: device code

    struct DeviceCode {
        let deviceCode: String
        let userCode: String
        let verificationURI: URL
        let expiresIn: Int
        let interval: Int
        let message: String
    }

    func requestDeviceCode() async throws -> DeviceCode {
        let url = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form([
            "client_id": Self.clientID,
            "scope": Self.scope
        ])

        let (data, response) = try await session.data(for: req)
        try Self.check(response, data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        guard let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let uriString = json["verification_uri"] as? String,
              let uri = URL(string: uriString) else {
            throw AuthError.missingField("device_code/user_code/verification_uri")
        }

        return DeviceCode(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: uri,
            expiresIn: json["expires_in"] as? Int ?? 900,
            interval: json["interval"] as? Int ?? 5,
            message: json["message"] as? String ?? "Go to \(uriString) and enter \(userCode)"
        )
    }

    // MARK: - Step 2: poll for the Microsoft token

    struct MicrosoftTokens {
        let accessToken: String
        let refreshToken: String?
    }

    /// Polls until the user completes sign-in, the code expires, or `isCancelled`
    /// returns true. `onTick` is called with a status string for the UI.
    func pollForTokens(deviceCode: DeviceCode,
                       isCancelled: () -> Bool,
                       onTick: (String) -> Void) async throws -> MicrosoftTokens {
        let url = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!
        let deadline = Date().addingTimeInterval(TimeInterval(deviceCode.expiresIn))
        var interval = max(deviceCode.interval, 2)

        while Date() < deadline {
            if isCancelled() { throw AuthError.cancelled }
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = form([
                "client_id": Self.clientID,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "device_code": deviceCode.deviceCode
            ])

            let (data, _) = try await session.data(for: req)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            if let access = json["access_token"] as? String {
                return MicrosoftTokens(accessToken: access, refreshToken: json["refresh_token"] as? String)
            }

            switch json["error"] as? String {
            case "authorization_pending":
                onTick("Waiting for you to sign in…")
            case "slow_down":
                interval += 5
                onTick("Slowing down…")
            case "expired_token":
                throw AuthError.http(400, "device code expired")
            case "authorization_declined":
                throw AuthError.cancelled
            case let other?:
                throw AuthError.http(400, other)
            case nil:
                onTick("Waiting for you to sign in…")
            }
        }
        throw AuthError.http(408, "device code expired")
    }

    // MARK: - Step 3: refresh an existing session

    func refreshMicrosoftTokens(refreshToken: String) async throws -> MicrosoftTokens {
        let url = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form([
            "client_id": Self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": Self.scope
        ])
        let (data, response) = try await session.data(for: req)
        try Self.check(response, data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let access = json["access_token"] as? String else {
            throw AuthError.missingField("access_token")
        }
        return MicrosoftTokens(accessToken: access, refreshToken: json["refresh_token"] as? String)
    }

    // MARK: - Step 4: Xbox Live → XSTS → Minecraft

    func authenticateXbox(microsoftAccessToken: String) async throws -> (xbl: String, uhs: String, xuid: String) {
        // 4a. Xbox Live user token
        let xblURL = URL(string: "https://user.auth.xboxlive.com/user/authenticate")!
        let xblBody: [String: Any] = [
            "Properties": [
                "AuthMethod": "RPS",
                "SiteName": "user.auth.xboxlive.com",
                "RpsTicket": "d=\(microsoftAccessToken)"
            ],
            "RelyingParty": "http://auth.xboxlive.com",
            "TokenType": "JWT"
        ]
        let xblJSON = try await postJSON(xblURL, body: xblBody)
        guard let xblToken = xblJSON["Token"] as? String,
              let displayClaims = xblJSON["DisplayClaims"] as? [String: Any],
              let xui = displayClaims["xui"] as? [[String: Any]],
              let uhs = xui.first?["uhs"] as? String else {
            throw AuthError.missingField("Xbox Live Token/uhs")
        }

        // 4b. XSTS token (relying party = Minecraft)
        let xstsURL = URL(string: "https://xsts.auth.xboxlive.com/xsts/authorize")!
        let xstsBody: [String: Any] = [
            "Properties": ["SandboxId": "RETAIL", "UserTokens": [xblToken]],
            "RelyingParty": "rp://api.minecraftservices.com/",
            "TokenType": "JWT"
        ]
        let xstsJSON = try await postJSON(xstsURL, body: xstsBody)

        if let xerr = xstsJSON["XErr"] as? Int {
            throw AuthError.xbox(Self.explainXErr(xerr))
        }
        guard let xstsToken = xstsJSON["Token"] as? String,
              let claims = xstsJSON["DisplayClaims"] as? [String: Any],
              let xui2 = claims["xui"] as? [[String: Any]],
              let xuid = xui2.first?["xid"] as? String else {
            throw AuthError.missingField("XSTS Token/xid")
        }
        return (xstsToken, uhs, xuid)
    }

    func authenticateMinecraft(uhs: String, xstsToken: String) async throws -> (token: String, expiresIn: Int) {
        let url = URL(string: "https://api.minecraftservices.com/authentication/login_with_xbox")!
        let body: [String: Any] = ["identityToken": "XBL3.0 x=\(uhs);\(xstsToken)"]
        let json = try await postJSON(url, body: body)
        guard let token = json["access_token"] as? String else {
            throw AuthError.missingField("Minecraft access_token")
        }
        return (token, json["expires_in"] as? Int ?? 86400)
    }

    func fetchProfile(minecraftToken: String) async throws -> (name: String, uuid: String) {
        let url = URL(string: "https://api.minecraftservices.com/minecraft/profile")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(minecraftToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw AuthError.noMinecraftOwnership
        }
        try Self.check(response, data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let name = json["name"] as? String, let uuid = json["id"] as? String else {
            throw AuthError.missingField("profile name/id")
        }
        return (name, uuid)
    }

    // MARK: - Full pipeline

    /// Runs steps 3→5 starting from a Microsoft access token, returning a ready
    /// `Account`. Used both after device-code sign-in and after a refresh.
    func buildAccount(microsoftAccessToken: String,
                      refreshToken: String?) async throws -> Account {
        let xbox = try await authenticateXbox(microsoftAccessToken: microsoftAccessToken)
        let mc = try await authenticateMinecraft(uhs: xbox.uhs, xstsToken: xbox.xbl)
        let profile = try await fetchProfile(minecraftToken: mc.token)

        return Account(
            type: .microsoft,
            username: profile.name,
            uuid: profile.uuid,
            accessToken: mc.token,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(mc.expiresIn)),
            xuid: xbox.xuid
        )
    }

    /// Refreshes an account in place, returning the updated copy.
    func refresh(account: Account) async throws -> Account {
        guard let rt = account.refreshToken else { throw AuthError.missingField("refresh_token") }
        let ms = try await refreshMicrosoftTokens(refreshToken: rt)
        var updated = try await buildAccount(microsoftAccessToken: ms.accessToken,
                                             refreshToken: ms.refreshToken ?? rt)
        updated.id = account.id
        return updated
    }

    // MARK: - Helpers

    private func postJSON(_ url: URL, body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        try Self.check(response, data)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func form(_ pairs: [String: String]) -> Data {
        pairs.map { "\($0.key)=\(Self.escape($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }

    private static func escape(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        throw AuthError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
    }

    private static func explainXErr(_ code: Int) -> String {
        switch code {
        case 2148916233: return "No Xbox account yet — create one at xbox.com first."
        case 2148916235: return "Xbox Live is not available in your region."
        case 2148916238: return "Child account — an adult must add you to a Microsoft Family."
        default:         return "unknown error \(code)"
        }
    }
}
