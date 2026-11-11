import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: DotfileStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
        } detail: {
            if let file = store.selectedFile {
                HStack(spacing: 0) {
                    EditorPane(file: file)
                    Divider()
                    SnapshotsPanel()
                        .frame(width: 270)
                }
            } else {
                Text("Select a file")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar { toolbarContent }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.syncWithDisk()
        }
        .confirmationDialog("Discard unsaved edits and reload from disk?",
                            isPresented: $store.confirmingReload) {
            Button("Discard Edits and Reload", role: .destructive) { store.reloadFromDisk() }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { store.save() } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(!store.isSelectionDirty)
            .help("Save changes to disk (⌘S). The previous version is snapshotted automatically.")

            Button { store.requestReload() } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(store.selectedPath == nil)
            .help("Reload the file from disk (⌘R)")

            Button { store.checkSyntax() } label: {
                Label("Check Syntax", systemImage: "checkmark.seal")
            }
            .disabled(store.selectedFile?.syntaxShell == nil)
            .help("Check the editor contents for shell syntax errors (⌘K)")

            Button { store.showingSnapshotPopover = true } label: {
                Label("Snapshot", systemImage: "camera")
            }
            .disabled(store.selectedPath == nil)
            .help("Save a snapshot of this file as it is on disk (⌘B)")
            .popover(isPresented: $store.showingSnapshotPopover, arrowEdge: .bottom) { snapshotPopover }

            Button { store.theme = store.theme.toggled } label: {
                Label(store.theme == .dark ? "Light Theme" : "Dark Theme",
                      systemImage: store.theme == .dark ? "sun.max" : "moon")
            }
            .help("Switch between the light and dark theme (⇧⌘L)")

            Button { store.openNewTerminal() } label: {
                Label("New Terminal", systemImage: "terminal")
            }
            .help("Open a new terminal window, which loads the saved config (⌘T)")
        }
    }

    private var snapshotPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Snapshot \(store.selectedFile?.displayName ?? "")")
                .font(.headline)
            TextField("Note (optional)", text: $store.snapshotNote)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit(commitSnapshot)
            if store.isSelectionDirty {
                Text("Snapshots capture the saved file, not unsaved edits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { store.showingSnapshotPopover = false }
                Button("Save Snapshot", action: commitSnapshot)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
    }

    private func commitSnapshot() {
        store.takeSnapshot(note: store.snapshotNote)
        store.snapshotNote = ""
        store.showingSnapshotPopover = false
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var store: DotfileStore

    var body: some View {
        List(selection: $store.selectedPath) {
            Section("Dotfiles") {
                ForEach(store.files) { file in
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        Text(file.shortName)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        if store.isDirty(file.path) {
                            Circle()
                                .fill(.orange)
                                .frame(width: 7, height: 7)
                                .help("Unsaved changes")
                        }
                    }
                    .tag(file.path)
                    .contextMenu {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
                        }
                        if file.isCustom {
                            Button("Remove from List") { store.removeCustomFile(file) }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { store.addFileFromPanel() } label: {
                    Label("Add File…", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(10)
        }
    }
}

// MARK: - Editor pane

struct EditorPane: View {
    @EnvironmentObject private var store: DotfileStore
    let file: Dotfile

    private var selectedSnapshot: Snapshot? {
        store.snapshots.first { $0.id == store.selectedSnapshotID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.conflicts.contains(file.path) { conflictBanner }
            if let snapshot = selectedSnapshot {
                SnapshotReviewView(snapshot: snapshot)
            } else {
                CodeEditor(text: $store.text, theme: store.theme, isShell: file.syntaxShell != nil)
                    .id(file.path)
            }
            Divider()
            statusBar
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(file.displayName)
                .font(.system(.headline, design: .monospaced))
            if store.isDirty(file.path) {
                Text("Unsaved changes")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.2), in: Capsule())
            }
            Spacer()
            if let date = store.modificationDate(file.path) {
                Text("Modified \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not on disk yet — saving will create it")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var conflictBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("This file changed on disk while you were editing it.")
            Spacer()
            Button("Keep My Edits") { store.keepEditsOverDisk() }
            Button("Reload from Disk") { store.reloadFromDisk() }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.yellow.opacity(0.15))
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if let status = store.status {
                Image(systemName: status.isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    .foregroundStyle(status.isError ? .red : .green)
                Text(status.text)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            Text("\(store.text.split(separator: "\n", omittingEmptySubsequences: false).count) lines")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}
