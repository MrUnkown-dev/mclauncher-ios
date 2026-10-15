import SwiftUI

/// Instance list + creation. An instance = version + loader + game directory.
struct InstancesView: View {
    @EnvironmentObject private var model: LauncherModel
    @State private var showingNew = false
    @State private var showingVersions = false
    @State private var showingModpacks = false

    var body: some View {
        NavigationStack {
            List {
                if model.instances.isEmpty {
                    ContentUnavailableView("No instances",
                                           systemImage: "square.stack.3d.up.slash",
                                           description: Text("Tap + to create one from an installed version."))
                } else {
                    ForEach(model.instances) { instance in
                        NavigationLink {
                            InstanceDetailView(instance: instance)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: instance.iconName).foregroundStyle(.green)
                                    Text(instance.name).font(.headline)
                                    Spacer()
                                    Text(instance.isInstalled ? "Ready" : "Not installed")
                                        .font(.caption2.bold())
                                        .foregroundStyle(instance.isInstalled ? .green : .orange)
                                }
                                HStack(spacing: 6) {
                                    tag(instance.gameVersion)
                                    tag(instance.loader.displayName)
                                    if let v = instance.loaderVersion { tag(v) }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet { model.deleteInstance(model.instances[index]) }
                    }
                }
            }
            .navigationTitle("Instances")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingVersions = true } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingNew = true } label: {
                            Label("New empty instance", systemImage: "plus")
                        }
                        Button { showingModpacks = true } label: {
                            Label("Install modpack from Modrinth",
                                  systemImage: "shippingbox.and.arrow.backward.fill")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingVersions) {
                VersionsView(showsDoneButton: true)
                    .environmentObject(model)
            }
            .sheet(isPresented: $showingModpacks) {
                NavigationStack {
                    ModrinthView(type: .modpack, instance: nil, showsDoneButton: true)
                }
                .environmentObject(model)
            }
            .sheet(isPresented: $showingNew) {
                NewInstanceView { name, version, loader in
                    model.createInstance(name: name, version: version, loader: loader)
                }
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.gray.opacity(0.18), in: Capsule())
    }
}

/// Sheet for creating a new instance.
struct NewInstanceView: View {
    @Environment(\.dismiss) private var dismiss

    let onCreate: (String, String, ModLoader) -> Void

    @State private var name = ""
    @State private var version = ""
    @State private var loader: ModLoader = .vanilla
    @State private var releases: [MinecraftVersion] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("My Instance", text: $name)
                }
                Section("Minecraft version") {
                    if isLoading {
                        HStack { ProgressView(); Text("Loading versions…").foregroundStyle(.secondary) }
                    } else {
                        Picker("Version", selection: $version) {
                            ForEach(releases) { v in
                                Text(v.id).tag(v.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                Section("Mod loader") {
                    Picker("Loader", selection: $loader) {
                        ForEach(ModLoader.allCases) { l in
                            Label(l.displayName, systemImage: l.iconName).tag(l)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("New Instance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let finalName = name.isEmpty ? "\(version) \(loader.displayName)" : name
                        onCreate(finalName, version, loader)
                        dismiss()
                    }
                    .disabled(version.isEmpty)
                }
            }
            .task {
                do {
                    let manifest = try await VersionManifestService().loadManifest()
                    releases = manifest.versions.filter { $0.isRelease }
                    version = manifest.latest.release
                } catch {
                    releases = []
                }
                isLoading = false
            }
        }
    }
}
