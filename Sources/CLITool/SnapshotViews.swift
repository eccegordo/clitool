import SwiftUI

// MARK: - Snapshot list

struct SnapshotsPanel: View {
    @EnvironmentObject private var store: DotfileStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Snapshots")
                    .font(.headline)
                Spacer()
                Text("\(store.snapshots.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            Divider()

            if store.snapshots.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No snapshots yet")
                        .foregroundStyle(.secondary)
                    Text("Take one before you make changes. CLITool also takes one automatically each time you save.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $store.selectedSnapshotID) {
                    ForEach(store.snapshots) { snapshot in
                        SnapshotRow(snapshot: snapshot)
                            .tag(snapshot.id)
                            .contextMenu {
                                Button("Delete Snapshot", role: .destructive) { store.delete(snapshot) }
                            }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Button { store.takeSnapshot(note: "") } label: {
                    Label("Snapshot Now", systemImage: "camera")
                }
                Spacer()
                Button { store.revealSnapshotsInFinder() } label: {
                    Image(systemName: "folder")
                }
                .help("Show this file's snapshots in Finder")
            }
            .padding(10)
        }
    }
}

private struct SnapshotRow: View {
    let snapshot: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.date.formatted(date: .abbreviated, time: .standard))
                .font(.callout.weight(.medium))
            HStack(spacing: 5) {
                if snapshot.automatic {
                    Text("AUTO")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                }
                Text(snapshot.note.isEmpty ? "Manual snapshot" : snapshot.note)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(ByteCountFormatter.string(fromByteCount: Int64(snapshot.bytes), countStyle: .file))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Snapshot review

/// Shows a snapshot against the current editor contents, with restore/delete actions.
struct SnapshotReviewView: View {
    @EnvironmentObject private var store: DotfileStore
    let snapshot: Snapshot

    private typealias Mode = SnapshotReviewMode

    var body: some View {
        let content = store.snapshotContent(snapshot)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Snapshot from \(snapshot.date.formatted(date: .abbreviated, time: .standard))")
                        .font(.callout.weight(.semibold))
                    if !snapshot.note.isEmpty {
                        Text(snapshot.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Picker("", selection: $store.reviewMode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button("Delete", role: .destructive) { store.delete(snapshot) }
                Button("Restore…") { store.confirmingRestore = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(content == nil)
                Button("Done") { store.selectedSnapshotID = nil }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
            Divider()

            if let content {
                switch store.reviewMode {
                case .changes: changesView(snapshot: content)
                case .contents: linesView(content.components(separatedBy: "\n").map { DiffLine(kind: .same, text: $0) })
                }
            } else {
                Text("This snapshot's contents are missing.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog("Restore \(store.selectedFile?.displayName ?? "this file") to this snapshot?",
                            isPresented: $store.confirmingRestore) {
            Button("Restore") { store.restore(snapshot) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.isSelectionDirty
                 ? "Your unsaved edits will be discarded. The version currently on disk is snapshotted first, so you can undo this."
                 : "The version currently on disk is snapshotted first, so you can undo this.")
        }
    }

    @ViewBuilder
    private func changesView(snapshot content: String) -> some View {
        let lines = DiffLine.diff(from: content, to: store.text)
        if lines.allSatisfy({ $0.kind == .same }) {
            VStack(spacing: 6) {
                Image(systemName: "equal.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("This snapshot is identical to the current file.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Label("only in snapshot (restoring brings these back)", systemImage: "minus")
                        .foregroundStyle(.red)
                    Label("only in current file (restoring removes these)", systemImage: "plus")
                        .foregroundStyle(.green)
                    Spacer()
                }
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                Divider()
                linesView(lines)
            }
        }
    }

    private func linesView(_ lines: [DiffLine]) -> some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 0) {
                        Text(line.kind.marker)
                            .frame(width: 22)
                            .foregroundStyle(line.kind.color)
                        Text(line.text.isEmpty ? " " : line.text)
                            .foregroundStyle(Color(nsColor: store.theme.text))
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(line.kind.color.opacity(line.kind == .same ? 0 : 0.14))
                }
            }
            .padding(.vertical, 8)
            .textSelection(.enabled)
        }
        .background(Color(nsColor: store.theme.background))
    }
}

// MARK: - Line diff

struct DiffLine {
    enum Kind {
        case same, removed, added

        var marker: String {
            switch self {
            case .same: return ""
            case .removed: return "−"
            case .added: return "+"
            }
        }

        var color: Color {
            switch self {
            case .same: return .clear
            case .removed: return .red
            case .added: return .green
            }
        }
    }

    let kind: Kind
    let text: String

    /// Line-by-line diff: `.removed` lines exist only in `old`, `.added` only in `new`.
    static func diff(from old: String, to new: String) -> [DiffLine] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in newLines.difference(from: oldLines) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var result: [DiffLine] = []
        var i = 0, j = 0
        while i < oldLines.count || j < newLines.count {
            if i < oldLines.count, removed.contains(i) {
                result.append(DiffLine(kind: .removed, text: oldLines[i]))
                i += 1
            } else if j < newLines.count, inserted.contains(j) {
                result.append(DiffLine(kind: .added, text: newLines[j]))
                j += 1
            } else if i < oldLines.count {
                result.append(DiffLine(kind: .same, text: oldLines[i]))
                i += 1
                j += 1
            } else {
                break
            }
        }
        return result
    }
}
