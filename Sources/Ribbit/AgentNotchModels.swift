import Combine
import Foundation

struct RibbitAgentDismissalRecord: Codable, Equatable, Sendable {
    let sessionID: String
    let dismissedAt: Date
    let dismissedState: RibbitAgentState
    let attentionKind: RibbitAttentionKind?
    let attentionDetail: String?
    let activity: String
    var isArmedForNextLivePhase: Bool

    init(session: RibbitAgentSession, dismissedAt: Date = .now) {
        sessionID = session.id
        self.dismissedAt = dismissedAt
        dismissedState = session.state
        attentionKind = session.attentionKind
        attentionDetail = session.attentionDetail
        activity = session.activity
        isArmedForNextLivePhase = !session.isLive
    }
}

enum RibbitAgentDismissalPolicy {
    static func reconciled(
        _ records: [String: RibbitAgentDismissalRecord],
        with sessions: [RibbitAgentSession]
    ) -> [String: RibbitAgentDismissalRecord] {
        let sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        var result = records

        for (sessionID, var record) in records {
            guard let session = sessionsByID[sessionID] else {
                record.isArmedForNextLivePhase = true
                result[sessionID] = record
                continue
            }

            guard session.lastUpdated > record.dismissedAt else {
                if !session.isLive {
                    record.isArmedForNextLivePhase = true
                    result[sessionID] = record
                }
                continue
            }

            if !session.isLive {
                record.isArmedForNextLivePhase = true
                result[sessionID] = record
                continue
            }

            let isNewAttention = session.needsAttention && (
                session.state != record.dismissedState
                    || session.attentionKind != record.attentionKind
                    || session.attentionDetail != record.attentionDetail
                    || session.activity != record.activity
            )
            let resumedAfterAttention = session.isLive
                && record.dismissedState != .running

            if record.isArmedForNextLivePhase || isNewAttention || resumedAfterAttention {
                result.removeValue(forKey: sessionID)
            }
        }

        return result
    }
}

enum RibbitAgentNotchLife: Equatable, Sendable {
    case quiet
    case running
    case ready
    case attention
}

struct RibbitAgentNotchProjection: Equatable, Sendable {
    let visibleSessions: [RibbitAgentSession]
    let displayedSessions: [RibbitAgentSession]
    let attentionCount: Int
    let runningCount: Int
    let readyCount: Int
    let primaryAttention: RibbitAgentSession?

    init(
        sessions: [RibbitAgentSession],
        hiddenSessionIDs: Set<String> = [],
        maximumDisplayedSessions: Int = 5
    ) {
        let visible = sessions
            .filter {
                !hiddenSessionIDs.contains($0.id)
                    && $0.state != .idle
                    && $0.state != .completed
            }
            .sorted {
                if $0.state.priority != $1.state.priority {
                    return $0.state.priority < $1.state.priority
                }
                return $0.lastUpdated > $1.lastUpdated
            }
        visibleSessions = visible
        attentionCount = visible.filter(\.needsAttention).count
        runningCount = visible.filter { $0.state == .running }.count
        readyCount = visible.filter { $0.state == .paused }.count
        primaryAttention = visible.first(where: \.needsAttention)
        if let primaryAttention {
            displayedSessions = [primaryAttention]
        } else {
            displayedSessions = Array(visible.prefix(max(0, maximumDisplayedSessions)))
        }
    }

    var life: RibbitAgentNotchLife {
        if attentionCount > 0 { return .attention }
        if runningCount > 0 { return .running }
        if readyCount > 0 { return .ready }
        return .quiet
    }
}

enum RibbitNotchPresentationMode: Equatable, Sendable {
    case compact
    case expandedEphemeral
    case expandedPinned
}

struct RibbitNotchPresentationState: Equatable, Sendable {
    private(set) var mode: RibbitNotchPresentationMode = .compact

    var isExpanded: Bool { mode != .compact }
    var isPinned: Bool { mode == .expandedPinned }

    mutating func expandEphemerally() {
        guard mode != .expandedPinned else { return }
        mode = .expandedEphemeral
    }

    mutating func expandAndPin() {
        mode = .expandedPinned
    }

    mutating func collapse() {
        mode = .compact
    }
}

struct RibbitAgentNotchViewMetrics: Equatable, Sendable {
    var hasPhysicalNotch = false
    var hardwareNotchWidth: CGFloat = 0
    var headerHeight: CGFloat = RibbitAgentNotchGeometry.fallbackCompactSize.height
}

@MainActor
final class RibbitAgentNotchState: ObservableObject {
    @Published private(set) var projection: RibbitAgentNotchProjection
    @Published private(set) var presentation = RibbitNotchPresentationState()
    @Published private(set) var hiddenSessionIDs: Set<String> = []
    @Published private(set) var viewMetrics = RibbitAgentNotchViewMetrics()

    let settings: AppSettings

