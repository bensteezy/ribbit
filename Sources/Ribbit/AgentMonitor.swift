import Foundation

@MainActor
final class RibbitAgentMonitor: ObservableObject {
    @Published private(set) var sessions: [RibbitAgentSession] = []
    @Published private(set) var sessionsByTerminalID: [UUID: RibbitAgentSession] = [:]
    @Published private(set) var unmatchedSessions: [RibbitAgentSession] = []

    private let sources: [RibbitLocalSessionFileSource]
    private let persistedSessionsURL: URL
    private var bridgedSessions: [String: RibbitAgentSession] = [:]
    private var bridgeServer: RibbitAgentBridgeServer?
    private var refreshTimer: Timer?
    private var terminalIdentities: () -> [RibbitTerminalIdentity] = { [] }
    private var onAssignmentsChanged: ([UUID: RibbitAgentSession]) -> Void = { _ in }
    private var onTransition: (RibbitAgentTransition) -> Void = { _ in }
    private var didCompleteInitialRefresh = false

    init(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        persistedSessionsURL = homeURL
            .appendingPathComponent("Library/Application Support/ribbit", isDirectory: true)
            .appendingPathComponent("agent-sessions.json")
        sources = [
            RibbitLocalSessionFileSource(
                agent: .codex,
                root: homeURL.appendingPathComponent(".codex/sessions", isDirectory: true)
            ),
            RibbitLocalSessionFileSource(
                agent: .claude,
                root: homeURL.appendingPathComponent(".claude/projects", isDirectory: true)
            ),
            RibbitLocalSessionFileSource(
                agent: .cursor,
                root: homeURL.appendingPathComponent(".cursor", isDirectory: true)
            )
        ]
        let restored = RibbitAgentStateStore.loadOrMigrate(homeURL: homeURL)
        bridgedSessions = Dictionary(uniqueKeysWithValues: restored.map { ($0.id, $0) })
    }

