import Foundation

/// File management for one instance: where each kind of content belongs, and
/// the operations the in-app browser performs on it.
///
/// Everything is scoped to the instance's game directory
/// (`Documents/minecraft/instances/<slug>`), which is also visible in the
/// Files app under "On My iPhone → MC Launcher".
enum InstanceFileManager {

    // MARK: - Entries

    /// One item in a directory listing.
    struct Entry: Identifiable, Hashable {
        let url: URL
        let isDirectory: Bool
        let size: Int64
        let modified: Date?

        var id: String { url.path }
        var name: String { url.lastPathComponent }
        var ext: String { url.pathExtension.lowercased() }

        /// A sensible SF Symbol for the file type.
        var iconName: String {
            if isDirectory { return "folder.fill" }
            switch ext {
            case "jar":                       return "shippingbox.fill"
            case "zip", "mcworld", "mcpack":  return "doc.zipper"
            case "json", "toml", "yml", "yaml", "cfg", "properties": return "curlybraces"
            case "png", "jpg", "jpeg":        return "photo"
            case "log", "txt", "md":          return "doc.text"
            default:                          return "doc"
            }
        }

        var sizeText: String { isDirectory ? "—" : InstanceFileManager.formattedSize(size) }
    }

    // MARK: - Categories

    /// The folders Minecraft reads content from.
    enum FileCategory: String, CaseIterable, Identifiable {
        case mods
        case resourcepacks
        case shaderpacks
        case datapacks
        case saves
        case config
        case logs
        case screenshots

        var id: String { rawValue }

        /// Folder name inside the instance directory.
        var relativePath: String { rawValue }

        var displayName: String {
            switch self {
            case .mods:          return "Mods"
            case .resourcepacks: return "Resource Packs"
            case .shaderpacks:   return "Shaders"
            case .datapacks:     return "Datapacks"
            case .saves:         return "Worlds"
            case .config:        return "Config"
            case .logs:          return "Logs"
            case .screenshots:   return "Screenshots"
            }
        }

        var systemImage: String {
            switch self {
            case .mods:          return "shippingbox.fill"
            case .resourcepacks: return "paintpalette.fill"
            case .shaderpacks:   return "sparkles"
            case .datapacks:     return "square.stack.3d.down.right.fill"
            case .saves:         return "globe.europe.africa.fill"
            case .config:        return "slider.horizontal.3"
            case .logs:          return "doc.text.magnifyingglass"
            case .screenshots:   return "photo.on.rectangle"
            }
        }

        /// One-line explanation shown in the UI.
        var hint: String {
            switch self {
            case .mods:
                return "Mod JARs go here. Requires a loader (Fabric / Forge / OptiFine) on this instance."
            case .resourcepacks:
                return "Resource pack .zip files or folders. Enable them in-game under Options → Resource Packs."
            case .shaderpacks:
                return "Shader packs. Requires Iris/OptiFine plus a supported renderer."
            case .datapacks:
                return "Staging area for datapacks. Vanilla loads datapacks from a world's own folder — open Worlds → <world> → datapacks to install one for a specific world."
            case .saves:
                return "Your worlds. Each world is a folder that may contain its own datapacks/ folder."
            case .config:
                return "Mod and game configuration files."
            case .logs:
                return "latest.log and crash reports — the place to look when something breaks."
            case .screenshots:
                return "Screenshots taken in game."
            }
        }

        /// Extensions that make sense in this folder (used for a soft warning,
        /// never to block an import).
        var acceptedExtensions: [String] {
            switch self {
            case .mods:                       return ["jar"]
            case .resourcepacks, .shaderpacks, .datapacks: return ["zip", "jar", ""]
            case .saves:                      return ["", "zip", "mcworld"]
            case .config, .logs, .screenshots: return ["", "txt", "log", "json", "toml", "png", "jpg", "jpeg"]
            }
        }

        func accepts(fileName: String) -> Bool {
            let ext = (fileName as NSString).pathExtension.lowercased()
            return acceptedExtensions.contains(ext)
        }
    }

    // MARK: - Paths

    static func instanceURL(_ instance: Instance) -> URL {
        LauncherPaths.instanceDir(instance.gameDirectory)
    }

    static func categoryURL(_ category: FileCategory, instance: Instance) -> URL {
        instanceURL(instance).appendingPathComponent(category.relativePath, isDirectory: true)
    }

    /// Create the instance directory and every standard content folder.
    @discardableResult
    static func bootstrap(instance: Instance) -> Bool {
        let fm = FileManager.default
        let root = instanceURL(instance)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            for category in FileCategory.allCases {
                try fm.createDirectory(at: categoryURL(category, instance: instance),
                                       withIntermediateDirectories: true)
            }
            return true
        } catch {
            NSLog("[MCL] instance bootstrap failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Listing

    static func entries(in directory: URL) throws -> [Entry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let items = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        return items.compactMap { url -> Entry? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return Entry(url: url,
                         isDirectory: values.isDirectory ?? false,
                         size: Int64(values.fileSize ?? 0),
                         modified: values.contentModificationDate)
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Number of items in a category folder, for the shortcut badges.
    static func itemCount(_ category: FileCategory, instance: Instance) -> Int {
        (try? entries(in: categoryURL(category, instance: instance)).count) ?? 0
    }

    // MARK: - Mutations

    /// Copy files picked from the system Files app into `destination`.
    /// Returns the URLs that were written.
    @discardableResult
    static func importFiles(from sources: [URL], into destination: URL) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        var written: [URL] = []
        for source in sources {
            // Files chosen through the picker are security-scoped.
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }

            let target = uniqueDestination(for: source.lastPathComponent, in: destination)
            try fm.copyItem(at: source, to: target)
            written.append(target)
        }
        return written
    }

    /// Move a file to a different folder (e.g. a .zip imported into Mods that
    /// is really a resource pack).
    @discardableResult
    static func move(_ url: URL, to directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL {
            return url
        }
        let target = uniqueDestination(for: url.lastPathComponent, in: directory)
        try fm.moveItem(at: url, to: target)
        return target
    }

    /// Rename in place, preserving the extension unless the user typed one.
    @discardableResult
    static func rename(_ url: URL, to newName: String) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }

        let ext = url.pathExtension
        var name = trimmed
        if !ext.isEmpty && !name.lowercased().hasSuffix(".\(ext.lowercased())") {
            name += ".\(ext)"
        }
        let target = url.deletingLastPathComponent().appendingPathComponent(name)
        if target.standardizedFileURL != url.standardizedFileURL {
            try FileManager.default.moveItem(at: url, to: target)
        }
        return target
    }

    static func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    @discardableResult
    static func createFolder(named name: String, in directory: URL) throws -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let target = uniqueDestination(for: trimmed, in: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    // MARK: - Helpers

    /// `mod.jar` → `mod (1).jar` when the name is taken.
    static func uniqueDestination(for filename: String, in directory: URL, isDirectory: Bool = false) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(filename, isDirectory: isDirectory)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var index = 1
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            candidate = directory.appendingPathComponent(name, isDirectory: isDirectory)
            index += 1
        }
        return candidate
    }

    static func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }

    /// Total size of a directory, computed lazily by the UI when needed.
    static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            let size = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}