    private let monitor: RibbitAgentMonitor
    private let persistedDismissalsURL: URL
    private let focusSession: (RibbitAgentSession) -> Void
    private var sessionDismissals: [String: RibbitAgentDismissalRecord] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var hoverExpandTask: Task<Void, Never>?
    private var hoverCollapseTask: Task<Void, Never>?
    private var attentionCollapseTask: Task<Void, Never>?
    private var isIslandHovering = false
    private var previousSessions: [RibbitAgentSession]

    init(
        monitor: RibbitAgentMonitor,
        settings: AppSettings,
        persistedDismissalsURL: URL? = nil,
        focusSession: @escaping (RibbitAgentSession) -> Void
    ) {
        self.monitor = monitor
        self.settings = settings
        self.focusSession = focusSession
        self.persistedDismissalsURL = persistedDismissalsURL
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            .appendingPathComponent("ribbit", isDirectory: true)
            .appendingPathComponent("notch-dismissals.json")
        previousSessions = monitor.sessions
        projection = RibbitAgentNotchProjection(sessions: monitor.sessions)
        loadDismissals()
        refresh(with: monitor.sessions, revealsAttention: false)

        monitor.$sessions
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions in
                self?.refresh(with: sessions, revealsAttention: true)
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var isExpanded: Bool { presentation.isExpanded }
    var isPinned: Bool { presentation.isPinned }

    func updateViewMetrics(_ metrics: RibbitAgentNotchViewMetrics) {
        if metrics != viewMetrics {
            viewMetrics = metrics
        }
    }

    func expandAndPin() {
        cancelHoverTasks()
        setPresentation { $0.expandAndPin() }
    }

    func collapse() {
        cancelHoverTasks()
        attentionCollapseTask?.cancel()
        setPresentation { $0.collapse() }
    }

    func setIslandHovering(_ hovering: Bool) {
        hoverExpandTask?.cancel()
        hoverCollapseTask?.cancel()
        isIslandHovering = hovering

        if hovering {
            guard settings.notchExpandOnHover, !isExpanded else { return }
            let delay = settings.notchHoverDelay
            hoverExpandTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, self.isIslandHovering else { return }
                self.setPresentation { $0.expandEphemerally() }
            }
            return
        }

        guard settings.notchAutoCollapse, !isPinned else { return }
        hoverCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, !self.isIslandHovering else { return }
            self.setPresentation { $0.collapse() }
        }
    }

    func hide(_ session: RibbitAgentSession) {
        var updated = sessionDismissals
        updated[session.id] = RibbitAgentDismissalRecord(session: session)
        updateDismissals(updated)
        refresh(with: monitor.sessions, revealsAttention: false)
    }

    func focus(_ session: RibbitAgentSession) {
        focusSession(session)
        collapse()
    }

    func stop() {
        cancellables.removeAll()
        cancelHoverTasks()
        attentionCollapseTask?.cancel()
    }

    private func refresh(
        with sessions: [RibbitAgentSession],
        revealsAttention: Bool
    ) {
        let reconciled = RibbitAgentDismissalPolicy.reconciled(
            sessionDismissals,
            with: sessions
        )
        updateDismissals(reconciled)
        let nextProjection = RibbitAgentNotchProjection(
            sessions: sessions,
            hiddenSessionIDs: hiddenSessionIDs
        )
        if nextProjection != projection {
            projection = nextProjection
        }

        let transition = RibbitAgentTransition.detect(
            previous: previousSessions,
            current: sessions
        )
        previousSessions = sessions
        guard revealsAttention, !transition.needsAttention.isEmpty else { return }
        revealAttention()
    }

    private func revealAttention() {
        setPresentation { $0.expandEphemerally() }
        attentionCollapseTask?.cancel()
        guard settings.notchAttentionRevealDwell > 0 else { return }
        attentionCollapseTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.settings.notchAttentionRevealDwell))
            guard !Task.isCancelled,
                  !self.isIslandHovering,
                  !self.isPinned else { return }
            self.setPresentation { $0.collapse() }
        }
    }

    private func setPresentation(
        _ update: (inout RibbitNotchPresentationState) -> Void
    ) {
        var next = presentation
        update(&next)
        if next != presentation {
            presentation = next
        }
    }

    private func cancelHoverTasks() {
        hoverExpandTask?.cancel()
        hoverCollapseTask?.cancel()
    }

    private func loadDismissals() {
        guard let data = try? Data(contentsOf: persistedDismissalsURL),
              let records = try? JSONDecoder().decode(
                  [RibbitAgentDismissalRecord].self,
                  from: data
              )
        else { return }
        sessionDismissals = Dictionary(
            uniqueKeysWithValues: records.map { ($0.sessionID, $0) }
        )
        hiddenSessionIDs = Set(sessionDismissals.keys)
    }

    private func updateDismissals(
        _ updated: [String: RibbitAgentDismissalRecord]
    ) {
        guard updated != sessionDismissals else { return }
        sessionDismissals = updated
        hiddenSessionIDs = Set(updated.keys)
        let records = updated.values.sorted { $0.sessionID < $1.sessionID }
        guard let data = try? JSONEncoder().encode(records) else { return }
        let directory = persistedDismissalsURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try? data.write(to: persistedDismissalsURL, options: .atomic)
    }
}
