import AppKit
import SwiftUI

struct TerminalCanvasWorkspace: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject private var agentMonitor: RibbitAgentMonitor
    let viewportSize: CGSize

    @State private var pan = CGSize.zero
    @State private var zoom: CGFloat = 1
    @State private var transientFrames: [UUID: CanvasNodeFrame] = [:]
    @State private var linkingSourceID: UUID?
    @State private var linkingTargetID: UUID?
    @State private var linkingPointer: CGPoint?
    @State private var cameraPersistenceTask: Task<Void, Never>?

    init(
        model: AppModel,
        settings: AppSettings,
        viewportSize: CGSize
    ) {
        self.model = model
        self.settings = settings
        self.viewportSize = viewportSize
        _agentMonitor = ObservedObject(wrappedValue: model.agentMonitor)
        _pan = State(initialValue: CGSize(
            width: model.canvasCamera.x,
            height: model.canvasCamera.y
        ))
        _zoom = State(initialValue: model.canvasCamera.zoom)
    }

    var body: some View {
        GeometryReader { _ in
            let displayedFrames = displayedFrames
            ZStack(alignment: .topLeading) {
                CanvasGrid(pan: pan, zoom: zoom)
                    .allowsHitTesting(false)

                ZStack(alignment: .topLeading) {
                    ContextEdgesLayer(
                        model: model,
                        frames: displayedFrames,
                        pan: pan,
                        zoom: zoom
                    )
                    if let linkingSourceID,
                       let linkingPointer,
                       let source = displayedFrames[linkingSourceID] {
                        CanvasLinkPreview(
                            source: CanvasInteractionMath.viewportFrame(
                                source,
                                pan: pan,
                                zoom: zoom
                            ),
                            target: linkingTargetID.flatMap {
                                displayedFrames[$0].map {
                                    CanvasInteractionMath.viewportFrame(
                                        $0,
                                        pan: pan,
                                        zoom: zoom
                                    )
                                }
                            },
                            pointer: linkingPointer
                        )
                    }
                    CanvasActivityEdgesLayer(
                        activities: visibleCanvasActivities,
                        frames: displayedFrames,
                        pan: pan,
                        zoom: zoom
                    )

                    ForEach(model.visibleTabs) { tab in
                        CanvasNodeCard(
                            tab: tab,
                            model: model,
                            settings: settings,
                            logicalFrame: logicalFrame(for: tab),
                            pan: pan,
                            zoom: zoom,
                            isLinkTarget: linkingTargetID == tab.id
                        )
                        .zIndex(model.selectedTabID == tab.id ? 2 : 1)
                    }

                    ForEach(model.externalAgentPins) { pin in
                        ExternalAgentCanvasCard(
                            pin: pin,
                            model: model,
                            logicalFrame: logicalFrame(for: pin),
                            pan: pan,
                            zoom: zoom
                        )
                        .zIndex(3)
                    }

                    ForEach(visibleCanvasActivities) { activity in
                        CanvasActivityCard(
                            activity: activity,
                            frame: CanvasAgentLayout.frame(
                                for: activity,
                                among: visibleCanvasActivities,
                                parent: displayedFrames[activity.parentTerminalID]
                            ),
                            pan: pan,
                            zoom: zoom
                        )
                        .zIndex(4)
                    }
                }

            }
            .overlay(alignment: .bottomTrailing) {
                CanvasControls(
                    zoom: zoom,
                    onZoomOut: { setZoom(zoom - 0.1, in: viewportSize) },
                    onZoomIn: { setZoom(zoom + 0.1, in: viewportSize) },
                    onReset: {
                        pan = .zero
                        zoom = 1
                        persistCamera()
                    },
                    onFit: { fit(in: viewportSize) },
                    onResetLayout: {
                        model.resetCanvasLayout()
                        pan = .zero
                        zoom = 1
                        persistCamera()
                    }
                )
                .padding(12)
            }
            .clipped()
            .dropDestination(for: String.self) { sessionIDs, location in
                guard let sessionID = sessionIDs.first,
                      let session = model.visibleUnmatchedAgentSessions.first(where: {
                          $0.id == sessionID
                      })
                else { return false }
                model.pinAgent(
                    session,
                    at: CGPoint(
                        x: (location.x - pan.width) / zoom,
                        y: (location.y - pan.height) / zoom
                    )
                )
                return true
            }
            .background {
                CanvasInteractionMonitor(
                    snapshot: interactionSnapshot,
                    onSelectTab: selectTab,
                    onActivateTab: activateTab,
                    onRenameTab: renameTab,
                    onCloseTab: closeTab,
                    onFocusAgent: focusAgent,
                    onCloseAgent: closeAgent,
                    onSelectBackground: {
                        model.selectedContextEdgeID = nil
                    },
                    onUpdateLink: updateLink,
                    onCreateLink: createLink,
                    onMoveNode: updateNodeFrame,
                    onResizeTab: updateTabFrame,
                    onPan: updateTrackpadPan,
                    onZoom: updateTrackpadZoom
                )
            }
        }
        .background(RibbitTheme.canvas)
        .onDisappear {
            cameraPersistenceTask?.cancel()
            persistCamera()
        }
    }

    private func updateTrackpadPan(_ delta: CGSize, ended: Bool) {
        pan = CGSize(
            width: pan.width + delta.width,
            height: pan.height + delta.height
        )
        if ended {
            scheduleCameraPersistence()
        }
    }

    private func updateTrackpadZoom(
        _ magnification: CGFloat,
        location: CGPoint,
        ended: Bool
    ) {
        let result = CanvasInteractionMath.zoom(
            currentZoom: zoom,
            pan: pan,
            magnification: magnification,
            anchor: location
        )
        zoom = result.zoom
        pan = result.pan
        if ended {
            scheduleCameraPersistence()
        }
    }

    private func setZoom(_ value: CGFloat, in available: CGSize) {
        let target = min(
            CanvasInteractionMetrics.maximumZoom,
            max(CanvasInteractionMetrics.minimumZoom, value)
        )
        let result = CanvasInteractionMath.zoom(
            currentZoom: zoom,
            pan: pan,
            magnification: target / zoom - 1,
            anchor: CGPoint(
                x: available.width / 2,
                y: available.height / 2
            )
        )
        zoom = result.zoom
        pan = result.pan
        persistCamera()
    }

    private func fit(in available: CGSize) {
        let frames = Array(displayedFrames.values)
            + visibleCanvasActivities.map {
                CanvasAgentLayout.frame(
                    for: $0,
                    among: visibleCanvasActivities,
                    parent: displayedFrames[$0.parentTerminalID]
                )
            }
        guard let camera = CanvasInteractionMath.fittedCamera(
            around: frames,
            in: available
        ) else {
            pan = .zero
            zoom = 1
            persistCamera()
            return
        }
        zoom = camera.zoom
        pan = CGSize(width: camera.x, height: camera.y)
        persistCamera()
    }

    private func persistCamera() {
        cameraPersistenceTask?.cancel()
        model.setCanvasCamera(CanvasCamera(
            x: pan.width,
            y: pan.height,
            zoom: zoom
        ))
    }

    private func scheduleCameraPersistence() {
        cameraPersistenceTask?.cancel()
        let camera = CanvasCamera(
            x: pan.width,
            y: pan.height,
            zoom: zoom
        )
        cameraPersistenceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            model.setCanvasCamera(camera)
        }
    }

    private var visibleCanvasActivities: [RibbitCanvasActivity] {
        let terminalIDs = Set(model.visibleTabs.map(\.id))
        return agentMonitor.canvasActivities.filter {
            terminalIDs.contains($0.parentTerminalID)
        }
    }

    private var displayedFrames: [UUID: CanvasNodeFrame] {
        Dictionary(uniqueKeysWithValues:
            model.visibleTabs.map { ($0.id, logicalFrame(for: $0)) }
                + model.externalAgentPins.map { ($0.id, logicalFrame(for: $0)) }
        )
    }

    private var interactionSnapshot: CanvasInteractionSnapshot {
        var nodes: [CanvasInteractionNode] = model.externalAgentPins.reversed().map {
            interactionNode(for: $0)
        }
        if let selected = model.visibleTabs.first(where: {
            $0.id == model.selectedTabID
        }) {
            nodes.append(interactionNode(for: selected))
        }
        nodes.append(contentsOf: model.visibleTabs.reversed().compactMap { tab in
            tab.id == model.selectedTabID ? nil : interactionNode(for: tab)
        })
        return CanvasInteractionSnapshot(
            zoom: zoom,
            nodesFrontToBack: nodes
        )
    }

    private func interactionNode(for tab: RibbitTab) -> CanvasInteractionNode {
        let frame = logicalFrame(for: tab)
        return CanvasInteractionNode(
            id: tab.id,
            kind: .tab,
            logicalFrame: frame,
            viewportFrame: CanvasInteractionMath.viewportFrame(
                frame,
                pan: pan,
                zoom: zoom
            ),
            hasAgentStatus: tab.agentSession != nil
        )
    }

    private func interactionNode(
        for pin: ExternalAgentPin
    ) -> CanvasInteractionNode {
        let frame = logicalFrame(for: pin)
        return CanvasInteractionNode(
            id: pin.id,
            kind: .agentPin,
            logicalFrame: frame,
            viewportFrame: CanvasInteractionMath.viewportFrame(
                frame,
                pan: pan,
                zoom: zoom
            ),
            hasAgentStatus: true
        )
    }

    private func logicalFrame(for tab: RibbitTab) -> CanvasNodeFrame {
        transientFrames[tab.id]
            ?? tab.canvasFrame
            ?? CanvasNodeFrame.initial(kind: tab.kind, index: 0)
    }

    private func logicalFrame(for pin: ExternalAgentPin) -> CanvasNodeFrame {
        transientFrames[pin.id] ?? pin.canvasFrame
    }

    private func selectTab(_ id: UUID) {
        guard let tab = model.visibleTabs.first(where: { $0.id == id }) else {
            return
        }
        model.selectedContextEdgeID = nil
        model.selectTab(tab)
    }

    private func activateTab(_ id: UUID) {
        guard let tab = model.visibleTabs.first(where: { $0.id == id }) else {
            return
        }
        model.activateTab(tab)
    }

    private func renameTab(_ id: UUID) {
        guard let tab = model.visibleTabs.first(where: {
            $0.id == id && $0.kind == .terminal
        }) else { return }
        model.promptToRenameTerminal(tab)
    }

    private func closeTab(_ id: UUID) {
        guard let tab = model.visibleTabs.first(where: { $0.id == id }) else {
            return
        }
        transientFrames.removeValue(forKey: id)
        model.closeTab(tab)
    }

    private func focusAgent(_ id: UUID) {
        guard let pin = model.externalAgentPins.first(where: {
            $0.id == id
        }) else { return }
        model.focusAgentPin(pin)
    }

    private func closeAgent(_ id: UUID) {
        guard let pin = model.externalAgentPins.first(where: {
            $0.id == id
        }) else { return }
        transientFrames.removeValue(forKey: id)
        model.unpinAgent(pin)
    }

    private func updateLink(
        sourceID: UUID,
        pointer: CGPoint,
        targetID: UUID?,
        ended: Bool
    ) {
        if ended {
            linkingSourceID = nil
            linkingTargetID = nil
            linkingPointer = nil
        } else {
            linkingSourceID = sourceID
            linkingTargetID = targetID
            linkingPointer = pointer
        }
    }

    private func createLink(sourceID: UUID, targetID: UUID) {
        guard let source = model.visibleTabs.first(where: {
            $0.id == sourceID
        }),
        let target = model.visibleTabs.first(where: {
            $0.id == targetID
        }) else { return }
        model.addContextLink(from: source, to: target)
    }

    private func updateNodeFrame(
        _ id: UUID,
        frame: CanvasNodeFrame,
        ended: Bool
    ) {
        transientFrames[id] = frame
        guard ended else { return }
        if let tab = model.visibleTabs.first(where: { $0.id == id }) {
            model.updateCanvasFrame(frame, for: tab)
        } else if let pin = model.externalAgentPins.first(where: {
            $0.id == id
        }) {
            model.updateExternalAgentPinFrame(frame, for: pin)
        }
        transientFrames.removeValue(forKey: id)
    }

    private func updateTabFrame(
        _ id: UUID,
        frame: CanvasNodeFrame,
        ended: Bool
    ) {
        transientFrames[id] = frame
        guard ended,
              let tab = model.visibleTabs.first(where: { $0.id == id })
        else { return }
        model.updateCanvasFrame(frame, for: tab)
        transientFrames.removeValue(forKey: id)
    }
}

