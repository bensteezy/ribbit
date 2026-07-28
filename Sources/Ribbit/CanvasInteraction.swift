import AppKit
import SwiftUI

enum CanvasInteractionNodeKind: Equatable {
    case tab
    case agentPin
}

enum CanvasResizeHandle: Equatable, CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var resizesLeft: Bool {
        self == .topLeft || self == .bottomLeft || self == .left
    }

    var resizesRight: Bool {
        self == .topRight || self == .bottomRight || self == .right
    }

    var resizesTop: Bool {
        self == .topLeft || self == .topRight || self == .top
    }

    var resizesBottom: Bool {
        self == .bottomLeft || self == .bottomRight || self == .bottom
    }
}

struct CanvasInteractionNode: Equatable, Identifiable {
    let id: UUID
    let kind: CanvasInteractionNodeKind
    let logicalFrame: CanvasNodeFrame
    let viewportFrame: CanvasNodeFrame
    let hasAgentStatus: Bool

    var viewportRect: CGRect {
        CGRect(
            x: viewportFrame.x,
            y: viewportFrame.y,
            width: viewportFrame.width,
            height: viewportFrame.height
        )
    }
}

struct CanvasInteractionSnapshot: Equatable {
    var zoom: CGFloat
    var nodesFrontToBack: [CanvasInteractionNode]

    static let empty = CanvasInteractionSnapshot(
        zoom: 1,
        nodesFrontToBack: []
    )
}

enum CanvasHitTarget: Equatable {
    case tabBody(UUID)
    case tabHeader(UUID)
    case tabControl(UUID)
    case tabClose(UUID)
    case tabLink(UUID)
    case tabResize(UUID, CanvasResizeHandle)
    case agentBody(UUID)
    case agentHeader(UUID)
    case agentControl(UUID)
    case agentClose(UUID)
    case background
}

enum CanvasInteractionMetrics {
    static let minimumZoom: CGFloat = 0.25
    static let maximumZoom: CGFloat = 2
    static let headerHeight: CGFloat = 34
    // The glyph stays visually small, while the interaction target is forgiving.
    static let closeTargetWidth: CGFloat = 44
    static let resizeEdgeTargetWidth: CGFloat = 10
    static let resizeCornerTargetSize: CGFloat = 30
    static let tabToolbarWidth: CGFloat = 42
    static let agentStatusWidth: CGFloat = 116
    static let minimumNodeWidth: CGFloat = 300
    static let minimumNodeHeight: CGFloat = 220

    static func terminalFontSize(base: Double, zoom: CGFloat) -> Double {
        min(32, max(8, base * zoom))
    }

    static func editorFontSize(base: Double, zoom: CGFloat) -> Double {
        min(32, max(8, base * zoom))
    }

    // Canvas cards are composited at the camera scale. Keeping Ghostty at its
    // base font avoids a full scrollback reflow every time the user switches
    // between canvas and tab presentation.
    static func terminalSurfaceFontScale(canvasZoom: CGFloat) -> CGFloat {
        1
    }
}

