import Foundation

/// Thin Swift wrapper around the native JVM entry point declared in
/// `Native/jvm_bridge.m`. The launcher stays buildable and runnable *without*
/// the JRE linked in — `isRuntimeAvailable` simply returns false and the UI
/// shows a clear "runtime not installed" message instead of crashing.
enum JVMBridge {

    /// True when the OpenJDK-for-iOS runtime is linked into the app.
    static var isRuntimeAvailable: Bool {
        MCL_hasJVM() != 0
    }

    /// Path of the bundled runtime, if present.
    static var runtimePath: String? {
        guard let c = MCL_runtimePath() else { return nil }
        return String(cString: c)
    }

    /// Launch the JVM. Blocks until Minecraft exits, so call it off the main
    /// thread. Returns the JVM exit code, or a negative value on setup failure.
    @discardableResult
    static func launch(arguments: [String], environment: [String: String] = [:]) -> Int32 {
        // Apply environment overrides (e.g. LIBGL_ES, MESA_* for the renderer).
        for (key, value) in environment {
            setenv(key, value, 1)
        }

        // argv must be a NULL-terminated C array.
        var cArgs: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        cArgs.append(nil)
        defer { for ptr in cArgs where ptr != nil { free(ptr) } }

        return cArgs.withUnsafeMutableBufferPointer { buf in
            MCL_launchJVM(Int32(arguments.count), buf.baseAddress)
        }
    }
}
