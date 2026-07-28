import Foundation

@MainActor
final class RibbitAgentMonitor: ObservableObject {
    @Published private(set) var sessions: [RibbitAgentSession] = []
    @Published private(set) var sessionsByTerminalID: [UUID: RibbitAgentSession] = [:]
    @Published private(set) var unmatchedSessions: [RibbitAgentSession] = []
    @Published private(set) var canvasActivities: [RibbitCanvasActivity] = []
    @Published private(set) var approvalRequests: [RibbitApprovalRequest] = []
    @Published private(set) var conversationItemsBySessionID:
        [String: [RibbitConversationItem]] = [:]

    private let sources: [RibbitLocalSessionFileSource]
    private let persistedSessionsURL: URL
    private let persistedCanvasActivitiesURL: URL
    private var bridgedSessions: [String: RibbitAgentSession] = [:]
    private var bridgeServer: RibbitAgentBridgeServer?
    private var refreshTimer: Timer?
    private var terminalIdentities: () -> [RibbitTerminalIdentity] = { [] }
    private var onAssignmentsChanged: ([UUID: RibbitAgentSession]) -> Void = { _ in }
    private var onTransition: (RibbitAgentTransition) -> Void = { _ in }
    private var didCompleteInitialRefresh = false

    init(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let supportURL = homeURL
            .appendingPathComponent("Library/Application Support/ribbit", isDirectory: true)
        persistedSessionsURL = supportURL.appendingPathComponent("agent-sessions.json")
        persistedCanvasActivitiesURL = supportURL
            .appendingPathComponent("canvas-activities.json")
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
        if let data = try? Data(contentsOf: persistedCanvasActivitiesURL),
           let restoredActivities = try? JSONDecoder().decode(
               [RibbitCanvasActivity].self,
               from: data
           ) {
            canvasActivities = restoredActivities.filter { $0.kind != .subagent }
        }
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
        approvalRequests = []
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
        applyCanvasActivity(event, now: now)
        let id = event.id ?? "\(event.agent.rawValue):\(event.providerSessionID ?? event.title)"
        applyConversationItem(event, sessionID: id, now: now)
        applyApprovalRequest(event, sessionID: id, now: now)
        if event.state == .completed {
            bridgedSessions.removeValue(forKey: id)
            approvalRequests.removeAll { $0.sessionID == id }
            conversationItemsBySessionID.removeValue(forKey: id)
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

    func resolveApproval(
        _ request: RibbitApprovalRequest,
        decision: RibbitApprovalDecision
    ) {
        guard let index = approvalRequests.firstIndex(where: {
            $0.id == request.id && $0.status != .responding
        }), let bridgeServer else { return }
        approvalRequests[index].status = .responding
        approvalRequests[index].failureMessage = nil
        bridgeServer.respondToApproval(id: request.id, decision: decision) {
            [weak self] delivered in
            Task { @MainActor in
                guard let self,
                      let currentIndex = self.approvalRequests.firstIndex(where: {
                          $0.id == request.id
                      })
                else { return }
                if delivered {
                    self.approvalRequests.remove(at: currentIndex)
                    if var session = self.bridgedSessions[request.sessionID] {
                        session.state = .running
                        session.activity = decision == .allow
                            ? "approved \(request.toolName)"
                            : "denied \(request.toolName)"
                        session.attentionKind = nil
                        session.attentionDetail = nil
                        session.lastUpdated = .now
                        self.bridgedSessions[request.sessionID] = session
                        self.refresh()
                    }
                } else {
                    self.approvalRequests[currentIndex].status = .failed
                    self.approvalRequests[currentIndex].failureMessage =
                        "This request expired. Open Claude to respond."
                }
            }
        }
    }

    private func applyApprovalRequest(
        _ event: RibbitAgentBridgeEvent,
        sessionID: String,
        now: Date
    ) {
        guard let approvalID = event.approvalID,
              event.agent == .claude,
              let toolName = event.approvalToolName,
              let summary = event.approvalSummary
        else { return }
        approvalRequests.removeAll { $0.id == approvalID }
        approvalRequests.append(RibbitApprovalRequest(
            id: approvalID,
            sessionID: sessionID,
            agent: event.agent,
            project: event.project ?? "local",
            toolName: toolName,
            summary: summary,
            receivedAt: now,
            status: .pending,
            failureMessage: nil
        ))
        approvalRequests.sort { $0.receivedAt > $1.receivedAt }
    }

    private func applyConversationItem(
        _ event: RibbitAgentBridgeEvent,
        sessionID: String,
        now: Date
    ) {
        guard let itemID = event.conversationID,
              let role = event.conversationRole,
              let rawText = event.conversationText
        else { return }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var items = conversationItemsBySessionID[sessionID, default: []]
        guard !items.contains(where: { $0.id == itemID }) else { return }
        items.append(RibbitConversationItem(
            id: itemID,
            sessionID: sessionID,
            role: role,
            text: text,
            createdAt: now
        ))
        conversationItemsBySessionID[sessionID] = Array(items.suffix(12))
    }

    private func applyCanvasActivity(
        _ event: RibbitAgentBridgeEvent,
        now: Date
    ) {
        guard let action = event.canvasAction,
              let rawParentID = event.focusTarget?.terminalSessionID,
              let parentTerminalID = UUID(uuidString: rawParentID)
        else { return }

        switch action {
        case .start:
            guard let eventID = event.canvasActivityID,
                  let kind = event.canvasActivityKind
            else { return }
            if let index = canvasActivities.firstIndex(where: {
                $0.eventID == eventID && $0.parentTerminalID == parentTerminalID
            }) {
                canvasActivities[index].kind = kind
                canvasActivities[index].type = event.canvasActivityType
                canvasActivities[index].task = event.canvasTask ?? ""
                canvasActivities[index].schedule = event.canvasSchedule
                canvasActivities[index].state = .working
                canvasActivities[index].finishedAt = nil
            } else {
                canvasActivities.append(RibbitCanvasActivity(
                    id: UUID(),
                    eventID: eventID,
                    parentTerminalID: parentTerminalID,
                    kind: kind,
                    type: event.canvasActivityType,
                    task: event.canvasTask ?? "",
                    schedule: event.canvasSchedule,
                    state: .working,
                    startedAt: now
                ))
            }
        case .finish:
            guard let eventID = event.canvasActivityID,
                  let index = canvasActivities.firstIndex(where: {
                      $0.eventID == eventID && $0.parentTerminalID == parentTerminalID
                  })
            else { return }
            finishCanvasActivity(at: index, event: event, now: now)
        case .finishOne:
            // ponytail: SubagentStop lacks the originating tool-use id. Oldest-first is the
            // smallest deterministic match; replace with provider ids if hooks expose them.
            guard let index = canvasActivities.firstIndex(where: {
                $0.parentTerminalID == parentTerminalID
                    && $0.kind == .subagent
                    && $0.state == .working
            }) else { return }
            finishCanvasActivity(at: index, event: event, now: now)
        case .remove:
            if let eventID = event.canvasActivityID {
                canvasActivities.removeAll {
                    $0.parentTerminalID == parentTerminalID && $0.eventID == eventID
                }
            } else if let kind = event.canvasActivityKind {
                canvasActivities.removeAll {
                    $0.parentTerminalID == parentTerminalID && $0.kind == kind
                }
            }
        }
        persistRecurringCanvasActivities()
    }

    private func finishCanvasActivity(
        at index: Int,
        event: RibbitAgentBridgeEvent,
        now: Date
    ) {
        canvasActivities[index].state = .done
        canvasActivities[index].finishedAt = now
        canvasActivities[index].durationMilliseconds =
            event.canvasDurationMilliseconds
            ?? Int(now.timeIntervalSince(canvasActivities[index].startedAt) * 1_000)
        canvasActivities[index].tokens = event.canvasTokens
        canvasActivities[index].toolUses = event.canvasToolUses
    }

    private func persistRecurringCanvasActivities() {
        do {
            try FileManager.default.createDirectory(
                at: persistedCanvasActivitiesURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try JSONEncoder().encode(
                canvasActivities.filter { $0.kind != .subagent }
            ).write(to: persistedCanvasActivitiesURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: persistedCanvasActivitiesURL.path
            )
        } catch {
            NSLog(
                "ribbit could not persist canvas activities: %@",
                error.localizedDescription
            )
        }
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
