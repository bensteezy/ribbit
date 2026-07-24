import Foundation

enum RibbitAgentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case cursor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        case .cursor: "cursor"
        }
    }
}

enum RibbitAgentState: String, Codable, CaseIterable, Sendable {
    case running
    case waiting
    case attention
    case paused
    case idle
    case completed

    var label: String {
        switch self {
        case .running: "running"
        case .waiting: "waiting"
        case .attention: "needs you"
        case .paused: "ready"
        case .idle: "idle"
        case .completed: "complete"
        }
    }

    var priority: Int {
        switch self {
        case .attention: 0
        case .waiting: 1
        case .running: 2
        case .paused: 3
        case .idle: 4
        case .completed: 5
        }
    }
}

enum RibbitAttentionKind: String, Codable, CaseIterable, Sendable {
    case permission
    case question
    case plan
    case followUp
}

struct RibbitSessionFocusTarget: Codable, Hashable, Sendable {
    enum Surface: String, Codable, Sendable {
        case ribbit
        case terminal
        case iTerm
        case codex
        case cursor
        case application

        var routesOutsideRibbit: Bool {
            switch self {
            case .iTerm, .codex, .cursor, .application:
                true
            case .ribbit, .terminal:
                false
            }
        }
    }

    var surface: Surface
    var applicationName: String?
    var tty: String?
    var iTermSessionID: String?
    var terminalSessionID: String?
    var workingDirectory: String?
    var processID: Int32?
    var tmuxTarget: String?
    var tmuxSocketPath: String?

    init(
        surface: Surface,
        applicationName: String? = nil,
        tty: String? = nil,
        iTermSessionID: String? = nil,
        terminalSessionID: String? = nil,
        workingDirectory: String? = nil,
        processID: Int32? = nil,
        tmuxTarget: String? = nil,
        tmuxSocketPath: String? = nil
    ) {
        self.surface = surface
        self.applicationName = applicationName
        self.tty = tty
        self.iTermSessionID = iTermSessionID
        self.terminalSessionID = terminalSessionID
        self.workingDirectory = workingDirectory
        self.processID = processID
        self.tmuxTarget = tmuxTarget
        self.tmuxSocketPath = tmuxSocketPath
    }
}

struct RibbitAgentSession: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var providerSessionID: String?
    var agent: RibbitAgentKind
    var title: String
    var project: String
    var activity: String
    var state: RibbitAgentState
    var lastUpdated: Date
    var sourceURL: URL?
    var isBridgeSession: Bool
    var attentionKind: RibbitAttentionKind?
    var attentionDetail: String?
    var focusTarget: RibbitSessionFocusTarget?

    var needsAttention: Bool {
        attentionKind != nil || state == .attention || state == .waiting
    }

    var isLive: Bool {
        state == .running || state == .waiting || state == .attention
    }

    var routableProviderSessionID: String? {
        Self.canonicalProviderSessionID(providerSessionID, agent: agent)
    }

    static func canonicalProviderSessionID(
        _ candidate: String?,
        agent: RibbitAgentKind
    ) -> String? {
        guard var candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidate.isEmpty else { return nil }
        let prefix = "\(agent.rawValue):"
        while candidate.hasPrefix(prefix) {
            candidate.removeFirst(prefix.count)
        }
        return candidate.isEmpty ? nil : candidate
    }
}

struct RibbitAgentBridgeEvent: Codable, Sendable {
    var id: String?
    var providerSessionID: String?
    var agent: RibbitAgentKind
    var title: String
    var project: String?
    var activity: String?
    var state: RibbitAgentState
    var attentionKind: RibbitAttentionKind?
    var attentionDetail: String?
    var focusTarget: RibbitSessionFocusTarget?
}

struct RibbitTerminalIdentity: Equatable, Sendable {
    let id: UUID
    let projectID: UUID?
    let workingDirectory: String
    let projectRoot: String
}

enum RibbitAgentSessionResolver {
    static func terminalID(
        for session: RibbitAgentSession,
        among terminals: [RibbitTerminalIdentity]
    ) -> UUID? {
        if let rawID = session.focusTarget?.terminalSessionID,
           let exactID = UUID(uuidString: rawID),
           terminals.contains(where: { $0.id == exactID }) {
            return exactID
        }

        if let directory = session.focusTarget?.workingDirectory {
            let standardized = URL(fileURLWithPath: directory).standardizedFileURL.path
            let exactDirectoryMatches = terminals.filter {
                URL(fileURLWithPath: $0.workingDirectory).standardizedFileURL.path == standardized
            }
            if exactDirectoryMatches.count == 1 {
                return exactDirectoryMatches[0].id
            }
        }

        let project = session.project.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty else { return nil }
        let projectMatches = terminals.filter {
            URL(fileURLWithPath: $0.projectRoot).lastPathComponent
                .localizedCaseInsensitiveCompare(project) == .orderedSame
        }
        return projectMatches.count == 1 ? projectMatches[0].id : nil
    }
}
