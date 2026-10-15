import Foundation

/// Canonical on-device layout. Everything the launcher writes lives under the
/// app's Documents directory so it survives reinstalls (on iOS the Documents
/// folder is backed up and can be reached through the Files app if enabled).
enum LauncherPaths {

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Root of the whole launcher data tree.
    ///
    /// Named `minecraft` (NOT `.minecraft`) on purpose: the iOS Files app hides
    /// dot-prefixed folders, and we want everything to show up under
    /// "On My iPhone → MC Launcher" so game files, mods and worlds are visible,
    /// manageable, and included in device backups.
    static var root: URL { documents.appendingPathComponent("minecraft", isDirectory: true) }

    /// Older builds used a hidden `.minecraft` folder; migrated on first launch.
    static var legacyRoot: URL { documents.appendingPathComponent(".minecraft", isDirectory: true) }

    static var versions: URL { root.appendingPathComponent("versions", isDirectory: true) }
    static var libraries: URL { root.appendingPathComponent("libraries", isDirectory: true) }
    static var assets: URL { root.appendingPathComponent("assets", isDirectory: true) }
    static var assetIndexes: URL { assets.appendingPathComponent("indexes", isDirectory: true) }
    static var assetObjects: URL { assets.appendingPathComponent("objects", isDirectory: true) }
    static var instances: URL { root.appendingPathComponent("instances", isDirectory: true) }
    static var runtime: URL { root.appendingPathComponent("runtime", isDirectory: true) }

    /// The JVM + graphics runtime that ships inside the app bundle (read-only).
    static var bundledRuntime: URL {
        Bundle.main.bundleURL.appendingPathComponent("Frameworks", isDirectory: true)
    }

    static func versionDir(_ id: String) -> URL {
        versions.appendingPathComponent(id, isDirectory: true)
    }

    static func instanceDir(_ slug: String) -> URL {
        instances.appendingPathComponent(slug, isDirectory: true)
    }

    /// Create every directory the launcher expects. Safe to call repeatedly.
    static func bootstrap() throws {
        migrateLegacyRootIfNeeded()
        for dir in [root, versions, libraries, assets, assetIndexes, assetObjects, instances, runtime] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Move a pre-existing hidden `.minecraft` folder to the visible `minecraft`
    /// location so existing installs keep their data.
    private static func migrateLegacyRootIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyRoot.path),
              !fm.fileExists(atPath: root.path) else { return }
        do {
            try fm.moveItem(at: legacyRoot, to: root)
            NSLog("[MCL] migrated .minecraft -> minecraft (Files-app visible)")
        } catch {
            NSLog("[MCL] legacy migration failed: \(error.localizedDescription)")
        }
    }

    /// A human-readable path for the UI, e.g. "On My iPhone/MC Launcher/minecraft".
    static var displayPath: String { "On My iPhone/MC Launcher/minecraft" }
}
