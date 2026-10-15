import Foundation
import CommonCrypto
import Security

/// Crypto helpers the launcher needs. Everything here is public, deterministic
/// and matches what the official launcher / server expects.
enum Crypto {

    /// Java's `UUID.nameUUIDFromBytes` (a.k.a. UUIDv3, MD5-based).
    /// Minecraft derives offline player UUIDs as
    /// `UUID.nameUUIDFromBytes(("OfflinePlayer:" + name).getBytes(UTF_8))`,
    /// so we must reproduce it byte-for-byte to get the same player identity.
    static func offlineUUID(for username: String) -> String {
        let data = Data(("OfflinePlayer:" + username).utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_MD5(buf.baseAddress, CC_LONG(data.count), &digest)
        }
        // Set version (3) and variant (IETF) bits, per RFC 4122.
        digest[6] = (digest[6] & 0x0F) | 0x30
        digest[8] = (digest[8] & 0x3F) | 0x80

        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return [
            String(hex.prefix(8)),
            String(hex.dropFirst(8).prefix(4)),
            String(hex.dropFirst(12).prefix(4)),
            String(hex.dropFirst(16).prefix(4)),
            String(hex.dropFirst(20).prefix(12))
        ].joined(separator: "-")
    }

    /// SHA-1 of a file, used to verify every downloaded artifact.
    static func sha1(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var context = CC_SHA1_CTX()
        CC_SHA1_Init(&context)
        while autoreleasepool(invoking: {
            let chunk = try? handle.read(upToCount: 1 << 20)
            guard let chunk, !chunk.isEmpty else { return false }
            chunk.withUnsafeBytes { _ = CC_SHA1_Update(&context, $0.baseAddress, CC_LONG(chunk.count)) }
            return true
        }) {}

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        CC_SHA1_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// A random UUID string, for client tokens and instance ids.
    static func randomUUID() -> String { UUID().uuidString.lowercased() }

    /// Fresh client token for the offline session (`-Dminecraft.client.token`).
    static func randomClientToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