enum CanvasInteractionHitTester {
    static func target(
        at point: CGPoint,
        snapshot: CanvasInteractionSnapshot
    ) -> CanvasHitTarget {
        for node in snapshot.nodesFrontToBack {
            let frame = node.viewportRect
            guard frame.contains(point) else { continue }
            let scale = max(0.5, snapshot.zoom)
            let closeTargetWidth =
                CanvasInteractionMetrics.closeTargetWidth * scale

            let closeRect = CGRect(
                x: frame.maxX - closeTargetWidth,
                y: frame.minY,
                width: closeTargetWidth,
                height: min(closeTargetWidth, frame.height)
            )
            if closeRect.contains(point) {
                let onResizeBorder = node.kind == .tab
                    && (
                        point.x >= frame.maxX
                            - CanvasInteractionMetrics.resizeEdgeTargetWidth
                                * scale
                        || point.y <= frame.minY
                            + CanvasInteractionMetrics.resizeEdgeTargetWidth
                                * scale
                    )
                if !onResizeBorder {
                    return node.kind == .tab
                        ? .tabClose(node.id)
                        : .agentClose(node.id)
                }
            }

            if node.kind == .tab,
               let handle = resizeHandle(
                   at: point,
                   in: frame,
                   scale: scale
               ) {
                return .tabResize(node.id, handle)
            }

            let headerRect = CGRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width,
                height: min(
                    CanvasInteractionMetrics.headerHeight * scale,
                    frame.height
                )
            )
            if headerRect.contains(point) {
                if node.kind == .tab {
                    let trailing = 5 * scale
                    let closeWidth = 32 * scale
                    let menuWidth = 26 * scale
                    let linkWidth = 24 * scale
                    let linkMaxX = frame.maxX
                        - trailing
                        - closeWidth
                        - menuWidth
                    let linkRect = CGRect(
                        x: linkMaxX - linkWidth,
                        y: frame.minY,
                        width: linkWidth,
                        height: headerRect.height
                    ).insetBy(dx: -3 * scale, dy: 0)
                    if linkRect.contains(point) {
                        return .tabLink(node.id)
                    }
                }
                let statusWidth = node.hasAgentStatus
                    ? CanvasInteractionMetrics.agentStatusWidth * scale
                    : 0
                let controlsWidth: CGFloat
                switch node.kind {
                case .tab:
                    controlsWidth = closeTargetWidth
                        + CanvasInteractionMetrics.tabToolbarWidth * scale
                        + statusWidth
                case .agentPin:
                    controlsWidth = closeTargetWidth
                        + statusWidth
                }
                if point.x >= frame.maxX - controlsWidth {
                    return node.kind == .tab
                        ? .tabControl(node.id)
                        : .agentControl(node.id)
                }
                return node.kind == .tab
                    ? .tabHeader(node.id)
                    : .agentHeader(node.id)
            }

            return node.kind == .tab
                ? .tabBody(node.id)
                : .agentBody(node.id)
        }
        return .background
    }

    static func resizeHandle(
        at point: CGPoint,
        in frame: CGRect,
        scale: CGFloat = 1
    ) -> CanvasResizeHandle? {
        let corner = min(
            CanvasInteractionMetrics.resizeCornerTargetSize * scale,
            frame.width / 3,
            frame.height / 3
        )
        let edge = CanvasInteractionMetrics.resizeEdgeTargetWidth * scale
        let nearLeft = point.x <= frame.minX + edge
        let nearRight = point.x >= frame.maxX - edge
        let nearTop = point.y <= frame.minY + edge
        let nearBottom = point.y >= frame.maxY - edge
        let inLeftCorner = point.x <= frame.minX + corner
        let inRightCorner = point.x >= frame.maxX - corner
        let inTopCorner = point.y <= frame.minY + corner
        let inBottomCorner = point.y >= frame.maxY - corner

        if inLeftCorner && inTopCorner { return .topLeft }
        if inRightCorner && inTopCorner { return .topRight }
        if inRightCorner && inBottomCorner { return .bottomRight }
        if inLeftCorner && inBottomCorner { return .bottomLeft }
        if nearTop { return .top }
        if nearRight { return .right }
        if nearBottom { return .bottom }
        if nearLeft { return .left }
        return nil
    }

    static func translatedFrame(
        _ frame: CanvasNodeFrame,
        from start: CGPoint,
        to current: CGPoint,
        zoom: CGFloat
    ) -> CanvasNodeFrame {
        frame.movedBy(
            width: (current.x - start.x) / max(zoom, 0.01),
            height: (current.y - start.y) / max(zoom, 0.01)
        )
    }

    static func resizedFrame(
        _ frame: CanvasNodeFrame,
        from start: CGPoint,
        to current: CGPoint,
        zoom: CGFloat,
        handle: CanvasResizeHandle
    ) -> CanvasNodeFrame {
        let deltaX = (current.x - start.x) / max(zoom, 0.01)
        let deltaY = (current.y - start.y) / max(zoom, 0.01)
        let originalMaxX = frame.x + frame.width
        let originalMaxY = frame.y + frame.height
        var result = frame

        if handle.resizesLeft {
            result.width = max(
                CanvasInteractionMetrics.minimumNodeWidth,
                frame.width - deltaX
            )
            result.x = originalMaxX - result.width
        } else if handle.resizesRight {
            result.width = max(
                CanvasInteractionMetrics.minimumNodeWidth,
                frame.width + deltaX
            )
        }

        if handle.resizesTop {
            result.height = max(
                CanvasInteractionMetrics.minimumNodeHeight,
                frame.height - deltaY
            )
            result.y = originalMaxY - result.height
        } else if handle.resizesBottom {
            result.height = max(
                CanvasInteractionMetrics.minimumNodeHeight,
                frame.height + deltaY
            )
        }

        return result
    }

    static func accessibilityResizeDescription(
        for handle: CanvasResizeHandle
    ) -> String {
        switch handle {
        case .topLeft: "top-left corner"
        case .top: "top edge"
        case .topRight: "top-right corner"
        case .right: "right edge"
        case .bottomRight: "bottom-right corner"
        case .bottom: "bottom edge"
        case .bottomLeft: "bottom-left corner"
        case .left: "left edge"
        }
    }
}

