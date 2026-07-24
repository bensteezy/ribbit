import AppKit
import SwiftUI

struct TerminalCanvasWorkspace: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    @State private var pan = CGSize.zero
    @State private var zoom: CGFloat = 1
    @State private var transientFrames: [UUID: CanvasNodeFrame] = [:]

    init(model: AppModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        _pan = State(initialValue: CGSize(
            width: model.canvasCamera.x,
            height: model.canvasCamera.y
        ))
        _zoom = State(initialValue: model.canvasCamera.zoom)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                CanvasGrid(pan: pan, zoom: zoom)
                    .allowsHitTesting(false)

                ZStack(alignment: .topLeading) {
                    CanvasGroupsLayer(model: model, pan: pan, zoom: zoom)
                    ContextEdgesLayer(model: model, pan: pan, zoom: zoom)

                    ForEach(model.visibleTabs) { tab in
                        CanvasNodeCard(
                            tab: tab,
                            model: model,
                            settings: settings,
                            logicalFrame: logicalFrame(for: tab),
                            pan: pan,
                            zoom: zoom
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
                }

            }
            .overlay(alignment: .bottomTrailing) {
                CanvasControls(
                    zoom: zoom,
                    onZoomOut: { setZoom(zoom - 0.1) },
                    onZoomIn: { setZoom(zoom + 0.1) },
                    onReset: {
                        pan = .zero
                        zoom = 1
                        persistCamera()
                    },
                    onFit: { fit(in: proxy.size) },
                    onResetLayout: {
                        model.resetCanvasLayout()
                        pan = .zero
                        zoom = 1
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
                    onMoveNode: updateNodeFrame,
                    onResizeTab: updateTabFrame,
                    onPan: updateTrackpadPan,
                    onZoom: updateTrackpadZoom
                )
            }
        }
        .background(RibbitTheme.canvas)
    }

    private func updateTrackpadPan(_ delta: CGSize, ended: Bool) {
        pan = CGSize(
            width: pan.width + delta.width,
            height: pan.height + delta.height
        )
        if ended {
            persistCamera()
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
            persistCamera()
        }
    }

    private func setZoom(_ value: CGFloat) {
        zoom = min(1.5, max(0.5, value))
        persistCamera()
    }

    private func fit(in available: CGSize) {
        let frames = model.visibleTabs.compactMap(\.canvasFrame)
            + model.externalAgentPins.map(\.canvasFrame)
        guard let first = frames.first else {
            pan = .zero
            zoom = 1
            return
        }
        let minX = frames.reduce(first.x) { min($0, $1.x) }
        let minY = frames.reduce(first.y) { min($0, $1.y) }
        let maxX = frames.reduce(first.x + first.width) { max($0, $1.x + $1.width) }
        let maxY = frames.reduce(first.y + first.height) { max($0, $1.y + $1.height) }
        let contentWidth = max(1, maxX - minX)
        let contentHeight = max(1, maxY - minY)
        let fitted = min(
            1,
            max(0.5, min((available.width - 64) / contentWidth, (available.height - 64) / contentHeight))
        )
        zoom = fitted
        pan = CGSize(
            width: 32 - minX * fitted,
            height: 32 - minY * fitted
        )
        persistCamera()
    }

    private func persistCamera() {
        model.setCanvasCamera(CanvasCamera(
            x: pan.width,
            y: pan.height,
            zoom: zoom
        ))
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
        let nextZoom = min(1.5, max(0.5, currentZoom * (1 + magnification)))
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
}

private struct CanvasGroupsLayer: View {
    @ObservedObject var model: AppModel
    let pan: CGSize
    let zoom: CGFloat

    var body: some View {
        GeometryReader { _ in
            ForEach(model.canvasGroups) { group in
                let frames = group.nodeIDs.compactMap { model.canvasFrame(for: $0) }
                if frames.count >= 2 {
                    CanvasGroupBoundary(
                        group: group,
                        frame: CanvasInteractionMath.viewportFrame(
                            enclosingFrame(frames),
                            pan: pan,
                            zoom: zoom
                        ),
                        onDelete: { model.removeCanvasGroup(group) }
                    )
                }
            }
        }
    }

    private func enclosingFrame(_ frames: [CanvasNodeFrame]) -> CanvasNodeFrame {
        let minX = frames.map(\.x).min() ?? 0
        let minY = frames.map(\.y).min() ?? 0
        let maxX = frames.map { $0.x + $0.width }.max() ?? minX
        let maxY = frames.map { $0.y + $0.height }.max() ?? minY
        return CanvasNodeFrame(
            x: minX - 18,
            y: minY - 42,
            width: maxX - minX + 36,
            height: maxY - minY + 60
        )
    }
}

private struct CanvasGroupBoundary: View {
    let group: CanvasGroup
    let frame: CanvasNodeFrame
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(RibbitTheme.accent.opacity(0.025))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            RibbitTheme.accent.opacity(0.28),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                        )
                }
                .allowsHitTesting(false)

            Menu {
                Button("remove group", role: .destructive, action: onDelete)
            } label: {
                Label(group.name, systemImage: "square.3.layers.3d")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(RibbitTheme.muted)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(RibbitTheme.raised)
                    .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(8)
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.x, y: frame.y)
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
            Menu("group with", systemImage: "square.3.layers.3d") {
                ForEach(model.visibleTabs) { tab in
                    Button(tab.title) {
                        model.groupNode(pin.id, with: tab.id)
                    }
                }
                ForEach(model.externalAgentPins.filter { $0.id != pin.id }) { target in
                    Button(target.session.title) {
                        model.groupNode(pin.id, with: target.id)
                    }
                }
            }
            if model.canvasGroups.contains(where: { $0.nodeIDs.contains(pin.id) }) {
                Button("remove from group", role: .destructive) {
                    model.removeNodeFromCanvasGroup(pin.id)
                }
            }
            Divider()
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
                    model.selectedTabID == tab.id
                        ? (tab.kind == .terminal ? tab.terminalTint.color : RibbitTheme.accent)
                        : RibbitTheme.rule,
                    lineWidth: model.selectedTabID == tab.id ? 1.5 : 1
                )
        }
        .overlay(alignment: .bottomTrailing) {
            resizeHandle
        }
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
        .scaleEffect(zoom, anchor: .topLeading)
        .offset(x: viewportFrame.x, y: viewportFrame.y)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

                Divider()

                Menu("group with", systemImage: "square.3.layers.3d") {
                    ForEach(model.visibleTabs.filter { $0.id != tab.id }) { target in
                        Button(target.title) {
                            model.groupNode(tab.id, with: target.id)
                        }
                    }
                    ForEach(model.externalAgentPins) { pin in
                        Button(pin.session.title) {
                            model.groupNode(tab.id, with: pin.id)
                        }
                    }
                }

                if model.canvasGroups.contains(where: { $0.nodeIDs.contains(tab.id) }) {
                    Button("remove from group", role: .destructive) {
                        model.removeNodeFromCanvasGroup(tab.id)
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

private struct ContextEdgesLayer: View {
    @ObservedObject var model: AppModel
    let pan: CGSize
    let zoom: CGFloat

    var body: some View {
        GeometryReader { _ in
            ForEach(model.contextEdges) { edge in
                if let source = model.visibleTabs.first(where: { $0.id == edge.sourceTabID }),
                   let target = model.visibleTabs.first(where: { $0.id == edge.targetTabID }),
                   let sourceFrame = source.canvasFrame,
                   let targetFrame = target.canvasFrame {
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
    let onSelect: () -> Void
    let onDelete: () -> Void

    private var direction: CGFloat {
        let sourceCenter = source.x + source.width / 2
        let targetCenter = target.x + target.width / 2
        return targetCenter >= sourceCenter ? 1 : -1
    }

    private var start: CGPoint {
        CGPoint(
            x: direction > 0 ? source.x + source.width : source.x,
            y: source.y + source.height / 2
        )
    }

    private var end: CGPoint {
        CGPoint(
            x: direction > 0 ? target.x : target.x + target.width,
            y: target.y + target.height / 2
        )
    }

    private var midpoint: CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                var path = Path()
                path.move(to: start)
                let controlOffset = max(56, abs(end.x - start.x) * 0.45)
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: start.x + direction * controlOffset, y: start.y),
                    control2: CGPoint(x: end.x - direction * controlOffset, y: end.y)
                )
                context.stroke(
                    path,
                    with: .color(isSelected ? RibbitTheme.accent : RibbitTheme.muted.opacity(0.65)),
                    style: StrokeStyle(lineWidth: isSelected ? 2 : 1.25, dash: [6, 5])
                )

                var arrow = Path()
                arrow.move(to: end)
                arrow.addLine(to: CGPoint(x: end.x - direction * 10, y: end.y - 5))
                arrow.addLine(to: CGPoint(x: end.x - direction * 10, y: end.y + 5))
                arrow.closeSubpath()
                context.fill(
                    arrow,
                    with: .color(isSelected ? RibbitTheme.accent : RibbitTheme.muted)
                )
            }
            .allowsHitTesting(false)

            Button(action: onSelect) {
                Image(systemName: isSelected ? "link.circle.fill" : "link.circle")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isSelected ? RibbitTheme.accent : RibbitTheme.muted)
            .background(RibbitTheme.raised.opacity(0.92))
            .clipShape(Circle())
            .offset(x: midpoint.x - 14, y: midpoint.y - 14)
            .contextMenu {
                Button("remove context link", role: .destructive, action: onDelete)
            }
            .help("context link — click to select, right-click to remove")
        }
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
