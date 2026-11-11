import AppKit
import Foundation

struct Dotfile: Identifiable, Hashable {
    let path: String
    let isCustom: Bool

    var id: String { path }
    /// e.g. "~/.zshrc"
    var displayName: String { (path as NSString).abbreviatingWithTildeInPath }
    /// e.g. ".zshrc" or ".ssh/config"
    var shortName: String {
        let name = displayName
        return name.hasPrefix("~/") ? String(name.dropFirst(2)) : name
    }

    /// The shell that can syntax-check this file, if it is a shell startup file.
    var syntaxShell: String? {
        let name = (path as NSString).lastPathComponent
        if name.contains("zsh") || name.hasPrefix(".zprofile") || name.hasPrefix(".zlog") { return "/bin/zsh" }
        if name.contains("bash") || name == ".profile" { return "/bin/bash" }
        return nil
    }
}

enum SnapshotReviewMode: String, CaseIterable {
    case changes = "Changes"
    case contents = "Snapshot"
}

struct StatusMessage: Equatable {
    var text: String
    var isError = false
}

@MainActor
final class DotfileStore: ObservableObject {
    static let shared = DotfileStore()

    /// Files under ~ that are listed automatically when they exist.
    private static let candidates = [
        ".zshrc", ".zprofile", ".zshenv", ".zlogin", ".zlogout",
        ".bashrc", ".bash_profile", ".profile", ".aliases", ".inputrc",
        ".gitconfig", ".gitignore_global", ".vimrc", ".tmux.conf", ".npmrc",
        ".ssh/config", ".config/starship.toml",
    ]
    private static let customFilesKey = "customFiles"

    @Published private(set) var files: [Dotfile] = []
    @Published var selectedPath: String? {
        didSet { if selectedPath != oldValue { selectionChanged() } }
    }
    /// File contents as last read from or written to disk.
    @Published private var diskText: [String: String] = [:]
    /// Unsaved edits, keyed by path.
    @Published private var drafts: [String: String] = [:]
    /// Files that changed on disk while they had unsaved edits.
    @Published private(set) var conflicts: Set<String> = []
    @Published private(set) var snapshots: [Snapshot] = []
    @Published var selectedSnapshotID: UUID?
    @Published var status: StatusMessage?
    @Published var confirmingReload = false

    // View state. Kept here rather than in @State, whose macro plugin ships only with
    // full Xcode — this project builds with just the Command Line Tools.
    @Published var showingSnapshotPopover = false
    @Published var snapshotNote = ""
    @Published var reviewMode: SnapshotReviewMode = .changes
    @Published var confirmingRestore = false

    private init() {
        reloadFileList()
        selectedPath = files.first?.path
        selectionChanged()
    }

    // MARK: File list

