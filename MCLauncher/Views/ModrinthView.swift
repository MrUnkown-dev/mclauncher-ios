import SwiftUI

/// Browse and search Modrinth. Content installs into the instance this view was
/// opened with; modpacks create a new instance instead.
struct ModrinthView: View {
    let type: ModrinthProjectType
    /// Target instance for content installs. `nil` in modpack mode.
    let instance: Instance?
    /// Show a Done button when presented as a sheet.
    var showsDoneButton: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ModrinthProject] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var totalHits = 0

    private let service = ModrinthService.shared

    var body: some View {
        List {
            targetBanner

            if let error {
                Section {
                    ContentUnavailableView("Could not reach Modrinth",
                                           systemImage: "wifi.exclamationmark",
                                           description: Text(error))
                }
            } else if isLoading && results.isEmpty {
                Section {
                    HStack { ProgressView(); Text("Searching…").foregroundStyle(.secondary) }
                }
            } else if results.isEmpty {
                Section {
                    ContentUnavailableView("No results",
                                           systemImage: type.systemImage,
                                           description: Text("Try a different search term, or clear the version filter."))
                }
            } else {
                Section {
                    ForEach(results) { project in
                        NavigationLink {
                            ModrinthProjectView(project: project, type: type, instance: instance)
                        } label: {
                            resultRow(project)
                        }
                    }
                } header: {
                    Text("\(totalHits) result\(totalHits == 1 ? "" : "s")")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(type.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .searchable(text: $query, prompt: "Search \(type.displayName.lowercased())")
        // Debounced search: cancels and restarts as the user types.
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await runSearch()
        }
        .refreshable { await runSearch() }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var targetBanner: some View {
        Section {
            if type == .modpack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Installs as a new instance").font(.subheadline.bold())
                        Text("The pack's game and loader versions are read from its manifest.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "plus.square.on.square").foregroundStyle(.green)
                }
            } else if let instance {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Installing into “\(instance.name)”").font(.subheadline.bold())
                        Text("Filtered to Minecraft \(instance.gameVersion)"
                             + (instance.loader.modrinthLoader.map { " · \($0.capitalized)" } ?? "")
                             + " · its own \(type.destinationCategory?.displayName ?? "") folder")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.green)
                }
            } else {
                Label("Open this from an instance to install into it.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
            }
        }
    }

    private func resultRow(_ project: ModrinthProject) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ModrinthIcon(url: project.iconURL)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.title).font(.subheadline.bold()).lineLimit(1)
                Text("by \(project.author)")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(project.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label(project.downloadsText, systemImage: "arrow.down.circle")
                    if let loader = instance?.loader.modrinthLoader,
                       type.usesLoaderFilter,
                       project.categories.contains(loader) {
                        Text(loader.capitalized)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.green.opacity(0.18), in: Capsule())
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func runSearch() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await service.search(
                query: query,
                type: type,
                gameVersion: type == .modpack ? nil : instance?.gameVersion,
                loader: type.usesLoaderFilter ? instance?.loader.modrinthLoader : nil
            )
            results = result.hits
            totalHits = result.total_hits
            error = nil
        } catch {
            self.error = error.localizedDescription
            results = []
        }
    }
}

/// Async project icon with a graceful placeholder.
struct ModrinthIcon: View {
    let url: URL?
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    default:
                        ZStack {
                            Color.gray.opacity(0.15)
                            ProgressView().controlSize(.mini)
                        }
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .stroke(.white.opacity(0.08)))
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.18)
            Image(systemName: "shippingbox.fill").foregroundStyle(.secondary)
        }
    }
}