private enum CanvasAgentLayout {
    static func frame(
        for activity: RibbitCanvasActivity,
        among activities: [RibbitCanvasActivity],
        parent: CanvasNodeFrame?
    ) -> CanvasNodeFrame {
        guard let parent else {
            return CanvasNodeFrame(x: 32, y: 32, width: 260, height: 104)
        }
        if activity.kind != .subagent {
            return CanvasNodeFrame(
                x: parent.x + 18,
                y: parent.y + parent.height + 64,
                width: 280,
                height: 104
            )
        }
        let siblings = activities
            .filter {
                $0.parentTerminalID == activity.parentTerminalID
                    && $0.kind == .subagent
            }
            .sorted { $0.startedAt < $1.startedAt }
        let index = siblings.firstIndex { $0.id == activity.id } ?? 0
        return CanvasNodeFrame(
            x: parent.x + parent.width + 72,
            y: parent.y + Double(index * 124),
            width: 280,
            height: 104
        )
    }
}

enum CanvasInteractionMath {
    static func viewportFrame(
        _ frame: CanvasNodeFrame,
        pan: CGSize,
        zoom: CGFloat
    ) -> CanvasNodeFrame {
        CanvasNodeFrame(
            x: pan.width + frame.x * zoom,
            y: pan.height + frame.y * zoom,
            width: frame.width * zoom,
            height: frame.height * zoom
        )
    }