    private var customPaths: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.customFilesKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.customFilesKey) }
    }

    func reloadFileList() {
        let home = NSHomeDirectory()
        var list: [Dotfile] = []
        for name in Self.candidates {
            let path = (home as NSString).appendingPathComponent(name)
            if name == ".zshrc" || FileManager.default.fileExists(atPath: path) {
                list.append(Dotfile(path: path, isCustom: false))
            }
        }
        for path in customPaths where !list.contains(where: { $0.path == path }) {
            list.append(Dotfile(path: path, isCustom: true))
        }
        if list != files { files = list }
    }

    func addFileFromPanel() {
        let panel = NSOpenPanel()
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.message = "Choose config files to manage in CLITool"
        guard panel.runModal() == .OK else { return }
        var paths = customPaths
        for url in panel.urls where !files.contains(where: { $0.path == url.path }) {
            paths.append(url.path)
        }
        customPaths = paths
        reloadFileList()
        if let first = panel.urls.first { selectedPath = first.path }
    }

    func removeCustomFile(_ file: Dotfile) {
        customPaths = customPaths.filter { $0 != file.path }
        drafts[file.path] = nil
        if selectedPath == file.path { selectedPath = files.first { $0.path != file.path }?.path }
        reloadFileList()
    }

    var selectedFile: Dotfile? { files.first { $0.path == selectedPath } }

    // MARK: Text

    private func read(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private func write(_ text: String, to path: String) throws {
        // Write through symlinks (dotfiles are often linked into a repo) and keep permissions.
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let permissions = try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
        try text.write(to: url, atomically: true, encoding: .utf8)
        if let permissions {
            try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }

    private func selectionChanged() {
        selectedSnapshotID = nil
        guard let path = selectedPath else { snapshots = []; return }
        if diskText[path] == nil { diskText[path] = read(path) }
        snapshots = SnapshotStore.list(for: path)
    }

    /// The editor contents for the selected file.
    var text: String {
        get {
            guard let path = selectedPath else { return "" }
            return drafts[path] ?? diskText[path] ?? ""
        }
        set {
            guard let path = selectedPath else { return }
            drafts[path] = newValue == diskText[path] ? nil : newValue
        }
    }

    func isDirty(_ path: String) -> Bool { drafts[path] != nil }
    var isSelectionDirty: Bool { selectedPath.map(isDirty) ?? false }
    var hasUnsavedChanges: Bool { !drafts.isEmpty }

    func fileExists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    // MARK: Save / reload

    func save() {
        guard let path = selectedPath else { return }
        save(path)
    }

    private func save(_ path: String) {
        guard let draft = drafts[path] else { return }
        let name = (path as NSString).abbreviatingWithTildeInPath
        do {
            if fileExists(path) {
                try SnapshotStore.add(path: path, text: read(path), note: "Before save", automatic: true)
            }
            try write(draft, to: path)
            diskText[path] = draft
            drafts[path] = nil
            conflicts.remove(path)
            if path == selectedPath { snapshots = SnapshotStore.list(for: path) }
            status = StatusMessage(text: "Saved \(name). New terminal windows will pick it up.")
        } catch {
            status = StatusMessage(text: "Could not save \(name): \(error.localizedDescription)", isError: true)
        }
    }

    func saveAll() {
        for path in Array(drafts.keys) { save(path) }
    }

    /// Reloads the selected file from disk, asking first if that would drop unsaved edits.
    func requestReload() {
        if isSelectionDirty { confirmingReload = true } else { reloadFromDisk() }
    }

    func reloadFromDisk() {
        guard let path = selectedPath else { return }
        diskText[path] = read(path)
        drafts[path] = nil
        conflicts.remove(path)
        status = StatusMessage(text: "Reloaded \((path as NSString).abbreviatingWithTildeInPath) from disk.")
    }

    /// Keeps unsaved edits after the file changed on disk; saving will overwrite the disk version.
    func keepEditsOverDisk() {
        guard let path = selectedPath else { return }
        let onDisk = read(path)
        diskText[path] = onDisk
        if drafts[path] == onDisk { drafts[path] = nil }
        conflicts.remove(path)
    }

    /// Picks up changes made outside the app (called when the app becomes active).
    func syncWithDisk() {
        for (path, known) in diskText {
            let onDisk = read(path)
            guard onDisk != known else { continue }
            if drafts[path] == nil {
                diskText[path] = onDisk
            } else {
                conflicts.insert(path)
            }
        }
        reloadFileList()
    }

    // MARK: Snapshots

    /// Snapshots the selected file as it is on disk.
    func takeSnapshot(note: String) {
        guard let path = selectedPath else { return }
        let name = (path as NSString).abbreviatingWithTildeInPath
        guard fileExists(path) else {
            status = StatusMessage(text: "\(name) does not exist on disk yet — save it first.", isError: true)
            return
        }
        do {
            try SnapshotStore.add(path: path, text: read(path),
                                  note: note.trimmingCharacters(in: .whitespacesAndNewlines), automatic: false)
            snapshots = SnapshotStore.list(for: path)
            status = StatusMessage(text: "Snapshot of \(name) saved.")
        } catch {
            status = StatusMessage(text: "Snapshot failed: \(error.localizedDescription)", isError: true)
        }
    }

    func snapshotAll() {
        var count = 0
        for file in files where fileExists(file.path) {
            if (try? SnapshotStore.add(path: file.path, text: read(file.path),
                                       note: "Snapshot of all files", automatic: false)) != nil {
                count += 1
            }
        }
        if let path = selectedPath { snapshots = SnapshotStore.list(for: path) }
        status = StatusMessage(text: "Saved snapshots of \(count) file\(count == 1 ? "" : "s").")
    }

    func snapshotContent(_ snapshot: Snapshot) -> String? {
        guard let path = selectedPath else { return nil }
        return SnapshotStore.content(of: snapshot, for: path)
    }

    /// Writes the snapshot back to disk. The current disk version is snapshotted first,
    /// so a restore can itself be undone.
    func restore(_ snapshot: Snapshot) {
        guard let path = selectedPath else { return }
        let name = (path as NSString).abbreviatingWithTildeInPath
        guard let content = SnapshotStore.content(of: snapshot, for: path) else {
            status = StatusMessage(text: "That snapshot's contents are missing.", isError: true)
            return
        }
        do {
            if fileExists(path) {
                try SnapshotStore.add(path: path, text: read(path), note: "Before restore", automatic: true)
            }
            try write(content, to: path)
            diskText[path] = content
            drafts[path] = nil
            conflicts.remove(path)
            selectedSnapshotID = nil
            snapshots = SnapshotStore.list(for: path)
            status = StatusMessage(text: "Restored \(name) to the snapshot from \(snapshot.date.formatted(date: .abbreviated, time: .shortened)).")
        } catch {
            status = StatusMessage(text: "Restore failed: \(error.localizedDescription)", isError: true)
        }
    }

    func delete(_ snapshot: Snapshot) {
        guard let path = selectedPath else { return }
        try? SnapshotStore.delete(snapshot, for: path)
        if selectedSnapshotID == snapshot.id { selectedSnapshotID = nil }
        snapshots = SnapshotStore.list(for: path)
    }

    func revealSnapshotsInFinder() {
        guard let path = selectedPath else { return }
        let directory = SnapshotStore.directory(for: path)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    // MARK: Shell helpers

    /// Runs `zsh -n` / `bash -n` over the editor contents (including unsaved edits).
    func checkSyntax() {
        guard let file = selectedFile, let shell = file.syntaxShell else { return }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("clitool-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            try text.write(to: temp, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-n", temp.path]
            let pipe = Pipe()
            process.standardError = pipe
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = (String(data: data, encoding: .utf8) ?? "")
                .replacingOccurrences(of: temp.path, with: file.shortName)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let shellName = (shell as NSString).lastPathComponent
            if process.terminationStatus == 0 {
                status = StatusMessage(text: "Syntax OK (\(shellName) -n).")
            } else {
                status = StatusMessage(text: output.isEmpty ? "Syntax check failed." : output, isError: true)
            }
        } catch {
            status = StatusMessage(text: "Could not run syntax check: \(error.localizedDescription)", isError: true)
        }
    }

    /// Opens a new terminal window, which starts a fresh shell with the saved config.
    func openNewTerminal() {
        let iTerm = URL(fileURLWithPath: "/Applications/iTerm.app")
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let app = FileManager.default.fileExists(atPath: iTerm.path) ? iTerm : terminal
        NSWorkspace.shared.open([URL(fileURLWithPath: NSHomeDirectory())], withApplicationAt: app,
                                configuration: NSWorkspace.OpenConfiguration())
    }
}
