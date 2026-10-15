import SwiftUI

/// Browse Mojang's version list and install a version into the launcher.
struct VersionsView: View {
    @EnvironmentObject private var model: LauncherModel
    /// Show a Done button when this view is presented as a sheet.
    var showsDoneButton: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [MinecraftVersion] = []
    @State private var filter: Filter = .release
    @State private var isLoading = true
    @State private var error: String?

    enum Filter: String, CaseIterable, Identifiable {
        case release, snapshot, all
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    private var visible: [MinecraftVersion] {
        switch filter {
        case .release:  return versions.filter { $0.isRelease }
        case .snapshot: return versions.filter { $0.isSnapshot }
        case .all:      return versions
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    ContentUnavailableView("Could not load versions",
                                           systemImage: "wifi.exclamationmark",
                                           description: Text(error))
                } else if isLoading {
                    HStack { ProgressView(); Text("Fetching version manifest…").foregroundStyle(.secondary) }
                } else {
                    ForEach(visible) { version in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(version.id).font(.subheadline.bold())
                                Text(version.typeLabel).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await install(version) }
                            } label: {
                                Image(systemName: "arrow.down.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .navigationTitle("Versions")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if showsDoneButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        do {
            let manifest = try await VersionManifestService().loadManifest()
            versions = manifest.versions
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func install(_ version: MinecraftVersion) async {
        // Install straight into a same-named vanilla instance.
        let instance = model.instances.first { $0.gameVersion == version.id && $0.loader == .vanilla }
            ?? Instance(name: version.id, gameVersion: version.id)
        if !model.instances.contains(where: { $0.id == instance.id }) {
            model.instances.append(instance)
        }
        await model.install(instance, version: version)
    }
}
