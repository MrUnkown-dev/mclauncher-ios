import SwiftUI

/// The "Files" tab: pick an instance, then jump straight into the folders that
/// matter (mods, resource packs, shaders, datapacks, worlds) or browse the
/// whole instance directory.
struct FilesView: View {
    @EnvironmentObject private var model: LauncherModel
    @State private var selectedInstanceID: UUID?
    @State private var refreshToken = UUID()

    private var instance: Instance? {
        model.instances.first { $0.id == selectedInstanceID } ?? model.instances.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.instances.isEmpty {
                    ContentUnavailableView(
                        "No instances",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text("Create an instance on the Instances tab, then come back to add mods and resource packs.")
                    )
                } else if let instance {
                    content(for: instance)
                }
            }
            .navigationTitle("Files")
        }
        .onAppear {
            if selectedInstanceID == nil { selectedInstanceID = model.instances.first?.id }
        }
    }

    @ViewBuilder
    private func content(for instance: Instance) -> some View {
        List {
            if model.instances.count > 1 {
                Section("Instance") {
                    Picker("Instance", selection: Binding(
                        get: { selectedInstanceID ?? instance.id },
                        set: { selectedInstanceID = $0; refreshToken = UUID() }
                    )) {
                        ForEach(model.instances) { item in
                            Text(item.name).tag(item.id)
                        }
                    }
                }
            }

            Section {
                ForEach(InstanceFileManager.FileCategory.allCases) { category in
                    NavigationLink {
                        DirectoryView(
                            url: InstanceFileManager.categoryURL(category, instance: instance),
                            title: category.displayName,
                            instance: instance
                        )
                    } label: {
                        categoryRow(category, instance: instance)
                    }
                }
            } header: {
                Text("Add content")
            } footer: {
                Text("Tap a folder, then ⋯ → Import from Files… to add a mod, resource pack or datapack. Everything is stored under “On My iPhone → MC Launcher”.")
            }

            Section {
                NavigationLink {
                    ModrinthView(type: .mod, instance: instance)
                } label: {
                    Label("Mods on Modrinth", systemImage: "shippingbox.fill")
                }
                NavigationLink {
                    ModrinthView(type: .resourcepack, instance: instance)
                } label: {
                    Label("Resource packs on Modrinth", systemImage: "paintpalette.fill")
                }
                NavigationLink {
                    ModrinthView(type: .shader, instance: instance)
                } label: {
                    Label("Shaders on Modrinth", systemImage: "sparkles")
                }
                NavigationLink {
                    ModrinthView(type: .datapack, instance: instance)
                } label: {
                    Label("Datapacks on Modrinth", systemImage: "square.stack.3d.down.right.fill")
                }
            } header: {
                Text("Discover")
            } footer: {
                Text("Results are filtered to Minecraft \(instance.gameVersion)"
                     + (instance.loader.modrinthLoader.map { " and \($0.capitalized)" } ?? "")
                     + ", and install into this instance's own folders.")
            }

            Section("Instance folder") {
                NavigationLink {
                    DirectoryView(url: InstanceFileManager.instanceURL(instance),
                                  title: instance.name,
                                  instance: instance)
                } label: {
                    Label("Browse all files", systemImage: "folder")
                }
                NavigationLink {
                    DirectoryView(url: LauncherPaths.root, title: "Launcher data", instance: nil)
                } label: {
                    Label("Launcher data root", systemImage: "externaldrive")
                }
            }
        }
        .id(refreshToken)
        .task { InstanceFileManager.bootstrap(instance: instance) }
    }

    private func categoryRow(_ category: InstanceFileManager.FileCategory,
                             instance: Instance) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .frame(width: 26)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.displayName).font(.subheadline)
                Text(category.hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            let count = InstanceFileManager.itemCount(category, instance: instance)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.gray.opacity(0.2), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}
