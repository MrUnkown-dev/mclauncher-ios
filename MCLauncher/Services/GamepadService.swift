import Foundation
import GameController

/// Bridges MFi / Bluetooth controllers into the values the JVM-side gamepad
/// shim expects. The shim reads a small JSON file the launcher writes every
/// frame, so no extra native code is required on the Java side.
final class GamepadService: ObservableObject {

    static let shared = GamepadService()

    @Published private(set) var connectedControllerName: String?

    /// File the Java gamepad shim polls.
    private var stateURL: URL {
        LauncherPaths.root.appendingPathComponent("controller.json")
    }

    private var timer: Timer?

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerChanged),
            name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerChanged),
            name: .GCControllerDidDisconnect, object: nil)
    }

    func start() {
        GCController.startWirelessControllerDiscovery {}
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.writeState()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func controllerChanged() {
        connectedControllerName = GCController.controllers().first?.vendorName
    }

    /// Serialises the current controller state to `controller.json`.
    private func writeState() {
        guard let controller = GCController.controllers().first,
              let gamepad = controller.extendedGamepad else { return }

        let state: [String: Any] = [
            "leftX": gamepad.leftThumbstick.xAxis.value,
            "leftY": gamepad.leftThumbstick.yAxis.value,
            "rightX": gamepad.rightThumbstick.xAxis.value,
            "rightY": gamepad.rightThumbstick.yAxis.value,
            "leftTrigger": gamepad.leftTrigger.value,
            "rightTrigger": gamepad.rightTrigger.value,
            "buttonA": gamepad.buttonA.isPressed,
            "buttonB": gamepad.buttonB.isPressed,
            "buttonX": gamepad.buttonX.isPressed,
            "buttonY": gamepad.buttonY.isPressed,
            "buttonMenu": gamepad.buttonMenu.isPressed,
            "leftShoulder": gamepad.leftShoulder.isPressed,
            "rightShoulder": gamepad.rightShoulder.isPressed
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }
}
