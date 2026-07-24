import Foundation

enum RibbitAgentStateStore {
    static func loadOrMigrate(
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [RibbitAgentSession] {
        let currentURL = homeURL
            .appendingPathComponent("Library/Application Support/ribbit", isDirectory: true)
            .appendingPathComponent("agent-sessions.json")
        if let sessions = decodeCurrent(at: currentURL) { return sessions }

        let legacyURL = homeURL
            .appendingPathComponent("Library/Application Support/Noot", isDirectory: true)
            .appendingPathComponent("sessions.json")
        guard let sessions = decodeLegacy(at: legacyURL), !sessions.isEmpty else { return [] }
        persist(sessions, to: currentURL, fileManager: fileManager)
        return sessions
    }

    static func persist(
        _ sessions: [RibbitAgentSession],
        to url: URL,
        fileManager: FileManager = .default
    ) {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try JSONEncoder().encode(sessions).write(to: url, options: .atomic)
            try? fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            NSLog("ribbit could not persist agent state: %@", error.localizedDescription)
        }
    }

    private static func decodeCurrent(at url: URL) -> [RibbitAgentSession]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([RibbitAgentSession].self, from: data)
    }

    private static func decodeLegacy(at url: URL) -> [RibbitAgentSession]? {
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([LegacySession].self, from: data)
        else { return nil }
        return records.compactMap(\.ribbitSession)
    }
}

private struct LegacySession: Decodable {
    let id: String
    let providerSessionID: String?
    let agent: String
    let title: String
    let project: String
    let activity: String
    let state: String
    let lastUpdated: Date
    let sourceURL: URL?
    let isBridgeSession: Bool
    let attentionKind: String?
    let attentionDetail: String?
    let focusTarget: LegacyFocusTarget?

    var ribbitSession: RibbitAgentSession? {
        guard let agent = RibbitAgentKind(rawValue: agent),
              let state = RibbitAgentState(rawValue: state)
        else { return nil }
        return RibbitAgentSession(
            id: id,
            providerSessionID: RibbitAgentSession.canonicalProviderSessionID(
                providerSessionID,
                agent: agent
            ),
            agent: agent,
            title: title,
            project: project,
            activity: activity,
            state: state,
            lastUpdated: lastUpdated,
            sourceURL: sourceURL,
            isBridgeSession: isBridgeSession,
            attentionKind: attentionKind.flatMap(RibbitAttentionKind.init(rawValue:)),
            attentionDetail: attentionDetail,
            focusTarget: focusTarget?.ribbitTarget
        )
    }
}

private struct LegacyFocusTarget: Decodable {
    let surface: String
    let applicationName: String?
    let tty: String?
    let iTermSessionID: String?
    let terminalSessionID: String?
    let workingDirectory: String?

    var ribbitTarget: RibbitSessionFocusTarget? {
        let mappedSurface: RibbitSessionFocusTarget.Surface
        switch surface {
        case "terminal": mappedSurface = .terminal
        case "iTerm": mappedSurface = .iTerm
        case "codex": mappedSurface = .codex
        case "cursor": mappedSurface = .cursor
        case "application": mappedSurface = .application
        default: return nil
        }
        return RibbitSessionFocusTarget(
            surface: mappedSurface,
            applicationName: applicationName,
            tty: tty,
            iTermSessionID: iTermSessionID,
            terminalSessionID: terminalSessionID,
            workingDirectory: workingDirectory
        )
    }
}