struct CanvasInteractionMonitor: NSViewRepresentable {
    let snapshot: CanvasInteractionSnapshot
    let onSelectTab: (UUID) -> Void
    let onActivateTab: (UUID) -> Void
    let onRenameTab: (UUID) -> Void
    let onCloseTab: (UUID) -> Void
    let onFocusAgent: (UUID) -> Void
    let onCloseAgent: (UUID) -> Void
    let onSelectBackground: () -> Void
    let onUpdateLink: (UUID, CGPoint, UUID?, Bool) -> Void
    let onCreateLink: (UUID, UUID) -> Void
    let onMoveNode: (UUID, CanvasNodeFrame, Bool) -> Void
    let onResizeTab: (UUID, CanvasNodeFrame, Bool) -> Void
    let onPan: (CGSize, Bool) -> Void
    let onZoom: (CGFloat, CGPoint, Bool) -> Void

    func makeNSView(context: Context) -> CanvasInteractionMonitorView {
        let view = CanvasInteractionMonitorView()
        update(view)
        return view
    }

    func updateNSView(
        _ nsView: CanvasInteractionMonitorView,
        context: Context
    ) {
        update(nsView)
    }

    static func dismantleNSView(
        _ nsView: CanvasInteractionMonitorView,
        coordinator: ()
    ) {
        nsView.stopMonitoring()
    }

    private func update(_ view: CanvasInteractionMonitorView) {
        view.snapshot = snapshot
        view.onSelectTab = onSelectTab
        view.onActivateTab = onActivateTab
        view.onRenameTab = onRenameTab
        view.onCloseTab = onCloseTab
        view.onFocusAgent = onFocusAgent
        view.onCloseAgent = onCloseAgent
        view.onSelectBackground = onSelectBackground
        view.onUpdateLink = onUpdateLink
        view.onCreateLink = onCreateLink
        view.onMoveNode = onMoveNode
        view.onResizeTab = onResizeTab
        view.onPan = onPan
        view.onZoom = onZoom
    }
}

@MainActor
final class CanvasInteractionMonitorView: NSView {
    var snapshot = CanvasInteractionSnapshot.empty
    var onSelectTab: (UUID) -> Void = { _ in }
    var onActivateTab: (UUID) -> Void = { _ in }
    var onRenameTab: (UUID) -> Void = { _ in }
    var onCloseTab: (UUID) -> Void = { _ in }
    var onFocusAgent: (UUID) -> Void = { _ in }
    var onCloseAgent: (UUID) -> Void = { _ in }
    var onSelectBackground: () -> Void = {}
    var onUpdateLink: (UUID, CGPoint, UUID?, Bool) -> Void = {
        _, _, _, _ in
    }
    var onCreateLink: (UUID, UUID) -> Void = { _, _ in }
    var onMoveNode: (UUID, CanvasNodeFrame, Bool) -> Void = { _, _, _ in }
    var onResizeTab: (UUID, CanvasNodeFrame, Bool) -> Void = { _, _, _ in }
    var onPan: (CGSize, Bool) -> Void = { _, _ in }
    var onZoom: (CGFloat, CGPoint, Bool) -> Void = { _, _, _ in }

    private enum OperationKind {
        case moveTab
        case resizeTab
        case moveAgent
        case closeTab
        case closeAgent
        case linkTab
        case pan
    }

    private struct Operation {
        let kind: OperationKind
        let id: UUID?
        let startPoint: CGPoint
        var lastPoint: CGPoint
        let originalFrame: CanvasNodeFrame?
        let resizeHandle: CanvasResizeHandle?
        let clickCount: Int
        var didDrag = false
    }

