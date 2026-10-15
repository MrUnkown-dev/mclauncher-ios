import SwiftUI

/// Project detail: description, metadata, and the version list filtered to what
/// the target instance can run. Tapping a version installs it.
struct ModrinthProjectView: View {
    @EnvironmentObject private var model: LauncherModel
    @Environment(\.dismiss) private var dismiss

    let project: ModrinthProject
    let type: ModrinthProjectType
    let instance: Instance?

    @State private var versions: [ModrinthVersion] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var installingVersionID: String?
    @State private var status = ""
    @State private var progress: Double = 0

    private let service = ModrinthService.shared

    var body: some View {
        List {
            header

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                if isLoading {
                    HStack { ProgressView(); Text("Loading versions…").foregroundStyle(.secondary) }
                } else if versions.isEmpty {
                    ContentUnavailableView(
                        "No compatible versions",
                        systemImage: "questionmark.circle",
                        description: Text(compatibilityMessage)
                    )
                } else {
                    ForEach(versions) { version in
                        versionRow(version)
                    }
                }
            } header: {
                Text("Versions")
            } footer: {
                Text(type == .modpack
                     ? "Installing creates a new instance with this pack's game and loader versions."
                     : "Downloads land in “\(instance?.name ?? "—")”’s own \(type.destinationCategory?.displayName ?? "") folder.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { progressBar }
        .task { await loadVersions() }
    }

    // MARK: - Header

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ModrinthIcon(url: project.iconURL, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.title).font(.headline)
                        Text("by \(project.author)")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Label(project.downloadsText, systemImage: "arrow.down.circle")
                            Label("\(project.follows)", systemImage: "heart")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                Text(project.description).font(.subheadline)

                if !project.categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(project.categories.prefix(8), id: \.self) { category in
                                Text(category)
                                    .font(.caption2)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.gray.opacity(0.18), in: Capsule())
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    metaPill("License", project.license)
                    metaPill("Client", project.client_side)
                    metaPill("Server", project.server_side)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func metaPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value.capitalized).font(.caption2.bold())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Version row

    private func versionRow(_ version: ModrinthVersion) -> some View {
        Button {
            Task { await install(version) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(version.version_number).font(.subheadline.bold())
                        Text(version.typeLabel)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(typeColor(version.version_type).opacity(0.2), in: Capsule())
                            .foregroundStyle(typeColor(version.version_type))
                    }
                    if !version.loaders.isEmpty {
                        Text(version.loaders.joined(separator: ", "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(version.game_versions.prefix(6).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if installingVersionID == version.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(installingVersionID != nil)
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "release": return .green
        case "beta":    return .orange
        default:        return .red
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressBar: some View {
        if installingVersionID != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text(status.isEmpty ? "Installing…" : status).font(.caption)
                ProgressView(value: progress)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(16)
        }
    }

    private var compatibilityMessage: String {
        guard let instance else {
            return "No versions are available for this project."
        }
        let loader = instance.loader.modrinthLoader.map { " / \($0)" } ?? ""
        return "Nothing published for Minecraft \(instance.gameVersion)\(loader). Try another version of the game or switch the instance's loader."
    }

    // MARK: - Actions

    private func loadVersions() async {
        isLoading = true
        defer { isLoading = false }
        do {
            versions = try await service.versions(
                projectID: project.project_id,
                gameVersion: type == .modpack ? nil : instance?.gameVersion,
                loader: type.usesLoaderFilter ? instance?.loader.modrinthLoader : nil
            )
            error = nil
        } catch {
            self.error = error.localizedDescription
            versions = []
        }
    }

    private func install(_ version: ModrinthVersion) async {
        installingVersionID = version.id
        status = "Starting…"
        progress = 0
        defer { installingVersionID = nil }

        do {
            if type == .modpack {
                let result = try await service.installModpack(version: version, name: project.title) { message, fraction in
                    Task { @MainActor in
                        status = message
                        progress = fraction
                    }
                }
                model.addInstalledInstance(result.instance)
                model.banner = "Installed “\(result.instance.name)” — \(result.downloadedFiles) files downloaded"
                    + (result.skippedFiles > 0 ? ", \(result.skippedFiles) skipped." : ".")
                // Pull the base game files for the pack's Minecraft version.
                Task { await model.installGameFiles(for: result.instance) }
                dismiss()
            } else if let instance, let category = type.destinationCategory {
                let url = try await service.install(version: version, into: instance, as: category) { fraction in
                    Task { @MainActor in
                        status = "Downloading…"
                        progress = fraction
                    }
                }
                model.banner = "Installed \(url.lastPathComponent) into \(instance.name) → \(category.displayName)."
                dismiss()
            } else {
                model.banner = "Open Modrinth from an instance to install \(type.singularName)s."
            }
        } catch {
            model.banner = "Install failed: \(error.localizedDescription)"
        }
    }
}
