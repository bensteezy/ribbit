import Foundation

struct RibbitContextIndex: Codable, Equatable {
    static let currentVersion = 1

    var version = currentVersion
    var targetTerminalID: UUID
    var links: [RibbitContextEntry]
}

struct RibbitContextEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var kind: TabKind
    var contentPath: String
}

enum RibbitContextIndexWriter {
    static func indexURL(
        supportURL: URL,
        projectID: UUID?,
        terminalID: UUID
    ) -> URL {
        supportURL
            .appendingPathComponent("context", isDirectory: true)
            .appendingPathComponent(
                projectID?.uuidString.lowercased() ?? "base",
                isDirectory: true
            )
            .appendingPathComponent(
                terminalID.uuidString.lowercased(),
                isDirectory: false
            )
            .appendingPathExtension("json")
    }

    static func noteSnapshotURL(
        supportURL: URL,
        projectID: UUID?,
        noteID: UUID
    ) -> URL {
        supportURL
            .appendingPathComponent("context", isDirectory: true)
            .appendingPathComponent(
                projectID?.uuidString.lowercased() ?? "base",
                isDirectory: true
            )
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(noteID.uuidString.lowercased())
            .appendingPathExtension("txt")
    }
}
