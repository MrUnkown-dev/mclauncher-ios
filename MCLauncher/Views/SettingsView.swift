import SwiftUI
import UIKit

/// Performance, graphics, controller and advanced settings.
struct SettingsView: View {
    @EnvironmentObject private var model: LauncherModel
    @EnvironmentObject private var settingsStore: SettingsStore

    private var binding: Binding<LauncherSettings> { $settingsStore.settings }

    var body: some View {
        NavigationStack {
            Form {
                Section("Performance") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Allocated RAM")
                            Spacer()
                            Text("\(settingsStore.settings.allocatedRAMmb) MB").foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(settingsStore.settings.allocatedRAMmb) },
                            set: { settingsStore.settings.allocatedRAMmb = Int($0) }
                        ), in: 512...4096, step: 128)
                    }
                    Toggle("Prefer JIT (faster)", isOn: binding.preferJIT)
                    Stepper("Max FPS: \(settingsStore.settings.maxFPS == 0 ? "Unlimited" : "\(settingsStore.settings.maxFPS)")",
                            value: binding.maxFPS, in: 0...240, step: 10)
                }

                Section("Graphics") {
                    Picker("Renderer", selection: binding.renderer) {
                        ForEach(Renderer.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Auto-pick renderer per version", isOn: binding.autoRenderer)
                    Toggle("Metal layer", isOn: binding.useMetalLayer)
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Resolution scale")
                            Spacer()
                            Text(String(format: "%.2f×", settingsStore.settings.resolutionScale))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: binding.resolutionScale, in: 0.5...1.0, step: 0.05)
                    }
                }

                Section("Controls") {
                    Toggle("Game controller support", isOn: binding.controllerEnabled)
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Cursor sensitivity")
                            Spacer()
                            Text(String(format: "%.2f×", settingsStore.settings.cursorSensitivity))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: binding.cursorSensitivity, in: 0.25...3.0, step: 0.05)
                    }
                }

                Section("Advanced") {
                    Toggle("Show console while playing", isOn: binding.showConsole)
                    Toggle("Prevent sleep during play", isOn: binding.preventSleep)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Extra JVM flags").font(.subheadline)
                        TextField("-XX:+UseSerialGC", text: binding.extraJVMArgs, axis: .vertical)
                            .font(.system(.caption, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section("Runtime") {
                    LabeledContent("Java runtime") {
                        Text(JVMBridge.isRuntimeAvailable ? "Installed" : "Missing")
                            .foregroundStyle(JVMBridge.isRuntimeAvailable ? .green : .orange)
                    }
                    LabeledContent("Renderer in use") {
                        Text(settingsStore.settings.renderer.displayName)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    LabeledContent("Data folder") {
                        Text(LauncherPaths.displayPath)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        if let url = URL(string: "shareddocuments://") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Open in Files app", systemImage: "folder")
                    }
                } header: {
                    Text("Files")
                } footer: {
                    Text("Game files, mods, resource packs, worlds and logs live here. They are visible in the Files app under “On My iPhone → MC Launcher” and are included in device backups.")
                }

                Section {
                    Button(role: .destructive) {
                        settingsStore.settings = .default
                    } label: {
                        Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
