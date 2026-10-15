import SwiftUI

/// Per-instance screen: install, launch, manage content, and inspect the
/// folder. Reached by tapping an instance on the Instances tab.
struct InstanceDetailView: View {
    @EnvironmentObject private var model: LauncherModel
    let instance: Instance

    @State private var isInstalling = false
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    private var current: Instance {
        model.instances.first { $0.id == instance.id } ?? instance
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: current.iconName)
                        .font(.system(size: 44))
                        .foregroundStyle(.green.gradient)
                    Text(current.name).font(.title3.bold())
                    HStack(spacing: 6) {
                        tag(current.gameVersion)
                        tag(current.loader.displayName)
                        tag(current.isInstalled ? "Installed" : "Not installed",
                            tint: current.isInstalled ? .green : .orange)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section("Content") {
                ForEach(InstanceFileManager.FileCategory.allCases) { category in
                    NavigationLink {
                        DirectoryView(
                            url: InstanceFileManager.categoryURL(category, instance: current),
                            title: category.displayName,
                            instance: current
                        )
                    } label: {
                        HStack {
                            Label(category.displayName, systemImage: category.systemImage)
                            Spacer()
                            let count = InstanceFileManager.itemCount(category, instance: current)
                            if count > 0 {
                                Text("\(count)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Manage files")
            } footer: {
                Text("Add mods, resource packs and datapacks here, then enable them in-game. Each instance has its own copies of these folders, so content never leaks between instances.")
            }

            Section {
                ForEach([ModrinthProjectType.mod, .resourcepack, .shader, .datapack]) { type in
                    NavigationLink {
                        ModrinthView(type: type, instance: current)
                    } label: {
                        Label(type.displayName, systemImage: type.systemImage)
                    }
                }
            } header: {
                Text("Browse Modrinth")
            } footer: {
                Text("Filtered to Minecraft \(current.gameVersion)"
                     + (current.loader.modrinthLoader.map { " and \($0.capitalized)" } ?? "")
                     + ". Downloads go into this instance's own folders.")
            }

            Section {
                Button {
                    Task { await install() }
                } label: {
                    HStack {
                        if isInstalling { ProgressView().controlSize(.small) }
                        Label(isInstalling ? "Installing…" : "Install / update version",
                              systemImage: "arrow.down.circle")
                    }
                }
                .disabled(isInstalling || current.loader != .vanilla)

                if current.loader != .vanilla {
                    Label("Loader installation is handled at first launch.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await model.launch(current) }
                } label: {
                    Label("Launch", systemImage: "play.fill")
                }
                .disabled(!JVMBridge.isRuntimeAvailable)
            }

            Section {
                NavigationLink {
                    DirectoryView(url: InstanceFileManager.instanceURL(current),
                                  title: current.name,
                                  instance: current)
                } label: {
                    Label("Open instance folder", systemImage: "folder")
                }
                HStack {
                    Text("Location").foregroundStyle(.secondary)
                    Spacer()
                    Text("minecraft/instances/\(current.gameDirectory)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete instance", systemImage: "trash")
                }
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { InstanceFileManager.bootstrap(instance: current) }
        .confirmationDialog("Delete “\(current.name)”?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.deleteInstance(current)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The instance is removed from the launcher. Its files stay in the minecraft/instances folder unless you delete them separately.")
        }
    }

    private func install() async {
        isInstalling = true
        defer { isInstalling = false }
        await model.installGameFiles(for: current)
    }

    private func tag(_ text: String, tint: Color = .secondary) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint == .secondary ? .primary : tint)
    }
}
