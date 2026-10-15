import Foundation

/// Graphics backend used to translate Minecraft's OpenGL calls onto the GPU.
enum Renderer: String, Codable, CaseIterable, Identifiable {
    /// GL4ES — OpenGL 2.1 → OpenGL ES. Best compatibility for 1.7–1.16.
    case gl4es
    /// ANGLE — OpenGL ES → Metal. Required for 1.17+ and better on modern GPUs.
    case angle
    /// Zink / Vulkan → Metal path. Experimental.
    case zink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gl4es: return "GL4ES (compatibility)"
        case .angle: return "ANGLE (Metal, 1.17+)"
        case .zink:  return "Zink (experimental)"
        }
    }
}

/// Everything the user can tune. Persisted as JSON in UserDefaults.
struct LauncherSettings: Codable, Equatable {
    /// Heap ceiling handed to the JVM in megabytes.
    var allocatedRAMmb: Int = 1024
    var renderer: Renderer = .angle
    /// Force the GLES/EGL surface through the Metal layer (smoother, required on some GPUs).
    var useMetalLayer: Bool = true
    /// Render resolution scale, 0.5–1.0. Lower = faster on old devices.
    var resolutionScale: Double = 1.0
    /// Cap FPS. 0 = unlimited.
    var maxFPS: Int = 60
    /// Enable the JVM's JIT when the environment allows it (paid cert / JIT-enabled).
    var preferJIT: Bool = true
    /// Extra raw JVM flags, space separated. Appended last, so they win.
    var extraJVMArgs: String = ""
    /// Show the live log console while playing.
    var showConsole: Bool = false
    /// Keep the device awake during play.
    var preventSleep: Bool = true
    /// Enable GameController support (MFi / Bluetooth pads → LWJGL gamepad).
    var controllerEnabled: Bool = true
    /// Cursor sensitivity multiplier for touch-as-mouse.
    var cursorSensitivity: Double = 1.0
    /// Automatically pick the renderer based on the selected game version.
    var autoRenderer: Bool = true

    static let `default` = LauncherSettings()
}

/// Small helper so settings survive relaunches.
final class SettingsStore: ObservableObject {
    private static let key = "mcl.settings.v1"

    @Published var settings: LauncherSettings {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(LauncherSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    /// The renderer that should actually be used for a given game version.
    /// 1.17 dropped fixed-function OpenGL, so GL4ES can no longer cope.
    func effectiveRenderer(forGameVersion version: String) -> Renderer {
        guard settings.autoRenderer else { return settings.renderer }
        return Self.suggestedRenderer(for: version)
    }

    static func suggestedRenderer(for version: String) -> Renderer {
        guard let minor = minorVersion(of: version) else { return .angle }
        return minor >= 17 ? .angle : .gl4es
    }

    /// "1.20.4" -> 20 ; "1.7.10" -> 7 ; snapshots -> nil.
    private static func minorVersion(of version: String) -> Int? {
        let parts = version.split(separator: ".")
        guard parts.count >= 2, parts[0] == "1", let minor = Int(parts[1]) else { return nil }
        return minor
    }
}
