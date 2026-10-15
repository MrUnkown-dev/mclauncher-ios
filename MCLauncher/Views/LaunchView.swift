import SwiftUI

/// The "Play" screen: pick an instance, see the selected account, and launch.
struct LaunchView: View {
    @EnvironmentObject private var model: LauncherModel
    @State private var selectedInstanceID: UUID?
    @State private var showConsole = false

    private var selected: Instance? {
        model.instances.first { $0.id == selectedInstanceID } ?? model.instances.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    runtimeWarning
                    heroCard
                    instancePicker
                    launchButton
                    if !model.consoleLines.isEmpty { consolePreview }
                }
                .padding(16)
            }
            .background(background)
            .navigationTitle("MC Launcher")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showConsole = true } label: {
                        Image(systemName: "terminal.fill")
                    }
                }
            }
            .sheet(isPresented: $showConsole) {
                ConsoleView(lines: model.consoleLines)
            }
            .onAppear {
                if selectedInstanceID == nil { selectedInstanceID = model.instances.first?.id }
            }
        }
    }

    private var background: some View {
        LinearGradient(colors: [Color(red: 0.05, green: 0.12, blue: 0.08),
                                Color(red: 0.02, green: 0.03, blue: 0.04)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var runtimeWarning: some View {
        if !JVMBridge.isRuntimeAvailable {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Java runtime not bundled").font(.subheadline.bold())
                    Text("The launcher shell works, but it cannot start Minecraft until the JRE is added. See BUILD.md → Adding the JRE.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.yellow.opacity(0.35)))
        }
    }

    private var heroCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "cube.transparent.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green.gradient)
            Text(selected?.name ?? "No instance")
                .font(.title2.bold())
            if let selected {
                HStack(spacing: 8) {
                    badge(selected.gameVersion)
                    badge(selected.loader.displayName)
                    if !selected.isInstalled { badge("not installed", tint: .orange) }
                }
            }
            if let account = model.accounts.selectedAccount {
                Label(account.username, systemImage: account.type == .microsoft ? "checkmark.seal.fill" : "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No account selected").font(.footnote).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func badge(_ text: String, tint: Color = .secondary) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint == .secondary ? .primary : tint)
    }

    @ViewBuilder
    private var instancePicker: some View {
        if model.instances.isEmpty {
            Card(title: "Instances", systemImage: "square.stack.3d.up") {
                Text("No instances yet — create one on the Instances tab.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            Card(title: "Choose instance", systemImage: "square.stack.3d.up") {
                ForEach(model.instances) { instance in
                    Button {
                        selectedInstanceID = instance.id
                    } label: {
                        HStack {
                            Image(systemName: instance.iconName)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(instance.name).font(.subheadline.bold())
                                Text("\(instance.gameVersion) · \(instance.loader.displayName)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if instance.id == selected?.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if instance.id != model.instances.last?.id { Divider() }
                }
            }
        }
    }

    private var launchButton: some View {
        VStack(spacing: 10) {
            Button {
                guard let selected else { return }
                Task { await model.launch(selected) }
            } label: {
                HStack {
                    if model.isLaunching { ProgressView().tint(.black) }
                    Text(model.isLaunching ? "Running…" : "Launch")
                        .font(.headline.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(model.isLaunching || selected == nil || !JVMBridge.isRuntimeAvailable)

            if !model.installStatus.isEmpty && model.installProgress > 0 && model.installProgress < 1 {
                ProgressView(value: model.installProgress) {
                    Text(model.installStatus).font(.caption)
                }
            }
        }
    }

    private var consolePreview: some View {
        Card(title: "Console", systemImage: "terminal") {
            Text(model.consoleLines.suffix(6).joined(separator: "\n"))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.green.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(6)
        }
    }
}
