import Foundation

/// A saved copy of a dotfile at a point in time.
struct Snapshot: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var note: String
    /// True for snapshots CLITool takes on its own (before a save or a restore).
    var automatic: Bool
    var bytes: Int
}

/// Snapshots live in ~/Library/Application Support/CLITool/Snapshots/<file key>/
/// as one `<uuid>.txt` per snapshot plus an `index.json`.
enum SnapshotStore {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CLITool/Snapshots", isDirectory: true)
    }

    static func directory(for path: String) -> URL {
        let key = path.replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return root.appendingPathComponent(key, isDirectory: true)
    }

    private static func indexURL(for path: String) -> URL {
        directory(for: path).appendingPathComponent("index.json")
    }

    private static func contentURL(for path: String, id: UUID) -> URL {
        directory(for: path).appendingPathComponent("\(id.uuidString).txt")
    }

    /// Newest first.
    static func list(for path: String) -> [Snapshot] {
        guard let data = try? Data(contentsOf: indexURL(for: path)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let items = (try? decoder.decode([Snapshot].self, from: data)) ?? []
        return items.sorted { $0.date > $1.date }
    }

    private static func writeIndex(_ items: [Snapshot], for path: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(items).write(to: indexURL(for: path), options: .atomic)
    }

    static func content(of snapshot: Snapshot, for path: String) -> String? {
        try? String(contentsOf: contentURL(for: path, id: snapshot.id), encoding: .utf8)
    }

    /// Saves `text` as a new snapshot. Automatic snapshots are skipped when the
    /// newest snapshot already holds identical content; returns nil in that case.
    @discardableResult
    static func add(path: String, text: String, note: String, automatic: Bool) throws -> Snapshot? {
        var items = list(for: path)
        if automatic, let latest = items.first, content(of: latest, for: path) == text {
            return nil
        }
        try FileManager.default.createDirectory(at: directory(for: path), withIntermediateDirectories: true)
        let snapshot = Snapshot(id: UUID(), date: Date(), note: note, automatic: automatic,
                                bytes: text.utf8.count)
        try text.write(to: contentURL(for: path, id: snapshot.id), atomically: true, encoding: .utf8)
        items.insert(snapshot, at: 0)
        try writeIndex(items, for: path)
        return snapshot
    }

    static func delete(_ snapshot: Snapshot, for path: String) throws {
        let items = list(for: path).filter { $0.id != snapshot.id }
        try writeIndex(items, for: path)
        try? FileManager.default.removeItem(at: contentURL(for: path, id: snapshot.id))
    }
}