    func start(
        terminalIdentities: @escaping () -> [RibbitTerminalIdentity],
        onAssignmentsChanged: @escaping ([UUID: RibbitAgentSession]) -> Void,
        onTransition: @escaping (RibbitAgentTransition) -> Void = { _ in },
        startsBridge: Bool = true,
        schedulesRefresh: Bool = true
    ) {
        guard refreshTimer == nil, bridgeServer == nil else { return }
        self.terminalIdentities = terminalIdentities
        self.onAssignmentsChanged = onAssignmentsChanged
        self.onTransition = onTransition
        if startsBridge {
            bridgeServer = RibbitAgentBridgeServer { [weak self] event in
                Task { @MainActor in
                    self?.apply(event)
                }
            }
            bridgeServer?.start()
        }
        refresh()
        if schedulesRefresh {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) {
                [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        bridgeServer?.stop()
        bridgeServer = nil
    }

    func refresh(now: Date = .now) {
        let previousSessions = sessions
        let identities = terminalIdentities()
        let terminalIDs = Set(identities.map(\.id))
        let activeCutoff = now.addingTimeInterval(-900)
        let attentionCutoff = now.addingTimeInterval(-86_400)
        let pausedCutoff = now.addingTimeInterval(-7_200)
        let local = sources.flatMap { $0.scan(now: now) }.filter { session in
            switch session.state {
            case .running:
                session.lastUpdated >= activeCutoff
            case .attention, .waiting:
                session.lastUpdated >= attentionCutoff
            case .paused:
                session.lastUpdated >= pausedCutoff
            case .idle, .completed:
                false
            }
        }

        let liveBridgeCutoff = now.addingTimeInterval(-600)
        let pausedBridgeCutoff = now.addingTimeInterval(-7_200)
        let retainedBridgeCutoff = now.addingTimeInterval(-86_400)
        let previousBridgedSessions = bridgedSessions
        bridgedSessions = bridgedSessions.filter { _, session in
            if session.focusTarget?.surface == .ribbit,
               let rawID = session.focusTarget?.terminalSessionID,
               let terminalID = UUID(uuidString: rawID),
               !terminalIDs.contains(terminalID) {
                return false
            }
            if session.agent == .claude,
               let processID = session.focusTarget?.processID,
               !Self.processIsRunning(processID) {
                return false
            }
            if session.needsAttention {
                return session.lastUpdated >= retainedBridgeCutoff
            }
            if session.state == .paused {
                return session.lastUpdated >= pausedBridgeCutoff
            }
            return session.lastUpdated >= liveBridgeCutoff
        }
        if bridgedSessions != previousBridgedSessions {
            persistBridgedSessions()
        }

        var latestLocalByID: [String: RibbitAgentSession] = [:]
        for session in local {
            if let current = latestLocalByID[session.id],
               current.lastUpdated > session.lastUpdated {
                continue
            }
            latestLocalByID[session.id] = session
        }

        var merged: [String: RibbitAgentSession] = [:]
        for session in latestLocalByID.values {
            if let current = merged[session.id],
               current.lastUpdated > session.lastUpdated { continue }
            merged[session.id] = session
        }
        for bridgeSession in bridgedSessions.values {
            if let localSession = merged[bridgeSession.id] {
                var resolved = bridgeSession
                resolved.sourceURL = localSession.sourceURL
                resolved.focusTarget = Self.resolvedFocusTarget(
                    bridge: bridgeSession.focusTarget,
                    local: localSession.focusTarget
                )
                merged[bridgeSession.id] = resolved
            } else {
                merged[bridgeSession.id] = bridgeSession
            }
        }
        sessions = merged.values.sorted {
            if $0.state.priority != $1.state.priority {
                return $0.state.priority < $1.state.priority
            }
            return $0.lastUpdated > $1.lastUpdated
        }
        if didCompleteInitialRefresh {
            let transition = RibbitAgentTransition.detect(
                previous: previousSessions,
                current: sessions
            )
            if !transition.isEmpty { onTransition(transition) }
        }
        didCompleteInitialRefresh = true
        assignSessions()
    }

    nonisolated static func processIsRunning(_ processID: Int32) -> Bool {
        guard processID > 0 else { return false }
        return kill(processID, 0) == 0 || errno == EPERM
    }

    nonisolated static func resolvedFocusTarget(
        bridge: RibbitSessionFocusTarget?,
        local: RibbitSessionFocusTarget?
    ) -> RibbitSessionFocusTarget? {
        guard let bridge else { return local }
        guard let local else { return bridge }

        // Exact host identities from hooks always win. A generic application
        // fallback does not: old Ribbit hooks classified Codex Desktop as
        // Terminal, while the transcript still contains its routable task ID.
        switch bridge.surface {
        case .ribbit, .terminal, .iTerm, .codex, .cursor:
            return bridge
        case .application:
            return local.surface == .codex ? local : bridge
        }
    }

    func apply(_ event: RibbitAgentBridgeEvent, now: Date = .now) {
        let id = event.id ?? "\(event.agent.rawValue):\(event.providerSessionID ?? event.title)"
        if event.state == .completed {
            bridgedSessions.removeValue(forKey: id)
            persistBridgedSessions()
            refresh(now: now)
            return
        }
        bridgedSessions[id] = RibbitAgentSession(
            id: id,
            providerSessionID: RibbitAgentSession.canonicalProviderSessionID(
                event.providerSessionID ?? event.id,
                agent: event.agent
            ),
            agent: event.agent,
            title: event.title,
            project: event.project ?? "local",
            activity: event.activity ?? "agent activity",
            state: event.state,
            lastUpdated: now,
            sourceURL: nil,
            isBridgeSession: true,
            attentionKind: event.attentionKind,
            attentionDetail: event.attentionDetail,
            focusTarget: event.focusTarget
        )
        persistBridgedSessions()
        refresh(now: now)
    }

    private func persistBridgedSessions() {
        RibbitAgentStateStore.persist(
            Array(bridgedSessions.values),
            to: persistedSessionsURL
        )
    }

    private func assignSessions() {
        let identities = terminalIdentities()
        var assignments: [UUID: RibbitAgentSession] = [:]
        var unmatched: [RibbitAgentSession] = []
        for session in sessions {
            guard let terminalID = RibbitAgentSessionResolver.terminalID(
                for: session,
                among: identities
            ) else {
                unmatched.append(session)
                continue
            }
            if let current = assignments[terminalID],
               current.state.priority < session.state.priority {
                continue
            }
            assignments[terminalID] = session
        }
        sessionsByTerminalID = assignments
        unmatchedSessions = unmatched
        onAssignmentsChanged(assignments)
    }
}