    static func zoom(
        currentZoom: CGFloat,
        pan: CGSize,
        magnification: CGFloat,
        anchor: CGPoint
    ) -> (zoom: CGFloat, pan: CGSize) {
        let nextZoom = min(
            CanvasInteractionMetrics.maximumZoom,
            max(
                CanvasInteractionMetrics.minimumZoom,
                currentZoom * (1 + magnification)
            )
        )
        guard nextZoom != currentZoom else {
            return (currentZoom, pan)
        }
        let canvasX = (anchor.x - pan.width) / currentZoom
        let canvasY = (anchor.y - pan.height) / currentZoom
        return (
            nextZoom,
            CGSize(
                width: anchor.x - canvasX * nextZoom,
                height: anchor.y - canvasY * nextZoom
            )
        )
    }

    static func fittedCamera(
        around frames: [CanvasNodeFrame],
        in available: CGSize,
        margin: CGFloat = 32
    ) -> CanvasCamera? {
        guard let first = frames.first else { return nil }
        let minX = frames.reduce(first.x) { min($0, $1.x) }
        let minY = frames.reduce(first.y) { min($0, $1.y) }
        let maxX = frames.reduce(first.x + first.width) {
            max($0, $1.x + $1.width)
        }
        let maxY = frames.reduce(first.y + first.height) {
            max($0, $1.y + $1.height)
        }
        let contentWidth = max(1, maxX - minX)
        let contentHeight = max(1, maxY - minY)
        let availableWidth = Double(available.width)
        let availableHeight = Double(available.height)
        let outerMargin = Double(margin)
        let usableWidth = max(1, availableWidth - outerMargin * 2)
        let usableHeight = max(1, availableHeight - outerMargin * 2)
        let fitted = min(
            1,
            max(CanvasInteractionMetrics.minimumZoom, min(
                usableWidth / contentWidth,
                usableHeight / contentHeight
            ))
        )
        return CanvasCamera(
            x: (availableWidth - contentWidth * fitted) / 2 - minX * fitted,
            y: (availableHeight - contentHeight * fitted) / 2 - minY * fitted,
            zoom: fitted
        )
    }
}

