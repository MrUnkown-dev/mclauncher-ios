import Foundation
import Compression

/// A minimal, dependency-free ZIP reader.
///
/// The launcher needs to read `.mrpack` modpacks (which are ZIPs) and the
/// occasional zipped resource pack, and iOS ships no public ZIP API. Rather than
/// pull in a third-party package — which would complicate the free-Apple-ID
/// signing flow — this implements just enough of the format: the End Of Central
/// Directory, the central directory, local file headers, and raw DEFLATE via the
/// `Compression` framework.
///
/// Limitations (documented, not hidden): ZIP64 archives (>4 GB or >65535
/// entries) and encrypted entries are not supported, which covers every real
/// `.mrpack`.
enum ZipArchive {

    enum ZipError: LocalizedError {
        case notAZip
        case unsupportedCompression(UInt16)
        case corrupt(String)
        case unsafePath(String)

        var errorDescription: String? {
            switch self {
            case .notAZip:                      return "Not a ZIP archive."
            case .unsupportedCompression(let m):return "Unsupported ZIP compression method \(m)."
            case .corrupt(let what):            return "Corrupt ZIP archive (\(what))."
            case .unsafePath(let p):            return "Refusing to extract unsafe path: \(p)"
            }
        }
    }

    struct Entry {
        let path: String
        let isDirectory: Bool
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    // MARK: - Signatures

    private static let eocdSignature: UInt32    = 0x0605_4b50
    private static let centralSignature: UInt32 = 0x0201_4b50
    private static let localSignature: UInt32   = 0x0403_4b50

    // MARK: - Byte helpers (little-endian)

    private static func u16(_ d: Data, _ offset: Int) -> UInt16 {
        let i = d.startIndex + offset
        return UInt16(d[i]) | (UInt16(d[i + 1]) << 8)
    }

    private static func u32(_ d: Data, _ offset: Int) -> UInt32 {
        let i = d.startIndex + offset
        return UInt32(d[i])
            | (UInt32(d[i + 1]) << 8)
            | (UInt32(d[i + 2]) << 16)
            | (UInt32(d[i + 3]) << 24)
    }

    // MARK: - Reading the directory

    static func entries(at url: URL) throws -> [Entry] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try entries(in: data)
    }

    static func entries(in data: Data) throws -> [Entry] {
        let count = data.count
        guard count > 22 else { throw ZipError.notAZip }

        // Locate the End Of Central Directory record by scanning backwards.
        // It is followed by at most 64 KB of comment.
        let maxComment = 65_535
        let searchFloor = max(0, count - 22 - maxComment)
        var eocd = -1
        var cursor = count - 22
        while cursor >= searchFloor {
            if u32(data, cursor) == eocdSignature { eocd = cursor; break }
            cursor -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }

        let entryCount = Int(u16(data, eocd + 10))
        let centralOffset = Int(u32(data, eocd + 16))
        guard centralOffset < count else { throw ZipError.corrupt("central directory offset") }

        var result: [Entry] = []
        result.reserveCapacity(entryCount)
        var p = centralOffset

        for _ in 0..<entryCount {
            guard p + 46 <= count, u32(data, p) == centralSignature else {
                throw ZipError.corrupt("central directory entry at \(p)")
            }
            let method = u16(data, p + 10)
            let compressedSize = Int(u32(data, p + 20))
            let uncompressedSize = Int(u32(data, p + 24))
            let nameLength = Int(u16(data, p + 28))
            let extraLength = Int(u16(data, p + 30))
            let commentLength = Int(u16(data, p + 32))
            let localOffset = Int(u32(data, p + 42))

            let nameStart = p + 46
            guard nameStart + nameLength <= count else { throw ZipError.corrupt("entry name") }
            let nameRange = (data.startIndex + nameStart)..<(data.startIndex + nameStart + nameLength)
            let name = String(decoding: data[nameRange], as: UTF8.self)

            result.append(Entry(path: name,
                                isDirectory: name.hasSuffix("/"),
                                compressionMethod: method,
                                compressedSize: compressedSize,
                                uncompressedSize: uncompressedSize,
                                localHeaderOffset: localOffset))

            p = nameStart + nameLength + extraLength + commentLength
        }
        return result
    }

    // MARK: - Extracting

    static func extract(_ entry: Entry, from data: Data) throws -> Data {
        let count = data.count
        let header = entry.localHeaderOffset
        guard header + 30 <= count, u32(data, header) == localSignature else {
            throw ZipError.corrupt("local header for \(entry.path)")
        }
        let nameLength = Int(u16(data, header + 26))
        let extraLength = Int(u16(data, header + 28))
        let dataStart = header + 30 + nameLength + extraLength
        guard dataStart + entry.compressedSize <= count else {
            throw ZipError.corrupt("data range for \(entry.path)")
        }

        let range = (data.startIndex + dataStart)..<(data.startIndex + dataStart + entry.compressedSize)
        let payload = data.subdata(in: range)

        switch entry.compressionMethod {
        case 0:
            return payload
        case 8:
            return try inflate(payload, expectedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedCompression(entry.compressionMethod)
        }
    }

    /// Raw DEFLATE. Apple's `COMPRESSION_ZLIB` is documented as raw DEFLATE
    /// (no zlib wrapper), which is exactly what ZIP method 8 stores.
    private static func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        guard !input.isEmpty else { throw ZipError.corrupt("empty deflate stream") }

        var output = Data(count: expectedSize)
        let written: Int = output.withUnsafeMutableBytes { outBuffer in
            input.withUnsafeBytes { inBuffer in
                guard let outBase = outBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let inBase = inBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(outBase, expectedSize,
                                                 inBase, input.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw ZipError.corrupt("inflate produced no output") }
        if written == expectedSize { return output }
        return Data(output.prefix(written))
    }

    // MARK: - Bulk extraction

    /// Extract every entry into `directory`.
    static func extractAll(from url: URL, to directory: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try extractAll(in: data, to: directory)
    }

    static func extractAll(in data: Data, to directory: URL) throws {
        let fm = FileManager.default
        for entry in try entries(in: data) {
            let destination = try safeURL(base: directory, relative: entry.path)
            if entry.isDirectory {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: destination.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try extract(entry, from: data).write(to: destination, options: .atomic)
        }
    }

    /// Extract only entries under `prefix`, optionally stripping that prefix.
    /// Used for a modpack's `overrides/` and `client-overrides/` trees.
    static func extract(from url: URL,
                        entriesMatching prefix: String,
                        strippingPrefix: Bool,
                        to directory: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let fm = FileManager.default

        for entry in try entries(in: data) where entry.path.hasPrefix(prefix) {
            let relative = strippingPrefix
                ? String(entry.path.dropFirst(prefix.count))
                : entry.path
            if relative.isEmpty { continue }
            // `safeURL` validates the path before it touches the filesystem.
            let destination = try safeURL(base: directory, relative: relative)
            if entry.isDirectory {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: destination.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try extract(entry, from: data).write(to: destination, options: .atomic)
        }
    }

    /// Reject absolute paths and `..` traversal so a malicious archive cannot
    /// escape the destination directory.
    private static func safeURL(base: URL, relative: String) throws -> URL {
        let normalized = relative.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/", omittingEmptySubsequences: true)
        guard !normalized.hasPrefix("/"),
              !components.contains(".."),
              !components.contains(where: { $0 == "~" }) else {
            throw ZipError.unsafePath(relative)
        }
        return base.appendingPathComponent(normalized)
    }
}