    private var eventMonitor: Any?
    private var operation: Operation?

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .leftMouseDown,
                .leftMouseDragged,
                .leftMouseUp,
                .otherMouseDown,
                .otherMouseDragged,
                .otherMouseUp,
                .mouseMoved,
                .cursorUpdate,
                .scrollWheel,
                .magnify
            ]
        ) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        operation = nil
        NSCursor.arrow.set()
    }

    func handleForTesting(_ event: NSEvent) -> NSEvent? {
        handle(event)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else {
            NSCursor.arrow.set()
            return event
        }

        switch event.type {
        case .leftMouseDown:
            return beginLeftMouse(
                at: location,
                clickCount: event.clickCount
            ) ? nil : event
        case .leftMouseDragged:
            return dragPointer(to: location) ? nil : event
        case .leftMouseUp:
            return endPointer(at: location) ? nil : event
        case .otherMouseDown where event.buttonNumber == 2:
            operation = Operation(
                kind: .pan,
                id: nil,
                startPoint: location,
                lastPoint: location,
                originalFrame: nil,
                resizeHandle: nil,
                clickCount: event.clickCount
            )
            return nil
        case .otherMouseDragged where event.buttonNumber == 2:
            return dragPointer(to: location) ? nil : event
        case .otherMouseUp where event.buttonNumber == 2:
            return endPointer(at: location) ? nil : event
        case .mouseMoved, .cursorUpdate:
            return updateCursor(at: location) ? nil : event
        case .scrollWheel:
            return handleScroll(event, at: location)
        case .magnify:
            routeMagnification(
                event.magnification,
                at: location,
                ended: Self.isGestureEnded(event)
            )
            return nil
        default:
            return event
        }
    }

    func beginLeftMouseForTesting(
        at location: CGPoint,
        clickCount: Int = 1
    ) -> Bool {
        beginLeftMouse(at: location, clickCount: clickCount)
    }

    func dragPointerForTesting(to location: CGPoint) -> Bool {
        dragPointer(to: location)
    }

    func endPointerForTesting(at location: CGPoint) -> Bool {
        endPointer(at: location)
    }

    func scrollForTesting(
        delta: CGSize,
        at location: CGPoint,
        command: Bool = false,
        overScrollableContent: Bool = false,
        ended: Bool = true
    ) -> Bool {
        routeScroll(
            delta: delta,
            at: location,
            command: command,
            overScrollableContent: overScrollableContent,
            ended: ended
        )
    }

    func magnifyForTesting(
        _ magnification: CGFloat,
        at location: CGPoint,
        ended: Bool = true
    ) {
        routeMagnification(
            magnification,
            at: location,
            ended: ended
        )
    }

    private func beginLeftMouse(
        at location: CGPoint,
        clickCount: Int
    ) -> Bool {
        let target = CanvasInteractionHitTester.target(
            at: location,
            snapshot: snapshot
        )
        switch target {
        case let .tabBody(id):
            onSelectTab(id)
            return false
        case let .tabHeader(id):
            guard let node = node(id) else { return false }
            onSelectTab(id)
            operation = Operation(
                kind: .moveTab,
                id: id,
                startPoint: location,
                lastPoint: location,
                originalFrame: node.logicalFrame,
                resizeHandle: nil,
                clickCount: clickCount
            )
            NSCursor.closedHand.set()
            return true
        case let .tabClose(id):
            operation = Operation(
                kind: .closeTab,
                id: id,
                startPoint: location,
                lastPoint: location,
                originalFrame: nil,
                resizeHandle: nil,
                clickCount: clickCount
            )
            return true
        case let .tabLink(id):
            operation = Operation(
                kind: .linkTab,
                id: id,
                startPoint: location,
                lastPoint: location,
                originalFrame: nil,
                resizeHandle: nil,
                clickCount: clickCount
            )
            NSCursor.crosshair.set()
            return true
        case let .tabResize(id, handle):
            guard let node = node(id) else { return false }
            onSelectTab(id)
            operation = Operation(
                kind: .resizeTab,
                id: id,
                startPoint: location,
                lastPoint: location,
                originalFrame: node.logicalFrame,
                resizeHandle: handle,
                clickCount: clickCount
            )
            setResizeCursor(handle)
            return true
        case let .agentHeader(id):
            guard let node = node(id) else { return false }
            operation = Operation(
                kind: .moveAgent,
                id: id,
                startPoint: location,
                lastPoint: location,
                originalFrame: node.logicalFrame,
                resizeHandle: nil,
                clickCount: clickCount
            )
            NSCursor.closedHand.set()
            return true
        case let .agentClose(id):
            operation = Operation(
                kind: .closeAgent,
                id: id,
                startPoint: location,
                lastPoint: location,
                originalFrame: nil,
                resizeHandle: nil,
                clickCount: clickCount
            )
            return true
        case .background:
            onSelectBackground()
            operation = Operation(
                kind: .pan,
                id: nil,
                startPoint: location,
                lastPoint: location,
                originalFrame: nil,
                resizeHandle: nil,
                clickCount: clickCount
            )
            NSCursor.closedHand.set()
            return false
        case .tabControl, .agentBody, .agentControl:
            return false
        }
    }

    private func dragPointer(to location: CGPoint) -> Bool {
        guard var operation else { return false }
        let totalDistance = hypot(
            location.x - operation.startPoint.x,
            location.y - operation.startPoint.y
        )
        if totalDistance >= 4 {
            operation.didDrag = true
        }

        switch operation.kind {
        case .moveTab, .moveAgent:
            guard let id = operation.id, let frame = operation.originalFrame else {
                self.operation = nil
                return false
            }
            let updated = CanvasInteractionHitTester.translatedFrame(
                frame,
                from: operation.startPoint,
                to: location,
                zoom: snapshot.zoom
            )
            onMoveNode(id, updated, false)
            operation.lastPoint = location
            self.operation = operation
            return true
        case .resizeTab:
            guard let id = operation.id,
                  let frame = operation.originalFrame,
                  let handle = operation.resizeHandle else {
                self.operation = nil
                return false
            }
            let updated = CanvasInteractionHitTester.resizedFrame(
                frame,
                from: operation.startPoint,
                to: location,
                zoom: snapshot.zoom,
                handle: handle
            )
            onResizeTab(id, updated, false)
            operation.lastPoint = location
            self.operation = operation
            return true
        case .pan:
            guard operation.didDrag else {
                self.operation = operation
                return false
            }
            onPan(
                CGSize(
                    width: location.x - operation.lastPoint.x,
                    height: location.y - operation.lastPoint.y
                ),
                false
            )
            operation.lastPoint = location
            self.operation = operation
            return true
        case .linkTab:
            guard let id = operation.id else {
                self.operation = nil
                return false
            }
            if operation.didDrag {
                onUpdateLink(
                    id,
                    location,
                    linkTarget(at: location, excluding: id),
                    false
                )
            }
            operation.lastPoint = location
            self.operation = operation
            return true
        case .closeTab, .closeAgent:
            return true
        }
    }

    private func endPointer(at location: CGPoint) -> Bool {
        guard let operation else { return false }
        self.operation = nil
        defer { updateCursor(at: location) }

        switch operation.kind {
        case .moveTab:
            guard let id = operation.id, let frame = operation.originalFrame else {
                return true
            }
            if operation.didDrag {
                let updated = CanvasInteractionHitTester.translatedFrame(
                    frame,
                    from: operation.startPoint,
                    to: location,
                    zoom: snapshot.zoom
                )
                onMoveNode(id, updated, true)
            } else if operation.clickCount >= 2 {
                onRenameTab(id)
            } else {
                onActivateTab(id)
            }
            return true
        case .moveAgent:
            guard let id = operation.id, let frame = operation.originalFrame else {
                return true
            }
            if operation.didDrag {
                let updated = CanvasInteractionHitTester.translatedFrame(
                    frame,
                    from: operation.startPoint,
                    to: location,
                    zoom: snapshot.zoom
                )
                onMoveNode(id, updated, true)
            } else {
                onFocusAgent(id)
            }
            return true
        case .resizeTab:
            guard let id = operation.id,
                  let frame = operation.originalFrame,
                  let handle = operation.resizeHandle else {
                return true
            }
            let updated = CanvasInteractionHitTester.resizedFrame(
                frame,
                from: operation.startPoint,
                to: location,
                zoom: snapshot.zoom,
                handle: handle
            )
            onResizeTab(id, updated, true)
            return true
        case .closeTab:
            if let id = operation.id,
               CanvasInteractionHitTester.target(
                   at: location,
                   snapshot: snapshot
               ) == .tabClose(id) {
                onCloseTab(id)
            }
            return true
        case .closeAgent:
            if let id = operation.id,
               CanvasInteractionHitTester.target(
                   at: location,
                   snapshot: snapshot
               ) == .agentClose(id) {
                onCloseAgent(id)
            }
            return true
        case .linkTab:
            guard let id = operation.id else { return true }
            let targetID = linkTarget(at: location, excluding: id)
            if operation.didDrag, let targetID {
                onCreateLink(id, targetID)
            }
            onUpdateLink(id, location, targetID, true)
            return true
        case .pan:
            if operation.didDrag {
                onPan(.zero, true)
                return true
            }
            return false
        }
    }

    private func handleScroll(
        _ event: NSEvent,
        at location: CGPoint
    ) -> NSEvent? {
        let consumed = routeScroll(
            delta: CGSize(
                width: event.scrollingDeltaX,
                height: event.scrollingDeltaY
            ),
            at: location,
            command: event.modifierFlags.contains(.command),
            overScrollableContent: isOverScrollableContent(event),
            ended: Self.isGestureEnded(event)
        )
        return consumed ? nil : event
    }

    @discardableResult
    private func routeScroll(
        delta: CGSize,
        at location: CGPoint,
        command: Bool,
        overScrollableContent: Bool,
        ended: Bool
    ) -> Bool {
        if command {
            onZoom(-delta.height * 0.01, location, ended)
            return true
        }
        guard !overScrollableContent else { return false }
        onPan(delta, ended)
        return true
    }

    private func routeMagnification(
        _ magnification: CGFloat,
        at location: CGPoint,
        ended: Bool
    ) {
        onZoom(magnification, location, ended)
    }

    private func isOverScrollableContent(_ event: NSEvent) -> Bool {
        guard let window, let contentView = window.contentView else { return false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        var candidate = contentView.hitTest(point)
        while let view = candidate {
            if view is RibbitGhosttyView || view is NSTextView {
                return true
            }
            candidate = view.superview
        }
        return false
    }

    private func node(_ id: UUID) -> CanvasInteractionNode? {
        snapshot.nodesFrontToBack.first { $0.id == id }
    }

    private func linkTarget(
        at location: CGPoint,
        excluding sourceID: UUID
    ) -> UUID? {
        snapshot.nodesFrontToBack.first {
            $0.kind == .tab
                && $0.id != sourceID
                && $0.viewportRect.contains(location)
        }?.id
    }

    @discardableResult
    func updateCursor(at location: CGPoint) -> Bool {
        if let operation {
            switch operation.kind {
            case .moveTab, .moveAgent, .pan:
                NSCursor.closedHand.set()
                return true
            case .resizeTab:
                setResizeCursor(operation.resizeHandle)
                return true
            case .linkTab:
                NSCursor.crosshair.set()
                return true
            case .closeTab, .closeAgent:
                NSCursor.arrow.set()
                return false
            }
        }
        switch CanvasInteractionHitTester.target(
            at: location,
            snapshot: snapshot
        ) {
        case .tabHeader, .agentHeader, .background:
            NSCursor.openHand.set()
            return true
        case .tabLink:
            NSCursor.crosshair.set()
            return true
        case let .tabResize(_, handle):
            setResizeCursor(handle)
            return true
        default:
            NSCursor.arrow.set()
            return false
        }
    }

    private func setResizeCursor(_ handle: CanvasResizeHandle?) {
        switch handle {
        case .left, .right:
            NSCursor.resizeLeftRight.set()
        case .top, .bottom:
            NSCursor.resizeUpDown.set()
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            NSCursor.crosshair.set()
        case nil:
            NSCursor.arrow.set()
        }
    }

    private static func isGestureEnded(_ event: NSEvent) -> Bool {
        event.phase == .ended
            || event.phase == .cancelled
            || event.momentumPhase == .ended
            || (event.phase.isEmpty && event.momentumPhase.isEmpty)
    }
}