private struct ExternalAgentCanvasCard: View {
    let pin: ExternalAgentPin
    @ObservedObject var model: AppModel
    let logicalFrame: CanvasNodeFrame
    let pan: CGSize
    let zoom: CGFloat

    private var nodeFrame: CanvasNodeFrame {
        logicalFrame
    }

    private var viewportFrame: CanvasNodeFrame {
        CanvasInteractionMath.viewportFrame(nodeFrame, pan: pan, zoom: zoom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    Color.clear
                        .contentShape(Rectangle())

                    HStack(spacing: 8) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(RibbitTheme.accent)

                        Text(pin.session.title)
                            .lineLimit(1)
                            .foregroundStyle(RibbitTheme.ink)

                        Spacer(minLength: 6)
                    }
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                AgentStatusBadge(
                    session: liveSession,
                    compact: true,
                    onActivate: {
                        model.focusAgentPin(pin)
                    }
                )

                Button {
                    model.unpinAgent(pin)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(RibbitTheme.muted)
                .help("remove agent from canvas")
            }
            .padding(.leading, 10)
            .padding(.trailing, 5)
            .frame(height: 34)
            .background(RibbitTheme.raised)

            Divider().overlay(RibbitTheme.rule)

            VStack(alignment: .leading, spacing: 8) {
                Text(liveSession.project)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(RibbitTheme.muted)
                Text(liveSession.activity)
                    .font(.system(size: 13))
                    .foregroundStyle(RibbitTheme.ink)
                    .lineLimit(2)
                if let detail = liveSession.attentionDetail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(RibbitTheme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button("focus session") {
                    model.focusAgentPin(pin)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(RibbitTheme.accent)
            }
            .padding(12)
        }
        .frame(width: nodeFrame.width, height: nodeFrame.height)
        .background(RibbitTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(RibbitTheme.accent.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
        .scaleEffect(zoom, anchor: .topLeading)
        .offset(x: viewportFrame.x, y: viewportFrame.y)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contextMenu {
            Button("remove from canvas", role: .destructive) {
                model.unpinAgent(pin)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(liveSession.agent.displayName), \(liveSession.state.label), \(liveSession.activity)"
        )
    }

    private var liveSession: RibbitAgentSession {
        model.agentMonitor.sessions.first { $0.id == pin.session.id } ?? pin.session
    }

}

private struct CanvasNodeCard: View {
    @ObservedObject var tab: RibbitTab
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let logicalFrame: CanvasNodeFrame
    let pan: CGSize
    let zoom: CGFloat
    let isLinkTarget: Bool

    private var nodeFrame: CanvasNodeFrame {
        logicalFrame
    }

    private var viewportFrame: CanvasNodeFrame {
        CanvasInteractionMath.viewportFrame(nodeFrame, pan: pan, zoom: zoom)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().overlay(RibbitTheme.rule)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .frame(width: nodeFrame.width, height: nodeFrame.height)
        .background(RibbitTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isLinkTarget
                        ? RibbitTheme.accent
                        : model.selectedTabID == tab.id
                        ? (tab.kind == .terminal ? tab.terminalTint.color : RibbitTheme.accent)
                        : RibbitTheme.rule,
                    lineWidth: isLinkTarget
                        ? 2
                        : model.selectedTabID == tab.id ? 1.5 : 1
                )
        }
        .overlay(alignment: .bottomTrailing) {
            resizeHandle
        }
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
        .scaleEffect(zoom, anchor: .topLeading)
        .offset(x: viewportFrame.x, y: viewportFrame.y)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .dropDestination(for: String.self) { sourceIDs, _ in
            guard let rawSourceID = sourceIDs.first,
                  let sourceID = UUID(uuidString: rawSourceID),
                  let source = model.visibleTabs.first(where: {
                      $0.id == sourceID && $0.id != tab.id
                  })
            else { return false }
            model.addContextLink(from: source, to: tab)
            return true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Color.clear
                    .contentShape(Rectangle())

                HStack(spacing: 8) {
                    Image(systemName: tab.kind.systemImage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tab.kind == .terminal ? tab.terminalTint.color : RibbitTheme.accent)

                    Text(tab.title)
                        .lineLimit(1)
                        .foregroundStyle(RibbitTheme.ink)

                    if tab.isDirty {
                        Circle()
                            .fill(RibbitTheme.accent)
                            .frame(width: 5, height: 5)
                    }

                    Spacer(minLength: 8)
                }
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let session = tab.agentSession {
                AgentStatusBadge(
                    session: session,
                    onActivate: {
                        model.focusAgentSession(session)
                    }
                )
            }

            Image(systemName: "arrow.right.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(RibbitTheme.muted)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
                .help("drag to another node to link context")

            Menu {
                let targets = model.visibleTabs.filter { $0.id != tab.id }
                if targets.isEmpty {
                    Text("no other nodes")
                } else {
                    ForEach(targets) { target in
                        Button {
                            model.addContextLink(from: tab, to: target)
                        } label: {
                            Label(target.title, systemImage: target.kind.systemImage)
                        }
                    }
                }

                let connected = model.contextEdges.filter {
                    $0.sourceTabID == tab.id || $0.targetTabID == tab.id
                }
                if !connected.isEmpty {
                    Divider()
                    ForEach(connected) { edge in
                        Button("remove link", role: .destructive) {
                            model.removeContextEdge(edge)
                        }
                    }
                }
            } label: {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .foregroundStyle(RibbitTheme.muted)
            .help("link this node’s context")

            if tab.kind == .terminal, tab.terminalSession?.isRunning == false {
                Text("exited")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(RibbitTheme.muted)
            }

            Button {
                model.closeTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(RibbitTheme.muted)
            .help("close \(tab.kind == .terminal ? "terminal" : "note")")
            .accessibilityLabel("close \(tab.title)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: 34)
        .background(RibbitTheme.raised)
    }

    @ViewBuilder
    private var content: some View {
        switch tab.kind {
        case .terminal:
            if let session = tab.terminalSession {
                ZStack(alignment: .top) {
                    TerminalRepresentable(
                        session: session,
                        settings: settings,
                        fontScale: CanvasInteractionMetrics
                            .terminalSurfaceFontScale(canvasZoom: zoom),
                        isActive: model.selectedTabID == tab.id
                    )
                        .id(tab.id)
                        .padding(6)
                    if let message = session.recoveryState.message {
                        TerminalRecoveryBanner(
                            message: message,
                            actionTitle: model.canResumeProviderSession(in: tab)
                                ? "resume \(tab.lastKnownAgent?.displayName ?? "agent")"
                                : nil,
                            onAction: {
                                model.resumeProviderSession(in: tab)
                            },
                            onDismiss: session.dismissRecoveryNotice
                        )
                        .padding(10)
                    }
                }
            }
        case .note:
            NoteEditor(
                text: Binding(
                    get: { tab.text },
                    set: { model.updateNoteText($0, for: tab) }
                ),
                fontSize: settings.editorTextSize
            ) {
                tab.isDirty = true
            }
        }
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(RibbitTheme.muted)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }
}

private struct CanvasLinkPreview: View {
    let source: CanvasNodeFrame
    let target: CanvasNodeFrame?
    let pointer: CGPoint

    var body: some View {
        Canvas { context, _ in
            let pointerFrame = CanvasNodeFrame(
                x: pointer.x,
                y: pointer.y,
                width: 0,
                height: 0
            )
            let geometry = CanvasConnectionGeometry(
                source: source,
                target: target ?? pointerFrame
            )
            var path = Path()
            path.move(to: geometry.start)
            path.addCurve(
                to: geometry.end,
                control1: geometry.control1,
                control2: geometry.control2
            )
            context.stroke(
                path,
                with: .color(RibbitTheme.canvas.opacity(0.92)),
                style: StrokeStyle(lineWidth: 4)
            )
            context.stroke(
                path,
                with: .color(RibbitTheme.accent.opacity(target == nil ? 0.72 : 1)),
                style: StrokeStyle(
                    lineWidth: target == nil ? 1.5 : 2,
                    dash: target == nil ? [5, 4] : []
                )
            )

            var arrow = Path()
            arrow.move(to: geometry.arrowTip)
            arrow.addLine(to: geometry.arrowLeft)
            arrow.addLine(to: geometry.arrowRight)
            arrow.closeSubpath()
            context.fill(arrow, with: .color(RibbitTheme.accent))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CanvasActivityEdgesLayer: View {
    let activities: [RibbitCanvasActivity]
    let frames: [UUID: CanvasNodeFrame]
    let pan: CGSize
    let zoom: CGFloat

    var body: some View {
        Canvas { context, _ in
            for activity in activities {
                guard let parent = frames[activity.parentTerminalID] else {
                    continue
                }
                let target = CanvasAgentLayout.frame(
                    for: activity,
                    among: activities,
                    parent: parent
                )
                let sourceFrame = CanvasInteractionMath.viewportFrame(
                    parent,
                    pan: pan,
                    zoom: zoom
                )
                let targetFrame = CanvasInteractionMath.viewportFrame(
                    target,
                    pan: pan,
                    zoom: zoom
                )
                let start = activity.kind == .subagent
                    ? CGPoint(
                        x: sourceFrame.x + sourceFrame.width,
                        y: sourceFrame.y + sourceFrame.height / 2
                    )
                    : CGPoint(
                        x: sourceFrame.x + sourceFrame.width / 2,
                        y: sourceFrame.y + sourceFrame.height
                    )
                let end = activity.kind == .subagent
                    ? CGPoint(x: targetFrame.x, y: targetFrame.y + targetFrame.height / 2)
                    : CGPoint(x: targetFrame.x + targetFrame.width / 2, y: targetFrame.y)
                var path = Path()
                path.move(to: start)
                if activity.kind == .subagent {
                    let control = max(44, abs(end.x - start.x) * 0.5)
                    path.addCurve(
                        to: end,
                        control1: CGPoint(x: start.x + control, y: start.y),
                        control2: CGPoint(x: end.x - control, y: end.y)
                    )
                } else {
                    let control = max(36, abs(end.y - start.y) * 0.5)
                    path.addCurve(
                        to: end,
                        control1: CGPoint(x: start.x, y: start.y + control),
                        control2: CGPoint(x: end.x, y: end.y - control)
                    )
                }
                context.stroke(
                    path,
                    with: .color(activity.color.opacity(0.7)),
                    style: StrokeStyle(
                        lineWidth: activity.state == .working ? 1.8 : 1.2,
                        dash: activity.state == .working ? [] : [5, 4]
                    )
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CanvasActivityCard: View {
    let activity: RibbitCanvasActivity
    let frame: CanvasNodeFrame
    let pan: CGSize
    let zoom: CGFloat

    private var viewportFrame: CanvasNodeFrame {
        CanvasInteractionMath.viewportFrame(frame, pan: pan, zoom: zoom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle()
                    .fill(activity.state == .working ? activity.color : RibbitTheme.muted)
                    .frame(width: 7, height: 7)
                Text(activity.label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(RibbitTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(activity.state == .working ? "working" : "done")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(activity.state == .working ? activity.color : RibbitTheme.muted)
            }

            Text(activity.task.isEmpty ? activity.schedule ?? "agent activity" : activity.task)
                .font(.system(size: 11))
                .foregroundStyle(RibbitTheme.muted)
                .lineLimit(2)

            HStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(activity.elapsedLabel(at: context.date))
                }
                if let tokens = activity.tokens {
                    Text("· \(tokens.formatted()) tokens")
                }
                if let toolUses = activity.toolUses {
                    Text("· \(toolUses) tools")
                }
                if let schedule = activity.schedule, !schedule.isEmpty {
                    Text("· \(schedule)")
                        .lineLimit(1)
                }
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(RibbitTheme.muted)
        }
        .padding(12)
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .background(RibbitTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(activity.color.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .scaleEffect(zoom, anchor: .topLeading)
        .offset(x: viewportFrame.x, y: viewportFrame.y)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(activity.label), \(activity.state.rawValue), \(activity.task)"
        )
    }
}

@MainActor
private extension RibbitCanvasActivity {
    var color: Color {
        switch kind {
        case .subagent: RibbitTheme.accent
        case .cron, .loop, .schedule: Color(nsColor: .systemPurple)
        }
    }

    var label: String {
        switch kind {
        case .subagent: type ?? "subagent"
        case .cron: "cron"
        case .loop: "loop"
        case .schedule: "schedule"
        }
    }

    func elapsedLabel(at now: Date) -> String {
        let milliseconds = durationMilliseconds
            ?? Int((finishedAt ?? now).timeIntervalSince(startedAt) * 1_000)
        let seconds = max(0, milliseconds / 1_000)
        return seconds < 60
            ? "\(seconds)s"
            : "\(seconds / 60)m \(seconds % 60)s"
    }
}

private struct ContextEdgesLayer: View {
    @ObservedObject var model: AppModel
    let frames: [UUID: CanvasNodeFrame]
    let pan: CGSize
    let zoom: CGFloat

    var body: some View {
        GeometryReader { _ in
            ForEach(model.contextEdges) { edge in
                if let sourceFrame = frames[edge.sourceTabID],
                   let targetFrame = frames[edge.targetTabID] {
                    let hasReverseEdge = model.contextEdges.contains {
                        $0.sourceTabID == edge.targetTabID
                            && $0.targetTabID == edge.sourceTabID
                    }
                    ContextEdgeView(
                        edge: edge,
                        source: CanvasInteractionMath.viewportFrame(
                            sourceFrame,
                            pan: pan,
                            zoom: zoom
                        ),
                        target: CanvasInteractionMath.viewportFrame(
                            targetFrame,
                            pan: pan,
                            zoom: zoom
                        ),
                        isSelected: model.selectedContextEdgeID == edge.id,
                        zoom: zoom,
                        laneOffset: hasReverseEdge
                            ? (edge.sourceTabID.uuidString
                                < edge.targetTabID.uuidString ? -10 : 10)
                            : 0,
                        onSelect: { model.selectContextEdge(edge) },
                        onDelete: { model.removeContextEdge(edge) }
                    )
                }
            }
        }
    }
}

private struct ContextEdgeView: View {
    let edge: ContextEdge
    let source: CanvasNodeFrame
    let target: CanvasNodeFrame
    let isSelected: Bool
    let zoom: CGFloat
    let laneOffset: CGFloat
    let onSelect: () -> Void
    let onDelete: () -> Void

    private var geometry: CanvasConnectionGeometry {
        CanvasConnectionGeometry(
            source: source,
            target: target,
            laneOffset: laneOffset
        )
    }

    private var controlSize: CGFloat {
        min(28, max(20, 28 * zoom))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                var path = Path()
                path.move(to: geometry.start)
                path.addCurve(
                    to: geometry.end,
                    control1: geometry.control1,
                    control2: geometry.control2
                )
                context.stroke(
                    path,
                    with: .color(RibbitTheme.canvas.opacity(0.92)),
                    style: StrokeStyle(lineWidth: isSelected ? 5 : 4)
                )
                context.stroke(
                    path,
                    with: .color(
                        isSelected
                            ? RibbitTheme.accent
                            : RibbitTheme.muted.opacity(0.78)
                    ),
                    style: StrokeStyle(lineWidth: isSelected ? 2.2 : 1.45)
                )

                var arrow = Path()
                arrow.move(to: geometry.arrowTip)
                arrow.addLine(to: geometry.arrowLeft)
                arrow.addLine(to: geometry.arrowRight)
                arrow.closeSubpath()
                context.fill(
                    arrow,
                    with: .color(isSelected ? RibbitTheme.accent : RibbitTheme.muted)
                )
            }
            .allowsHitTesting(false)

            Button(action: onSelect) {
                Image(systemName: isSelected ? "link.circle.fill" : "link.circle")
                    .font(.system(
                        size: min(14, max(10, 14 * zoom)),
                        weight: .medium
                    ))
                    .frame(width: controlSize, height: controlSize)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isSelected ? RibbitTheme.accent : RibbitTheme.muted)
            .background(RibbitTheme.raised.opacity(0.92))
            .clipShape(Circle())
            .offset(
                x: geometry.midpoint.x - controlSize / 2,
                y: geometry.midpoint.y - controlSize / 2
            )
            .contextMenu {
                Button("remove context link", role: .destructive, action: onDelete)
            }
            .help("context link — click to select, right-click to remove")
        }
    }
}

struct CanvasConnectionGeometry: Equatable {
    let start: CGPoint
    let end: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let midpoint: CGPoint
    let arrowTip: CGPoint
    let arrowLeft: CGPoint
    let arrowRight: CGPoint

    init(
        source: CanvasNodeFrame,
        target: CanvasNodeFrame,
        laneOffset: CGFloat = 0
    ) {
        let sourceCenter = CGPoint(
            x: source.x + source.width / 2,
            y: source.y + source.height / 2
        )
        let targetCenter = CGPoint(
            x: target.x + target.width / 2,
            y: target.y + target.height / 2
        )
        let deltaX = targetCenter.x - sourceCenter.x
        let deltaY = targetCenter.y - sourceCenter.y

        if abs(deltaX) >= abs(deltaY) {
            let direction: CGFloat = deltaX >= 0 ? 1 : -1
            start = CGPoint(
                x: direction > 0 ? source.x + source.width : source.x,
                y: sourceCenter.y + laneOffset
            )
            end = CGPoint(
                x: direction > 0 ? target.x : target.x + target.width,
                y: targetCenter.y + laneOffset
            )
            let control = max(48, abs(end.x - start.x) * 0.45)
            control1 = CGPoint(
                x: start.x + direction * control,
                y: start.y
            )
            control2 = CGPoint(
                x: end.x - direction * control,
                y: end.y
            )
        } else {
            let direction: CGFloat = deltaY >= 0 ? 1 : -1
            start = CGPoint(
                x: sourceCenter.x + laneOffset,
                y: direction > 0 ? source.y + source.height : source.y
            )
            end = CGPoint(
                x: targetCenter.x + laneOffset,
                y: direction > 0 ? target.y : target.y + target.height
            )
            let control = max(48, abs(end.y - start.y) * 0.45)
            control1 = CGPoint(
                x: start.x,
                y: start.y + direction * control
            )
            control2 = CGPoint(
                x: end.x,
                y: end.y - direction * control
            )
        }

        midpoint = Self.point(
            at: 0.5,
            start: start,
            control1: control1,
            control2: control2,
            end: end
        )
        arrowTip = end
        let tangent = CGVector(
            dx: end.x - control2.x,
            dy: end.y - control2.y
        )
        let length = max(0.001, hypot(tangent.dx, tangent.dy))
        let unit = CGVector(dx: tangent.dx / length, dy: tangent.dy / length)
        let base = CGPoint(
            x: end.x - unit.dx * 10,
            y: end.y - unit.dy * 10
        )
        arrowLeft = CGPoint(
            x: base.x - unit.dy * 4.5,
            y: base.y + unit.dx * 4.5
        )
        arrowRight = CGPoint(
            x: base.x + unit.dy * 4.5,
            y: base.y - unit.dx * 4.5
        )
    }

    private static func point(
        at t: CGFloat,
        start: CGPoint,
        control1: CGPoint,
        control2: CGPoint,
        end: CGPoint
    ) -> CGPoint {
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * inverse * start.x
                + 3 * inverse * inverse * t * control1.x
                + 3 * inverse * t * t * control2.x
                + t * t * t * end.x,
            y: inverse * inverse * inverse * start.y
                + 3 * inverse * inverse * t * control1.y
                + 3 * inverse * t * t * control2.y
                + t * t * t * end.y
        )
    }
}

private struct CanvasGrid: View {
    let pan: CGSize
    let zoom: CGFloat

    var body: some View {
        Canvas { context, size in
            let spacing = max(16, 28 * zoom)
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1.5, height: 1.5))
            let startX = pan.width.truncatingRemainder(dividingBy: spacing)
            let startY = pan.height.truncatingRemainder(dividingBy: spacing)
            for x in stride(from: startX, through: size.width, by: spacing) {
                for y in stride(from: startY, through: size.height, by: spacing) {
                    context.drawLayer { layer in
                        layer.translateBy(x: x, y: y)
                        layer.fill(dot, with: .color(RibbitTheme.rule.opacity(0.8)))
                    }
                }
            }
        }
        .background(RibbitTheme.canvas)
    }
}

private struct CanvasControls: View {
    let zoom: CGFloat
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onReset: () -> Void
    let onFit: () -> Void
    let onResetLayout: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            controlButton("minus", help: "zoom out", action: onZoomOut)
            Button(action: onReset) {
                Text("\(Int((zoom * 100).rounded()))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .frame(width: 48, height: 28)
            }
            .buttonStyle(.plain)
            .help("reset zoom")
            controlButton("plus", help: "zoom in", action: onZoomIn)
            Divider().frame(height: 16)
            controlButton("arrow.up.left.and.arrow.down.right", help: "fit nodes", action: onFit)
            Menu {
                Button("reset node layout", systemImage: "rectangle.3.group") {
                    onResetLayout()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .foregroundStyle(RibbitTheme.muted)
        .padding(4)
        .background(RibbitTheme.raised.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(RibbitTheme.rule, lineWidth: 1)
        }
    }

    private func controlButton(
        _ systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
