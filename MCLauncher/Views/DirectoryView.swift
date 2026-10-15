import SwiftUI
import UniformTypeIdentifiers

/// Observable wrapper around one directory listing.
@MainActor
final class DirectoryModel: ObservableObject {
    @Published var entries: [InstanceFileManager.Entry] = []
    @Published var error: String?
    @Published var isLoading = false

    func load(_ url: URL) {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try InstanceFileManager.entries(in: url)
            error = nil
        } catch {
            entries = []
            self.error = error.localizedDescription
        }
    }
}

/// A full file browser for one directory. Directories push a new `DirectoryView`;
/// files can be renamed, moved, deleted, shared, or added via the system Files
/// picker. This is what lets users install mods, resource packs and datapacks
/// without ever leaving the launcher.
struct DirectoryView: View {
    let url: URL
    let title: String
    /// Present when browsing inside an instance, enabling the "Move to…" menu.
    var instance: Instance?

    @StateObject private var model = DirectoryModel()

    @State private var showImporter = false
    @State private var renameTarget: InstanceFileManager.Entry?
    @State private var renameText = ""
    @State private var deleteTarget: InstanceFileManager.Entry?
    @State private var moveTarget: InstanceFileManager.Entry?
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var notice: String?

    var body: some View {
        List {
            if model.entries.isEmpty && model.error == nil {
                emptyState
            }
            ForEach(model.entries) { entry in
                row(for: entry)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteTarget = entry
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            beginRename(entry)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            moveTarget = entry
                        } label: {
                            Label("Move", systemImage: "arrow.right.doc.on.clipboard")
                        }
                        .tint(.orange)
                    }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) { noticeBar }
        .toolbar { toolbarContent }
        .task { model.load(url) }
        .refreshable { model.load(url) }
        // ---- Import from the system Files app / iCloud ----
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        // ---- Rename ----
        .alert("Rename", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") { commitRename() }
        }
        // ---- New folder ----
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") { commitNewFolder() }
        }
        // ---- Delete ----
        .confirmationDialog(
            "Delete “\(deleteTarget?.name ?? "")”?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This cannot be undone.")
        }
        // ---- Move to a category folder ----
        .confirmationDialog(
            "Move “\(moveTarget?.name ?? "")” to…",
            isPresented: Binding(
                get: { moveTarget != nil },
                set: { if !$0 { moveTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let instance {
                ForEach(InstanceFileManager.FileCategory.allCases) { category in
                    Button(category.displayName) { commitMove(to: category, instance: instance) }
                }
            }
            Button("Cancel", role: .cancel) { moveTarget = nil }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("This folder is empty").font(.subheadline.bold())
            Text("Tap \(Image(systemName: "ellipsis.circle")) → Import to add files from the Files app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func row(for entry: InstanceFileManager.Entry) -> some View {
        if entry.isDirectory {
            NavigationLink {
                DirectoryView(url: entry.url, title: entry.name, instance: instance)
            } label: {
                entryLabel(entry)
            }
        } else {
            entryLabel(entry)
        }
    }

    private func entryLabel(_ entry: InstanceFileManager.Entry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.iconName)
                .frame(width: 26)
                .foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.subheadline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.sizeText)
                    if let modified = entry.modified {
                        Text("·")
                        Text(modified, style: .date)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !entry.isDirectory {
                ShareLink(item: entry.url) {
                    Image(systemName: "square.and.arrow.up").font(.footnote)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showImporter = true
                } label: {
                    Label("Import from Files…", systemImage: "square.and.arrow.down")
                }
                Button {
                    newFolderName = ""
                    showNewFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                Divider()
                Button {
                    model.load(url)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var noticeBar: some View {
        if let notice {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                Text(notice).font(.caption).lineLimit(3)
                Spacer(minLength: 0)
                Button { self.notice = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            do {
                let written = try InstanceFileManager.importFiles(from: urls, into: url)
                model.load(url)
                if let instance,
                   let category = categoryForCurrentFolder(instance: instance),
                   let first = written.first,
                   !category.accepts(fileName: first.lastPathComponent) {
                    notice = "Added \(written.count) file(s). Heads-up: “\(first.lastPathComponent)” may not belong in \(category.displayName) — check the folder."
                } else {
                    notice = "Added \(written.count) file(s)."
                }
            } catch {
                notice = "Import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            notice = "Import cancelled: \(error.localizedDescription)"
        }
    }

    private func beginRename(_ entry: InstanceFileManager.Entry) {
        renameText = entry.name
        renameTarget = entry
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        do {
            try InstanceFileManager.rename(target.url, to: renameText)
            model.load(url)
        } catch {
            notice = "Rename failed: \(error.localizedDescription)"
        }
        renameTarget = nil
    }

    private func commitDelete() {
        guard let target = deleteTarget else { return }
        do {
            try InstanceFileManager.delete(target.url)
            model.load(url)
        } catch {
            notice = "Delete failed: \(error.localizedDescription)"
        }
        deleteTarget = nil
    }

    private func commitNewFolder() {
        do {
            try InstanceFileManager.createFolder(named: newFolderName, in: url)
            model.load(url)
        } catch {
            notice = "Could not create folder: \(error.localizedDescription)"
        }
        newFolderName = ""
        showNewFolder = false
    }

    private func commitMove(to category: InstanceFileManager.FileCategory, instance: Instance) {
        guard let target = moveTarget else { return }
        do {
            try InstanceFileManager.move(target.url,
                                          to: InstanceFileManager.categoryURL(category, instance: instance))
            model.load(url)
            notice = "Moved to \(category.displayName)."
        } catch {
            notice = "Move failed: \(error.localizedDescription)"
        }
        moveTarget = nil
    }

    /// Which category folder (if any) this view is showing.
    private func categoryForCurrentFolder(instance: Instance) -> InstanceFileManager.FileCategory? {
        let standardized = url.standardizedFileURL
        return InstanceFileManager.FileCategory.allCases.first {
            InstanceFileManager.categoryURL($0, instance: instance).standardizedFileURL == standardized
        }
    }
}
