import AppKit
import Foundation
import Testing
@testable import Ribbit

@Suite(.serialized)
@MainActor
struct RibbitTests {
    @Test func onlyExplicitTopChromeMovesTheWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        RibbitWindowConfigurator.configure(window)
        let dragRegion = RibbitWindowDragView()

        #expect(window.identifier == RibbitWindowConfigurator.mainWindowIdentifier)
        #expect(!window.isMovableByWindowBackground)
        #expect(!window.isReleasedWhenClosed)
        #expect(dragRegion.mouseDownCanMoveWindow)
        #expect(dragRegion.acceptsFirstMouse(for: nil))
    }

    @Test func mainWindowConfigurationNeverMutatesTheNotchPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 38),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let originalIdentifier = NSUserInterfaceItemIdentifier("agent-notch")
        panel.identifier = originalIdentifier
        panel.isMovableByWindowBackground = true

        RibbitWindowConfigurator.configure(panel)

        #expect(panel.identifier == originalIdentifier)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.styleMask.contains(.resizable))
        #expect(panel.isMovableByWindowBackground)
    }

    @Test func ghosttyTerminalAcceptsTheActivationClick() {
        let view = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in false },
            sendKey: { _, _ in true },
            sendBindingAction: { _ in true }
        ))

        #expect(view.acceptsFirstMouse(for: nil))
    }

    @Test func clickingGhosttyMovesTheTextCursorToThatTerminal() throws {
        var activationCount = 0
        let view = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in false },
            sendKey: { _, _ in true },
            sendBindingAction: { _ in true }
        ))
        view.onActivated = {
            activationCount += 1
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 20, y: 20),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        view.mouseDown(with: event)

        #expect(window.firstResponder === view)
        #expect(activationCount == 1)
    }

    @Test func canvasPinchZoomKeepsThePointUnderTheTrackpadStationary() {
        let anchor = CGPoint(x: 400, y: 300)
        let originalPan = CGSize(width: 100, height: 50)
        let result = CanvasInteractionMath.zoom(
            currentZoom: 1,
            pan: originalPan,
            magnification: 0.25,
            anchor: anchor
        )

        #expect(result.zoom == 1.25)
        let originalCanvasPoint = CGPoint(
            x: (anchor.x - originalPan.width),
            y: (anchor.y - originalPan.height)
        )
        let transformedPoint = CGPoint(
            x: originalCanvasPoint.x * result.zoom + result.pan.width,
            y: originalCanvasPoint.y * result.zoom + result.pan.height
        )
        #expect(abs(transformedPoint.x - anchor.x) < 0.001)
        #expect(abs(transformedPoint.y - anchor.y) < 0.001)
    }

    @Test func canvasViewportUsesExplicitGeometryForMixedAppKitContent() {
        let logical = CanvasNodeFrame(
            x: 120,
            y: 80,
            width: 620,
            height: 390
        )
        let viewport = CanvasInteractionMath.viewportFrame(
            logical,
            pan: CGSize(width: -40, height: 30),
            zoom: 0.75
        )

        #expect(viewport == CanvasNodeFrame(
            x: 50,
            y: 90,
            width: 465,
            height: 292.5
        ))
    }

    @Test func canvasFitCentersEveryNodeWithEvenOuterSpace() throws {
        let camera = try #require(CanvasInteractionMath.fittedCamera(
            around: [
                CanvasNodeFrame(x: 100, y: 50, width: 400, height: 300),
                CanvasNodeFrame(x: 600, y: 250, width: 200, height: 200),
            ],
            in: CGSize(width: 1000, height: 700)
        ))

        #expect(camera.zoom == 1)
        #expect(camera.x == 50)
        #expect(camera.y == 100)

        let overview = try #require(CanvasInteractionMath.fittedCamera(
            around: [
                CanvasNodeFrame(x: 0, y: 0, width: 4_000, height: 2_000),
            ],
            in: CGSize(width: 1_000, height: 700)
        ))
        #expect(abs(
            overview.zoom - CanvasInteractionMetrics.minimumZoom
        ) < 0.001)
    }

    @Test func canvasConnectionsUseTheClosestAxisAndAimAtTheTarget() {
        let horizontal = CanvasConnectionGeometry(
            source: CanvasNodeFrame(x: 0, y: 0, width: 200, height: 100),
            target: CanvasNodeFrame(x: 400, y: 40, width: 200, height: 100)
        )
        #expect(horizontal.start == CGPoint(x: 200, y: 50))
        #expect(horizontal.end == CGPoint(x: 400, y: 90))
        #expect(horizontal.arrowTip == horizontal.end)
        #expect(horizontal.arrowLeft.x < horizontal.end.x)
        #expect(horizontal.arrowRight.x < horizontal.end.x)

        let vertical = CanvasConnectionGeometry(
            source: CanvasNodeFrame(x: 0, y: 0, width: 200, height: 100),
            target: CanvasNodeFrame(x: 20, y: 400, width: 200, height: 100)
        )
        #expect(vertical.start == CGPoint(x: 100, y: 100))
        #expect(vertical.end == CGPoint(x: 120, y: 400))
        #expect(vertical.arrowLeft.y < vertical.end.y)
        #expect(vertical.arrowRight.y < vertical.end.y)

        let parallel = CanvasConnectionGeometry(
            source: CanvasNodeFrame(x: 0, y: 0, width: 200, height: 100),
            target: CanvasNodeFrame(x: 400, y: 40, width: 200, height: 100),
            laneOffset: 10
        )
        #expect(parallel.start.y == horizontal.start.y + 10)
        #expect(parallel.end.y == horizontal.end.y + 10)
    }

    @Test func trackpadMonitorNeverBecomesTheMouseHitTarget() {
        let monitor = CanvasInteractionMonitorView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 700)
        )

        #expect(monitor.hitTest(NSPoint(x: 450, y: 350)) == nil)
    }

    @Test func customCanvasCursorsStopBeforeUnderlyingViewsResetThem() {
        let tabID = UUID()
        let frame = CanvasNodeFrame(
            x: 40,
            y: 40,
            width: 620,
            height: 390
        )
        let monitor = CanvasInteractionMonitorView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 700)
        )
        monitor.snapshot = CanvasInteractionSnapshot(
            zoom: 1,
            nodesFrontToBack: [
                CanvasInteractionNode(
                    id: tabID,
                    kind: .tab,
                    logicalFrame: frame,
                    viewportFrame: frame,
                    hasAgentStatus: false
                )
            ]
        )

        #expect(monitor.updateCursor(
            at: CGPoint(x: 100, y: 55)
        ))
        #expect(monitor.updateCursor(
            at: CGPoint(x: 800, y: 600)
        ))
        #expect(!monitor.updateCursor(
            at: CGPoint(x: 300, y: 180)
        ))
    }

    @Test func canvasHitTestingSeparatesNodeChromeFromTerminalContent() {
        let tabID = UUID()
        let pinID = UUID()
        let snapshot = CanvasInteractionSnapshot(
            zoom: 1,
            nodesFrontToBack: [
                CanvasInteractionNode(
                    id: pinID,
                    kind: .agentPin,
                    logicalFrame: CanvasNodeFrame(
                        x: 360,
                        y: 480,
                        width: 280,
                        height: 170
                    ),
                    viewportFrame: CanvasNodeFrame(
                        x: 360,
                        y: 480,
                        width: 280,
                        height: 170
                    ),
                    hasAgentStatus: true
                ),
                CanvasInteractionNode(
                    id: tabID,
                    kind: .tab,
                    logicalFrame: CanvasNodeFrame(
                        x: 40,
                        y: 40,
                        width: 620,
                        height: 390
                    ),
                    viewportFrame: CanvasNodeFrame(
                        x: 40,
                        y: 40,
                        width: 620,
                        height: 390
                    ),
                    hasAgentStatus: false
                )
            ]
        )

        #expect(CanvasInteractionHitTester.target(
            at: CGPoint(x: 100, y: 55),
            snapshot: snapshot
        ) == .tabHeader(tabID))
        #expect(CanvasInteractionHitTester.target(
            at: CGPoint(x: 645, y: 55),
            snapshot: snapshot
        ) == .tabClose(tabID))
        #expect(CanvasInteractionHitTester.target(
            at: CGPoint(x: 658, y: 42),
            snapshot: snapshot
        ) == .tabResize(tabID, .topRight))
        #expect(CanvasInteractionHitTester.target(
            at: CGPoint(x: 645, y: 80),
            snapshot: snapshot
        ) == .tabClose(tabID))
        #expect(CanvasInteractionHitTester.target(
            at: CGPoint(x: 600, y: 55),
            snapshot: snapshot
        ) == .tabControl(tabID))
        #expect(CanvasInteractionHitTester.target(
            at: CGPoint(x: 585, y: 55),
            snapshot: snapshot
        ) == .tabLink(tabID))
        #expect(CanvasInteractionHitTester.target(
            at: CGPoint(x: 300, y: 180),
            snapshot: snapshot
        ) == .tabBody(tabID))
        #expect(CanvasInteractionHitTester.target(
            at: CGPoint(x: 645, y: 415),
            snapshot: snapshot
        ) == .tabResize(tabID, .bottomRight))
        #expect(CanvasInteractionHitTester.target(
            at: CGPoint(x: 625, y: 495),
            snapshot: snapshot
        ) == .agentClose(pinID))
        #expect(CanvasInteractionHitTester.target(
            at: CGPoint(x: 700, y: 450),
            snapshot: snapshot
        ) == .background)

        let resizeTargets: [(CGPoint, CanvasResizeHandle)] = [
            (CGPoint(x: 42, y: 42), .topLeft),
            (CGPoint(x: 300, y: 42), .top),
            (CGPoint(x: 658, y: 42), .topRight),
            (CGPoint(x: 658, y: 200), .right),
            (CGPoint(x: 658, y: 428), .bottomRight),
            (CGPoint(x: 300, y: 428), .bottom),
            (CGPoint(x: 42, y: 428), .bottomLeft),
            (CGPoint(x: 42, y: 200), .left)
        ]
        for (point, handle) in resizeTargets {
            #expect(CanvasInteractionHitTester.target(
                at: point,
                snapshot: snapshot
            ) == .tabResize(tabID, handle))
        }
    }

    @Test func nativeCanvasMonitorRoutesCloseAndDragWithoutSwiftUIGestures() {
        let tabID = UUID()
        let logicalFrame = CanvasNodeFrame(
            x: 40,
            y: 40,
            width: 620,
            height: 390
        )
        let monitor = CanvasInteractionMonitorView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 700)
        )
        monitor.snapshot = CanvasInteractionSnapshot(
            zoom: 1,
            nodesFrontToBack: [
                CanvasInteractionNode(
                    id: tabID,
                    kind: .tab,
                    logicalFrame: logicalFrame,
                    viewportFrame: logicalFrame,
                    hasAgentStatus: false
                )
            ]
        )
        var closedID: UUID?
        var movedFrame: CanvasNodeFrame?
        var moveEnded = false
        monitor.onCloseTab = { closedID = $0 }
        monitor.onMoveNode = { _, frame, ended in
            movedFrame = frame
            moveEnded = ended
        }
        let closePoint = NSPoint(x: 645, y: 55)
        #expect(monitor.beginLeftMouseForTesting(at: closePoint))
        #expect(monitor.endPointerForTesting(at: closePoint))
        #expect(closedID == tabID)

        let dragStart = NSPoint(x: 100, y: 55)
        let dragEnd = NSPoint(x: 180, y: 115)
        #expect(monitor.beginLeftMouseForTesting(at: dragStart))
        #expect(monitor.dragPointerForTesting(to: dragEnd))
        #expect(monitor.endPointerForTesting(at: dragEnd))

        #expect(movedFrame == CanvasNodeFrame(
            x: 120,
            y: 100,
            width: 620,
            height: 390
        ))
        #expect(moveEnded)
    }

    @Test func canvasMonitorRoutesSelectionResizePanAndAgentUnpin() {
        let tabID = UUID()
        let pinID = UUID()
        let tabFrame = CanvasNodeFrame(
            x: 40,
            y: 40,
            width: 620,
            height: 390
        )
        let pinFrame = CanvasNodeFrame(
            x: 420,
            y: 480,
            width: 300,
            height: 170
        )
        let monitor = CanvasInteractionMonitorView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 700)
        )
        monitor.snapshot = CanvasInteractionSnapshot(
            zoom: 1,
            nodesFrontToBack: [
                CanvasInteractionNode(
                    id: pinID,
                    kind: .agentPin,
                    logicalFrame: pinFrame,
                    viewportFrame: pinFrame,
                    hasAgentStatus: true
                ),
                CanvasInteractionNode(
                    id: tabID,
                    kind: .tab,
                    logicalFrame: tabFrame,
                    viewportFrame: tabFrame,
                    hasAgentStatus: false
                )
            ]
        )
        var selectedID: UUID?
        var resizedFrame: CanvasNodeFrame?
        var resizeEnded = false
        var panDeltas: [CGSize] = []
        var panEnded = false
        var selectedBackground = false
        var unpinnedID: UUID?
        monitor.onSelectTab = { selectedID = $0 }
        monitor.onResizeTab = { _, frame, ended in
            resizedFrame = frame
            resizeEnded = ended
        }
        monitor.onPan = { delta, ended in
            panDeltas.append(delta)
            panEnded = ended
        }
        monitor.onSelectBackground = { selectedBackground = true }
        monitor.onCloseAgent = { unpinnedID = $0 }

        #expect(!monitor.beginLeftMouseForTesting(
            at: CGPoint(x: 200, y: 180)
        ))
        #expect(selectedID == tabID)

        let resizeStart = CGPoint(x: 645, y: 415)
        let resizeEnd = CGPoint(x: 705, y: 455)
        #expect(monitor.beginLeftMouseForTesting(at: resizeStart))
        #expect(monitor.dragPointerForTesting(to: resizeEnd))
        #expect(monitor.endPointerForTesting(at: resizeEnd))
        #expect(resizedFrame == CanvasNodeFrame(
            x: 40,
            y: 40,
            width: 680,
            height: 430
        ))
        #expect(resizeEnded)

        let panStart = CGPoint(x: 800, y: 600)
        let panEnd = CGPoint(x: 850, y: 625)
        #expect(!monitor.beginLeftMouseForTesting(at: panStart))
        #expect(selectedBackground)
        #expect(monitor.dragPointerForTesting(to: panEnd))
        #expect(monitor.endPointerForTesting(at: panEnd))
        #expect(panDeltas.first == CGSize(width: 50, height: 25))
        #expect(panEnded)

        let pinClose = CGPoint(x: 705, y: 495)
        #expect(monitor.beginLeftMouseForTesting(at: pinClose))
        #expect(monitor.endPointerForTesting(at: pinClose))
        #expect(unpinnedID == pinID)
    }

    @Test func canvasLinkDragPreviewsAndCreatesTheDirectedEdge() {
        let sourceID = UUID()
        let targetID = UUID()
        let sourceFrame = CanvasNodeFrame(
            x: 40,
            y: 40,
            width: 620,
            height: 390
        )
        let targetFrame = CanvasNodeFrame(
            x: 720,
            y: 120,
            width: 440,
            height: 320
        )
        let monitor = CanvasInteractionMonitorView(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 700)
        )
        monitor.snapshot = CanvasInteractionSnapshot(
            zoom: 1,
            nodesFrontToBack: [
                CanvasInteractionNode(
                    id: targetID,
                    kind: .tab,
                    logicalFrame: targetFrame,
                    viewportFrame: targetFrame,
                    hasAgentStatus: false
                ),
                CanvasInteractionNode(
                    id: sourceID,
                    kind: .tab,
                    logicalFrame: sourceFrame,
                    viewportFrame: sourceFrame,
                    hasAgentStatus: false
                ),
            ]
        )
        var previewTargetID: UUID?
        var createdEdge: (UUID, UUID)?
        var previewEnded = false
        monitor.onUpdateLink = { _, _, targetID, ended in
            previewTargetID = targetID
            previewEnded = ended
        }
        monitor.onCreateLink = { createdEdge = ($0, $1) }

        #expect(monitor.beginLeftMouseForTesting(
            at: CGPoint(x: 585, y: 55)
        ))
        #expect(monitor.dragPointerForTesting(
            to: CGPoint(x: 800, y: 200)
        ))
        #expect(previewTargetID == targetID)
        #expect(monitor.endPointerForTesting(
            at: CGPoint(x: 800, y: 200)
        ))
        #expect(createdEdge?.0 == sourceID)
        #expect(createdEdge?.1 == targetID)
        #expect(previewEnded)
    }

    @Test func everyCanvasEdgeAndCornerResizesFromItsAnchoredOppositeSide() {
        let frame = CanvasNodeFrame(
            x: 100,
            y: 80,
            width: 600,
            height: 400
        )

        let left = CanvasInteractionHitTester.resizedFrame(
            frame,
            from: CGPoint(x: 100, y: 200),
            to: CGPoint(x: 180, y: 200),
            zoom: 2,
            handle: .left
        )
        #expect(left == CanvasNodeFrame(
            x: 140,
            y: 80,
            width: 560,
            height: 400
        ))

        let topLeft = CanvasInteractionHitTester.resizedFrame(
            frame,
            from: CGPoint(x: 100, y: 80),
            to: CGPoint(x: 40, y: 20),
            zoom: 2,
            handle: .topLeft
        )
        #expect(topLeft == CanvasNodeFrame(
            x: 70,
            y: 50,
            width: 630,
            height: 430
        ))

        let bottomRight = CanvasInteractionHitTester.resizedFrame(
            frame,
            from: CGPoint(x: 700, y: 480),
            to: CGPoint(x: 820, y: 560),
            zoom: 2,
            handle: .bottomRight
        )
        #expect(bottomRight == CanvasNodeFrame(
            x: 100,
            y: 80,
            width: 660,
            height: 440
        ))

        let clampedTop = CanvasInteractionHitTester.resizedFrame(
            CanvasNodeFrame(x: 100, y: 80, width: 300, height: 220),
            from: CGPoint(x: 200, y: 80),
            to: CGPoint(x: 200, y: 240),
            zoom: 1,
            handle: .top
        )
        #expect(clampedTop == CanvasNodeFrame(
            x: 100,
            y: 80,
            width: 300,
            height: 220
        ))
    }

    @Test func trackpadScrollPinchAndCommandWheelReachCanvasCallbacks() {
        let monitor = CanvasInteractionMonitorView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 700)
        )
        var panEvents: [(CGSize, Bool)] = []
        var zoomEvents: [(CGFloat, CGPoint, Bool)] = []
        monitor.onPan = { panEvents.append(($0, $1)) }
        monitor.onZoom = { zoomEvents.append(($0, $1, $2)) }

        #expect(monitor.scrollForTesting(
            delta: CGSize(width: -18, height: 26),
            at: CGPoint(x: 300, y: 250),
            ended: false
        ))
        #expect(panEvents.count == 1)
        #expect(panEvents[0].0 == CGSize(width: -18, height: 26))
        #expect(!panEvents[0].1)

        #expect(!monitor.scrollForTesting(
            delta: CGSize(width: 0, height: -12),
            at: CGPoint(x: 300, y: 250),
            overScrollableContent: true
        ))
        #expect(panEvents.count == 1)

        #expect(monitor.scrollForTesting(
            delta: CGSize(width: 0, height: -9),
            at: CGPoint(x: 300, y: 250),
            command: true
        ))
        #expect(zoomEvents[0].0 == 0.09)
        #expect(zoomEvents[0].1 == CGPoint(x: 300, y: 250))
        #expect(zoomEvents[0].2)

        monitor.magnifyForTesting(
            0.14,
            at: CGPoint(x: 520, y: 340),
            ended: false
        )
        #expect(zoomEvents[1].0 == 0.14)
        #expect(zoomEvents[1].1 == CGPoint(x: 520, y: 340))
        #expect(!zoomEvents[1].2)
    }

    @Test func canvasZoomScalesTerminalAndEditorTypography() {
        #expect(CanvasInteractionMetrics.terminalFontSize(
            base: 14,
            zoom: 0.5
        ) == 8)
        #expect(CanvasInteractionMetrics.terminalFontSize(
            base: 14,
            zoom: 1
        ) == 14)
        #expect(CanvasInteractionMetrics.terminalFontSize(
            base: 14,
            zoom: 1.5
        ) == 21)
        #expect(CanvasInteractionMetrics.editorFontSize(
            base: 16,
            zoom: 1.25
        ) == 20)
        #expect(CanvasInteractionMetrics.terminalSurfaceFontScale(
            canvasZoom: 0.5
        ) == 1)
        #expect(CanvasInteractionMetrics.terminalSurfaceFontScale(
            canvasZoom: 1.5
        ) == 1)

        let terminal = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in false },
            sendKey: { _, _ in true },
            sendBindingAction: { _ in true }
        ))
        terminal.updateAppearance(fontSize: 21)
        #expect(terminal.font.pointSize == 21)
    }

    @Test func canvasUpdatesCannotStealFocusForInactiveTerminals() {
        #expect(!TerminalFocusPolicy.shouldFocus(
            wasActive: false,
            isActive: false,
            appIsActive: true
        ))
        #expect(!TerminalFocusPolicy.shouldFocus(
            wasActive: true,
            isActive: true,
            appIsActive: true
        ))
        #expect(!TerminalFocusPolicy.shouldFocus(
            wasActive: false,
            isActive: true,
            appIsActive: false
        ))
        #expect(TerminalFocusPolicy.shouldFocus(
            wasActive: false,
            isActive: true,
            appIsActive: true
        ))
    }

    @Test func agentTerminalReturnKeysUseCompatibleFallbacks() {
        #expect(AgentTerminalInput.fallbackReturnSequence(
            keyCode: 36,
            modifiers: .shift,
            enhancedKeyboardEnabled: false
        ) == [0x0a])
        #expect(AgentTerminalInput.fallbackReturnSequence(
            keyCode: 36,
            modifiers: .option,
            enhancedKeyboardEnabled: false
        ) == [0x1b, 0x0d])
        #expect(AgentTerminalInput.fallbackReturnSequence(
            keyCode: 36,
            modifiers: .shift,
            enhancedKeyboardEnabled: true
        ) == nil)
        #expect(AgentTerminalInput.fallbackReturnSequence(
            keyCode: 36,
            modifiers: [],
            enhancedKeyboardEnabled: false
        ) == nil)
        #expect(AgentTerminalInput.fallbackReturnBindingAction(
            keyCode: 36,
            modifiers: .shift,
            enhancedKeyboardEnabled: false
        ) == "text:\\x0a")
        #expect(AgentTerminalInput.fallbackReturnBindingAction(
            keyCode: 36,
            modifiers: .option,
            enhancedKeyboardEnabled: false
        ) == "text:\\x1b\\x0d")
    }

    @Test func allAppKitMouseButtonsMapToDistinctGhosttyButtons() {
        let mapped = (0...10).compactMap {
            RibbitMouseButton(appKitButtonNumber: $0)
        }
        #expect(mapped == RibbitMouseButton.allCases)
        #expect(Set(mapped.map(\.ghosttyValue)).count == 11)
        #expect(RibbitMouseButton(appKitButtonNumber: 11) == nil)
    }

    @Test func ghosttyBindingWinsForUnreservedCommandShortcut() throws {
        var sentKeys: [TerminalInputTestHarness.KeyAction] = []
        var bindingActions: [String] = []
        let view = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in true },
            sendKey: { _, action in
                sentKeys.append(action)
                return true
            },
            sendBindingAction: {
                bindingActions.append($0)
                return true
            }
        ))
        let event = try #require(Self.keyEvent(
            characters: "x",
            modifiers: .command,
            keyCode: 7
        ))

        #expect(view.performKeyEquivalent(with: event))
        #expect(sentKeys == [.press])
        #expect(bindingActions.isEmpty)
    }

    @Test func documentedRibbitShortcutWinsOverGhosttyDefaultBinding() throws {
        var sentKeys: [TerminalInputTestHarness.KeyAction] = []
        let view = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in true },
            sendKey: { _, action in
                sentKeys.append(action)
                return true
            },
            sendBindingAction: { _ in true }
        ))
        let event = try #require(Self.keyEvent(
            characters: "n",
            modifiers: .command,
            keyCode: 45
        ))

        #expect(!view.performKeyEquivalent(with: event))
        #expect(sentKeys.isEmpty)
    }

    @Test func unclaimedCommandShortcutContinuesToRibbitMenu() throws {
        var sentKeys: [TerminalInputTestHarness.KeyAction] = []
        let view = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in false },
            sendKey: { _, action in
                sentKeys.append(action)
                return true
            },
            sendBindingAction: { _ in true }
        ))
        let event = try #require(Self.keyEvent(
            characters: "t",
            modifiers: .command,
            keyCode: 17
        ))

        #expect(!view.performKeyEquivalent(with: event))
        #expect(sentKeys.isEmpty)
    }

    @Test func modifiedReturnFallbackRunsThroughLiveViewExactlyOnce() throws {
        var sentKeys: [TerminalInputTestHarness.KeyAction] = []
        var bindingActions: [String] = []
        var sentBytes: [[UInt8]] = []
        let view = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in false },
            sendKey: { _, action in
                sentKeys.append(action)
                return true
            },
            sendBindingAction: {
                bindingActions.append($0)
                return true
            },
            observeBytes: { sentBytes.append($0) }
        ))
        let press = try #require(Self.keyEvent(
            characters: "\r",
            modifiers: .shift,
            keyCode: 36
        ))
        let release = try #require(Self.keyEvent(
            type: .keyUp,
            characters: "\r",
            modifiers: .shift,
            keyCode: 36
        ))

        view.keyDown(with: press)
        view.keyUp(with: release)

        #expect(sentBytes == [[0x0a]])
        #expect(bindingActions.isEmpty)
        #expect(sentKeys.isEmpty)
    }

    @Test func optionReturnFallbackUsesEscapeReturnThroughLiveView() throws {
        var sentKeys: [TerminalInputTestHarness.KeyAction] = []
        var bindingActions: [String] = []
        var sentBytes: [[UInt8]] = []
        let view = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in false },
            sendKey: { _, action in
                sentKeys.append(action)
                return true
            },
            sendBindingAction: {
                bindingActions.append($0)
                return true
            },
            observeBytes: { sentBytes.append($0) }
        ))
        let event = try #require(Self.keyEvent(
            characters: "\r",
            modifiers: .option,
            keyCode: 36
        ))

        view.keyDown(with: event)

        #expect(sentBytes == [[0x1b, 0x0d]])
        #expect(bindingActions.isEmpty)
        #expect(sentKeys.isEmpty)
    }

    @Test func enhancedInputUsesNativeGhosttyEventInsteadOfFallback() throws {
        var sentKeys: [TerminalInputTestHarness.KeyAction] = []
        let view = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in false },
            sendKey: { _, action in
                sentKeys.append(action)
                return true
            },
            sendBindingAction: { _ in false }
        ))
        view.enhancedKeyboardInputEnabled = true
        let event = try #require(Self.keyEvent(
            characters: "\r",
            modifiers: .shift,
            keyCode: 36
        ))

        view.keyDown(with: event)

        #expect(sentKeys == [.press])
    }

    @Test func ordinaryAndUnsupportedReturnChordsStayOnNativeGhosttyPath() throws {
        var sentKeys: [TerminalInputTestHarness.KeyAction] = []
        var sentBytes: [[UInt8]] = []
        let view = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in false },
            sendKey: { _, action in
                sentKeys.append(action)
                return true
            },
            sendBindingAction: { _ in true },
            observeBytes: { sentBytes.append($0) }
        ))
        let cases: [(String, NSEvent.ModifierFlags, UInt16)] = [
            ("\r", [], 36),
            ("\r", [], 76),
            ("\r", .control, 36),
            ("\r", [.shift, .option], 36),
            ("\r", .shift, 76)
        ]

        for (characters, modifiers, keyCode) in cases {
            view.keyDown(with: try #require(Self.keyEvent(
                characters: characters,
                modifiers: modifiers,
                keyCode: keyCode
            )))
        }

        #expect(sentKeys == Array(repeating: .press, count: 4))
        #expect(sentBytes == [[0x0a]])
    }

    @Test func modifiedReturnRepeatAndReleaseNeverDoubleSend() throws {
        var sentKeys: [TerminalInputTestHarness.KeyAction] = []
        var sentBytes: [[UInt8]] = []
        let view = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in false },
            sendKey: { _, action in
                sentKeys.append(action)
                return true
            },
            sendBindingAction: { _ in true },
            observeBytes: { sentBytes.append($0) }
        ))
        let press = try #require(Self.keyEvent(
            characters: "\r",
            modifiers: .shift,
            keyCode: 36
        ))
        let repeatEvent = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .shift,
            timestamp: 2,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: true,
            keyCode: 36
        ))
        let release = try #require(Self.keyEvent(
            type: .keyUp,
            characters: "\r",
            modifiers: .shift,
            keyCode: 36
        ))

        view.keyDown(with: press)
        view.keyDown(with: repeatEvent)
        view.keyUp(with: release)

        #expect(sentBytes == [[0x0a], [0x0a]])
        #expect(sentKeys.isEmpty)
    }

    @Test func commandShortcutMatrixHasOneDeterministicOwner() throws {
        let terminalChords: [(String, UInt16)] = [
            ("c", 8), ("v", 9), ("x", 7)
        ]
        let ribbitChords: [(String, UInt16)] = [
            ("f", 3), ("w", 13), ("t", 17), ("n", 45), ("o", 31), ("s", 1),
            ("k", 40), ("0", 29), ("1", 18), ("5", 23), ("9", 25),
            ("-", 27), ("=", 24)
        ]
        var terminalOwnedKeys: [TerminalInputTestHarness.KeyAction] = []
        let terminalOwnedView = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in true },
            sendKey: { _, action in
                terminalOwnedKeys.append(action)
                return true
            },
            sendBindingAction: { _ in true }
        ))
        var appOwnedKeys: [TerminalInputTestHarness.KeyAction] = []
        let appOwnedView = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in false },
            sendKey: { _, action in
                appOwnedKeys.append(action)
                return true
            },
            sendBindingAction: { _ in true }
        ))

        for (characters, keyCode) in terminalChords {
            let event = try #require(Self.keyEvent(
                characters: characters,
                modifiers: .command,
                keyCode: keyCode
            ))
            #expect(terminalOwnedView.performKeyEquivalent(with: event))
            #expect(!appOwnedView.performKeyEquivalent(with: event))
        }

        for (characters, keyCode) in ribbitChords {
            let event = try #require(Self.keyEvent(
                characters: characters,
                modifiers: .command,
                keyCode: keyCode
            ))
            #expect(!terminalOwnedView.performKeyEquivalent(with: event))
            #expect(!appOwnedView.performKeyEquivalent(with: event))
        }

        #expect(terminalOwnedKeys == Array(
            repeating: .press,
            count: terminalChords.count
        ))
        #expect(appOwnedKeys.isEmpty)

        for (characters, keyCode) in [("[", UInt16(33)), ("]", UInt16(30))] {
            let event = try #require(Self.keyEvent(
                characters: characters,
                modifiers: [.command, .shift],
                keyCode: keyCode
            ))
            #expect(!terminalOwnedView.performKeyEquivalent(with: event))
            #expect(!appOwnedView.performKeyEquivalent(with: event))
        }
    }

    @Test func modifierChangesReachTheLiveViewTransport() throws {
        var sentKeys: [TerminalInputTestHarness.KeyAction] = []
        let view = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in false },
            sendKey: { _, action in
                sentKeys.append(action)
                return true
            },
            sendBindingAction: { _ in true }
        ))
        let press = try #require(Self.keyEvent(
            type: .flagsChanged,
            characters: "",
            modifiers: .shift,
            keyCode: 0x38
        ))
        let release = try #require(Self.keyEvent(
            type: .flagsChanged,
            characters: "",
            modifiers: [],
            keyCode: 0x38
        ))

        view.flagsChanged(with: press)
        view.flagsChanged(with: release)

        #expect(sentKeys == [.press, .release])
    }

    @Test func markedTextLifecycleSupportsImeComposition() {
        let view = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in false },
            sendKey: { _, _ in true },
            sendBindingAction: { _ in true }
        ))

        view.setMarkedText(
            "かな",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        #expect(view.hasMarkedText())
        #expect(view.markedRange() == NSRange(location: 0, length: 2))
        view.unmarkText()
        #expect(!view.hasMarkedText())
        #expect(view.markedRange().location == NSNotFound)
    }

    @Test func appKitTextInterpretationReachesGhosttyOnce() throws {
        var actions: [TerminalInputTestHarness.KeyAction] = []
        var details: [(String?, Bool)] = []
        let view = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in false },
            sendKey: { _, action in
                actions.append(action)
                return true
            },
            sendBindingAction: { _ in true },
            observeKeyDetails: { text, composing in
                details.append((text, composing))
            }
        ))
        let event = try #require(Self.keyEvent(
            characters: "é",
            modifiers: [],
            keyCode: 14
        ))

        view.keyDown(with: event)

        #expect(actions == [.press])
        #expect(details.count == 1)
        #expect(details.first?.0 == "é")
        #expect(details.first?.1 == false)
    }

    @Test func editingAndNavigationKeysAreNeverSwallowedByAppKit() throws {
        var actions: [TerminalInputTestHarness.KeyAction] = []
        let view = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in false },
            sendKey: { _, action in
                actions.append(action)
                return true
            },
            sendBindingAction: { _ in true }
        ))
        let cases: [(String, NSEvent.ModifierFlags, UInt16)] = [
            ("\u{f702}", [], 123),
            ("\u{f703}", [], 124),
            ("\u{f700}", [], 126),
            ("\u{f701}", [], 125),
            ("\u{f702}", .option, 123),
            ("\t", [], 48),
            ("\t", .shift, 48),
            ("\u{7f}", [], 51)
        ]

        for (characters, modifiers, keyCode) in cases {
            let event = try #require(Self.keyEvent(
                characters: characters,
                modifiers: modifiers,
                keyCode: keyCode
            ))
            view.keyDown(with: event)
        }

        #expect(actions == Array(repeating: .press, count: cases.count))
    }

    @Test func tmuxDiscoveryUsesPathWithoutAssumingHomebrew() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-tmux-discovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("tmux", isDirectory: false)
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let installation = TmuxInstallation.discover(
            environment: ["PATH": root.path],
            standardCandidates: []
        )

        #expect(installation?.executableURL.standardizedFileURL == executable.standardizedFileURL)
    }

    @Test func packagedGhosttyTerminfoIsDiscoveredForTmuxClients() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-terminfo-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = root
            .appendingPathComponent("Vendor/GhosttyResources/terminfo", isDirectory: true)
        let entry = expected
            .appendingPathComponent("78", isDirectory: true)
            .appendingPathComponent("xterm-ghostty", isDirectory: false)
        try FileManager.default.createDirectory(
            at: entry.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: entry)
        let source = root
            .appendingPathComponent("Sources/Ribbit/GhosttyResources.swift", isDirectory: false)

        let discovered = GhosttyResources.terminfoURL(
            bundle: .main,
            sourceFilePath: source.path
        )

        #expect(discovered?.standardizedFileURL == expected.standardizedFileURL)
    }

    @Test func tmuxSettingsStatusRechecksAvailabilityAndVersion() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-tmux-status-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("tmux", isDirectory: false)
        try "#!/bin/sh\nprintf 'tmux test-version\\n'\n"
            .write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        var installation: TmuxInstallation?
        let status = TmuxStatusModel(discover: { installation })
        #expect(status.availability == .unavailable)

        installation = TmuxInstallation(executableURL: executable)
        status.recheck()

        #expect(status.availability == .available(
            path: executable.path,
            version: "tmux test-version"
        ))
    }

    @Test func tmuxSessionNamesAreStableAndProjectIsolated() {
        let project = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let terminal = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        #expect(TmuxTerminalBackend.sessionName(projectID: project, terminalID: terminal) ==
            "ribbit-11111111-1111-1111-1111-111111111111-22222222-2222-2222-2222-222222222222")
        #expect(TmuxTerminalBackend.sessionName(projectID: nil, terminalID: terminal) ==
            "ribbit-base-22222222-2222-2222-2222-222222222222")
    }

    @Test func tmuxLaunchInjectsTheExactRibbitTerminalIdentity() {
        let terminal = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let backend = TmuxTerminalBackend(
            installation: TmuxInstallation(
                executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/tmux")
            ),
            socketName: "ribbit",
            sessionName: TmuxTerminalBackend.sessionName(
                projectID: nil,
                terminalID: terminal
            ),
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        #expect(backend.launchArguments.contains(
            "RIBBIT_TERMINAL_ID=22222222-2222-2222-2222-222222222222"
        ))
        #expect(backend.launchArguments.contains("mouse"))
        #expect(backend.launchArguments.contains("on"))
    }

    @Test func isolatedTmuxSessionCanCreateInspectAndTerminate() {
        guard let installation = TmuxInstallation.discover() else { return }
        let terminalID = UUID()
        let backend = TmuxTerminalBackend(
            installation: installation,
            socketName: "ribbit-tests-\(UUID().uuidString.lowercased())",
            sessionName: TmuxTerminalBackend.sessionName(
                projectID: UUID(),
                terminalID: terminalID
            ),
            workingDirectory: FileManager.default.temporaryDirectory
        )
        defer { _ = backend.terminate() }

        #expect(TerminalBackend.directShell.recoveryState(restoring: false) == .none)
        #expect(TerminalBackend.directShell.recoveryState(restoring: true) == .persistenceUnavailable)
        #expect(TerminalBackend.tmux(backend).recoveryState(restoring: true) == .tmuxSessionRecreated)
        #expect(!backend.hasSession())
        #expect(backend.createDetached())
        #expect(backend.hasSession())
        #expect(backend.isMouseModeEnabled())
        #expect(TerminalBackend.tmux(backend).recoveryState(restoring: true) == .none)
        #expect(backend.terminate())
        #expect(!backend.hasSession())
    }

    @Test func modifiedReturnRespectsGhosttyBindingAndEnhancedInput() throws {
        var sentKeys: [TerminalInputTestHarness.KeyAction] = []
        var bindingActions: [String] = []
        var sentBytes: [[UInt8]] = []
        let event = try #require(Self.keyEvent(
            characters: "\r",
            modifiers: .option,
            keyCode: 36
        ))
        let boundView = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in true },
            sendKey: { _, action in
                sentKeys.append(action)
                return true
            },
            sendBindingAction: {
                bindingActions.append($0)
                return true
            },
            observeBytes: { sentBytes.append($0) }
        ))

        boundView.keyDown(with: event)
        #expect(sentKeys == [.press])
        #expect(bindingActions.isEmpty)
        #expect(sentBytes.isEmpty)

        sentKeys.removeAll()
        let enhancedView = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in false },
            sendKey: { _, action in
                sentKeys.append(action)
                return true
            },
            sendBindingAction: {
                bindingActions.append($0)
                return true
            },
            observeBytes: { sentBytes.append($0) }
        ))
        enhancedView.enhancedKeyboardInputEnabled = true
        enhancedView.keyDown(with: event)

        #expect(sentKeys == [.press])
        #expect(bindingActions.isEmpty)
        #expect(sentBytes.isEmpty)
    }

    private static func keyEvent(
        type: NSEvent.EventType = .keyDown,
        characters: String,
        modifiers: NSEvent.ModifierFlags,
        keyCode: UInt16
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 1,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    @Test func droppedPathsAreQuotedForTheShell() {
        let insertion = AgentTerminalInput.insertionText(for: [
            "/tmp/a file.png",
            "/tmp/developer's note.txt"
        ])

        #expect(insertion == "'/tmp/a file.png' '/tmp/developer'\\''s note.txt' ")
    }

    @Test func finderFileDropBecomesAnAbsoluteTerminalPath() throws {
        let pasteboard = NSPasteboard(name: .init("ribbit-file-drop-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let fileURL = URL(fileURLWithPath: "/tmp/ribbit drop.png")
        #expect(pasteboard.writeObjects([fileURL as NSURL]))

        let insertion = try TerminalDropReader.insertionText(
            from: pasteboard,
            attachmentDirectoryURL: FileManager.default.temporaryDirectory
        )

        #expect(insertion == "'/tmp/ribbit drop.png' ")
    }

    @Test func rawImageDropIsSavedAsAProjectAttachment() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-image-drop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pasteboard = NSPasteboard(name: .init("ribbit-image-drop-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 4,
            bitsPerPixel: 32
        )
        let pngData = try #require(bitmap?.representation(using: .png, properties: [:]))
        pasteboard.setData(pngData, forType: .png)

        let droppedText = try TerminalDropReader.insertionText(
            from: pasteboard,
            attachmentDirectoryURL: root
        )
        let insertion = try #require(droppedText)
        let filename = try #require(insertion.split(separator: "'").first).description
        let savedURL = URL(fileURLWithPath: filename)

        #expect(savedURL.deletingLastPathComponent() == root)
        #expect(savedURL.pathExtension == "png")
        #expect(FileManager.default.fileExists(atPath: savedURL.path))
    }

    @Test func addingNoteSelectsIt() {
        let model = AppModel(
            projectURL: URL(fileURLWithPath: "/tmp"),
            terminalBackendPreference: .directShell
        )
        model.newNote()
        #expect(model.selectedTab?.kind == .note)
        #expect(model.selectedTab?.title == "untitled.txt")
    }

    @Test func closingLastVisibleTabLeavesTheCanvasEmpty() {
        let model = AppModel(
            projectURL: URL(fileURLWithPath: "/tmp"),
            terminalBackendPreference: .directShell
        )
        let original = model.tabs[0]
        model.closeTab(original)
        #expect(model.tabs.isEmpty)
        #expect(model.selectedTabID == nil)
    }

    @Test func newTerminalCreatesAnIndependentSession() throws {
        let model = AppModel(
            projectURL: URL(fileURLWithPath: "/tmp"),
            terminalBackendPreference: .directShell
        )
        let firstSession = try #require(model.selectedTab?.terminalSession)

        model.newTerminal()
        let secondSession = try #require(model.selectedTab?.terminalSession)

        #expect(firstSession !== secondSession)
        #expect(firstSession.view !== secondSession.view)
        #expect(model.visibleTabs.count == 2)
    }

    @Test func conventionalTabCommandsCycleSelectAndCloseTabs() throws {
        let fixture = try temporaryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = AppModel(
            projectURL: fixture.project,
            registryURL: fixture.registry,
            terminalBackendPreference: .directShell
        )
        let first = try #require(model.selectedTab)
        model.newNote()
        let second = try #require(model.selectedTab)
        model.newTerminal()
        let third = try #require(model.selectedTab)

        model.selectPreviousTab()
        #expect(model.selectedTabID == second.id)
        model.selectNextTab()
        #expect(model.selectedTabID == third.id)
        model.selectNextTab()
        #expect(model.selectedTabID == first.id)
        model.selectTab(at: 1)
        #expect(model.selectedTabID == second.id)
        model.closeSelectedTab()
        #expect(!model.visibleTabs.contains { $0.id == second.id })
        #expect(model.visibleTabs.count == 2)
    }

    @Test func terminalCanBeRenamedAndColored() throws {
        let model = AppModel(
            projectURL: URL(fileURLWithPath: "/tmp"),
            terminalBackendPreference: .directShell
        )
        let terminal = try #require(model.selectedTab)

        model.renameTerminal(terminal, to: "  agent one  ")
        model.setTerminalTint(.purple, for: terminal)

        #expect(terminal.title == "agent one")
        #expect(terminal.terminalTint == .purple)
    }

    @Test func terminalFindCreatesNativeFindBar() throws {
        let model = AppModel(
            projectURL: URL(fileURLWithPath: "/tmp"),
            terminalBackendPreference: .directShell
        )
        let session = try #require(model.selectedTab?.terminalSession)
        let initialSubviewCount = session.view.subviews.count

        model.findInSelectedTerminal()

        #expect(session.view.subviews.count > initialSubviewCount)
    }

    @Test func appearanceSettingsPersistAndApplyToNewTerminals() throws {
        let suiteName = "ribbit-settings-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.colorScheme = .midnight
        settings.projectRailTextSize = 13
        settings.tabTextSize = 15
        settings.terminalTextSize = 19
        settings.editorTextSize = 18
        settings.filesTextSize = 12
        settings.glassySurfacesEnabled = true
        settings.sidebarOpacity = 0.65
        settings.sidebarBlur = 0.55
        settings.glassDepth = 0.75
        settings.notchMonitorEnabled = true
        settings.notchExpandOnHover = false
        settings.notchHoverDelay = 0.4
        settings.notchAutoCollapse = false
        settings.notchAttentionRevealDwell = 8
        settings.notchDisplayTarget = .followRibbit
        settings.notchShowActivityDetail = false
        settings.notchHideInFullScreen = true
        settings.notchExpandedWidth = .wide
        settings.notchOpacity = 0.7
        settings.notchBlur = 0.45

        let restored = AppSettings(defaults: defaults)
        #expect(restored.colorScheme == .midnight)
        #expect(restored.projectRailTextSize == 13)
        #expect(restored.tabTextSize == 15)
        #expect(restored.terminalTextSize == 19)
        #expect(restored.editorTextSize == 18)
        #expect(restored.filesTextSize == 12)
        #expect(restored.glassySurfacesEnabled)
        #expect(restored.sidebarOpacity == 0.65)
        #expect(restored.sidebarBlur == 0.55)
        #expect(restored.glassDepth == 0.75)
        #expect(restored.notchMonitorEnabled)
        #expect(!restored.notchExpandOnHover)
        #expect(restored.notchHoverDelay == 0.4)
        #expect(!restored.notchAutoCollapse)
        #expect(restored.notchAttentionRevealDwell == 8)
        #expect(restored.notchDisplayTarget == .followRibbit)
        #expect(!restored.notchShowActivityDetail)
        #expect(restored.notchHideInFullScreen)
        #expect(restored.notchExpandedWidth == .wide)
        #expect(restored.notchOpacity == 0.7)
        #expect(restored.notchBlur == 0.45)

        let model = AppModel(
            projectURL: URL(fileURLWithPath: "/tmp"),
            settings: restored,
            terminalBackendPreference: .directShell
        )
        let session = try #require(model.selectedTab?.terminalSession)
        #expect(session.view.font.pointSize == 19)
    }

    @Test func blurSettingsPreserveExistingGlassStrengthOnUpgrade() throws {
        let suiteName = "ribbit-blur-migration-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(0.40, forKey: "appearance.sidebarOpacity")
        defaults.set(0.25, forKey: "appearance.glassDepth")

        let settings = AppSettings(defaults: defaults)
        #expect(abs(settings.sidebarBlur - (0.40 * 0.55 / 0.70)) < 0.000_001)
        #expect(abs(settings.notchBlur - (0.25 * 0.58 / 0.72)) < 0.000_001)
    }

    @Test func ribbitHereCreatesNotesAndPersistsProject() throws {
        let fixture = try temporaryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let model = AppModel(
            projectURL: fixture.project,
            registryURL: fixture.registry,
            terminalBackendPreference: .directShell
        )
        model.ribbitHere(fixture.project)

        #expect(FileManager.default.fileExists(
            atPath: fixture.project.appendingPathComponent("ribbit-notes").path
        ))
        #expect(model.selectedProject?.rootURL == fixture.project.standardizedFileURL)
        #expect(model.selectedTab?.terminalSession?.currentDirectory == fixture.project.path)

        let restored = AppModel(
            registryURL: fixture.registry,
            terminalBackendPreference: .directShell
        )
        #expect(restored.selectedProject?.rootURL == fixture.project.standardizedFileURL)
    }

    @Test func projectNotesUseRibbitNotesFolder() throws {
        let fixture = try temporaryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let model = AppModel(
            projectURL: fixture.project,
            registryURL: fixture.registry,
            terminalBackendPreference: .directShell
        )
        model.ribbitHere(fixture.project)
        model.newNote()

        #expect(model.selectedTab?.kind == .note)
        #expect(model.selectedTab?.fileURL?.deletingLastPathComponent().lastPathComponent == "ribbit-notes")
        #expect(FileManager.default.fileExists(atPath: model.selectedTab?.fileURL?.path ?? ""))
    }

    @Test func switchingWorkspacesHidesAndRestoresTabs() throws {
        let fixture = try temporaryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let secondProject = fixture.root.appendingPathComponent("second-project", isDirectory: true)
        try FileManager.default.createDirectory(at: secondProject, withIntermediateDirectories: true)

        let model = AppModel(
            projectURL: fixture.root,
            registryURL: fixture.registry,
            terminalBackendPreference: .directShell
        )
        let baseTabID = try #require(model.selectedTab?.id)

        model.ribbitHere(fixture.project)
        model.newTerminal()
        let firstProjectTabIDs = Set(model.visibleTabs.map(\.id))
        #expect(firstProjectTabIDs.count == 2)

        model.ribbitHere(secondProject)
        #expect(model.visibleTabs.count == 1)
        #expect(Set(model.visibleTabs.map(\.id)).isDisjoint(with: firstProjectTabIDs))

        let firstProject = try #require(model.projects.first { $0.rootURL == fixture.project.standardizedFileURL })
        model.selectProject(firstProject)
        #expect(Set(model.visibleTabs.map(\.id)) == firstProjectTabIDs)

        model.selectBaseWorkspace()
        #expect(model.visibleTabs.map(\.id) == [baseTabID])
        #expect(model.projectURL == FileManager.default.homeDirectoryForCurrentUser)
        #expect(model.tabs.count == 4)
    }

    @Test func workspaceRelaunchRestoresStableTabsLayoutAndSelection() throws {
        let fixture = try temporaryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let model = AppModel(
            projectURL: fixture.project,
            registryURL: fixture.registry,
            terminalBackendPreference: .directShell
        )
        model.ribbitHere(fixture.project)
        let terminal = try #require(model.selectedTab)
        model.renameTerminal(terminal, to: "codex agent")
        model.setTerminalTint(.blue, for: terminal)
        let frame = CanvasNodeFrame(x: 91, y: 73, width: 710, height: 430)
        model.updateCanvasFrame(frame, for: terminal)

        model.newNote()
        let note = try #require(model.selectedTab)
        model.updateNoteText("persistent scratch text", for: note)
        model.setWorkspaceMode(.canvas)
        model.setCanvasCamera(CanvasCamera(x: -120, y: 44, zoom: 0.8))
        let selectedID = note.id

        let restored = AppModel(
            registryURL: fixture.registry,
            terminalBackendPreference: .directShell
        )
        let restoredTerminal = try #require(restored.visibleTabs.first { $0.kind == .terminal })
        let restoredNote = try #require(restored.visibleTabs.first { $0.kind == .note })

        #expect(restoredTerminal.id == terminal.id)
        #expect(restoredTerminal.title == "codex agent")
        #expect(restoredTerminal.terminalTint == .blue)
        #expect(restoredTerminal.canvasFrame == frame)
        #expect(restoredNote.id == note.id)
        #expect(restoredNote.text == "persistent scratch text")
        #expect(restoredNote.isDirty)
        #expect(restored.selectedTabID == selectedID)
        #expect(restored.workspaceMode == .canvas)
        #expect(restored.canvasCamera == CanvasCamera(x: -120, y: 44, zoom: 0.8))
    }

    @Test func terminalTranscriptRemovesControlSequencesAndKeepsLatestCarriageReturn() {
        let source = "start\rprogress 1\rprogress 2\n\u{001B}[31mred\u{001B}[0m\n\u{001B}]7;file:///tmp\u{0007}prompt\n"
        let rendered = TerminalTranscriptRenderer.render(Data(source.utf8))

        #expect(rendered == "progress 2\nred\nprompt\n")
    }

    @Test func terminalJournalRotatesOldSegmentsAndConsumesSaveRequests() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-journal-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try TerminalJournal(directoryURL: root, maximumBytes: 12, segmentBytes: 5)

        journal.append(Data("0123456789abcdef".utf8))
        let transcript = journal.transcript()
        #expect(transcript == "56789abcdef\n")

        try "agent run".write(to: journal.requestURL, atomically: true, encoding: .utf8)
        guard case let .save(name)? = journal.consumeSaveRequest() else {
            Issue.record("expected a save request")
            return
        }
        #expect(name == "agent run")
        #expect(!FileManager.default.fileExists(atPath: journal.requestURL.path))
    }

    @Test func ribbitCommandInstallerCreatesProjectAwareSaveCommand() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-command-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let binURL = try RibbitCommandInstaller.install(in: root)
        let commandURL = binURL.appendingPathComponent("ribbit")
        let script = try String(contentsOf: commandURL, encoding: .utf8)
        let permissions = try #require(
            FileManager.default.attributesOfItem(atPath: commandURL.path)[.posixPermissions] as? NSNumber
        )

        #expect(script.contains("RIBBIT_SAVE_REQUEST"))
        #expect(script.contains("RIBBIT_CONTEXT_INDEX"))
        #expect(script.contains("tail -c 36"))
        #expect(script.contains("usage: ribbit save [note-name]"))
        #expect(permissions.intValue & 0o111 != 0)
    }

    @Test func projectTerminalJournalExportsAsAnOpenNote() throws {
        let fixture = try temporaryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let support = fixture.root.appendingPathComponent("journal-support", isDirectory: true)
        let model = AppModel(
            projectURL: fixture.project,
            registryURL: fixture.registry,
            journalSupportURL: support,
            terminalBackendPreference: .directShell
        )
        model.ribbitHere(fixture.project)
        let terminal = try #require(model.selectedTab)
        let session = try #require(terminal.terminalSession)
        session.journal?.append(Data("journal export marker\n".utf8))

        let destination = try #require(model.saveTerminalJournal(
            terminal,
            requestedName: "Agent Session",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let noteText = try String(contentsOf: destination, encoding: .utf8)

        #expect(destination.deletingLastPathComponent().lastPathComponent == "ribbit-notes")
        #expect(destination.lastPathComponent.hasSuffix("-agent-session.txt"))
        #expect(noteText.contains("journal export marker"))
        #expect(model.selectedTab?.kind == .note)
        #expect(model.selectedTab?.fileURL == destination)
    }

    @Test func ribbitSaveCommandTriggersProjectNoteExport() throws {
        let fixture = try temporaryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let support = fixture.root.appendingPathComponent("command-support", isDirectory: true)
        let model = AppModel(
            projectURL: fixture.project,
            registryURL: fixture.registry,
            journalSupportURL: support,
            terminalBackendPreference: .directShell
        )
        model.ribbitHere(fixture.project)
        let terminal = try #require(model.selectedTab)
        let session = try #require(terminal.terminalSession)
        let journal = try #require(session.journal)
        journal.append(Data("command bridge marker\n".utf8))

        let commandURL = support.appendingPathComponent("bin/ribbit")
        let process = Process()
        process.executableURL = commandURL
        process.arguments = ["save", "command-run"]
        var environment = ProcessInfo.processInfo.environment
        environment["RIBBIT_PROJECT"] = "1"
        environment["RIBBIT_SAVE_REQUEST"] = journal.requestURL.path
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
        let note = try #require(model.selectedTab)
        #expect(note.kind == .note)
        #expect(note.title.hasSuffix("-command-run.txt"))
        #expect(note.text.contains("command bridge marker"))
    }

    @Test func ghosttyJournalSnapshotAppendsOnlyNewOutput() {
        #expect(
            TerminalSnapshotDelta.delta(
                previous: "prompt\nfirst\n",
                current: "prompt\nfirst\nsecond\n"
            ) == "second\n"
        )
    }

    @Test func ghosttyJournalSnapshotSurvivesScrollbackTrimming() {
        #expect(
            TerminalSnapshotDelta.delta(
                previous: "old\nshared\n",
                current: "shared\nnew\n"
            ) == "new\n"
        )
    }

    @Test func agentSummaryTracksRunningAttentionAndReadyStates() {
        let running = RibbitSessionEventSummary.parse("""
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"response_item","payload":{"type":"custom_tool_call_output"}}
        """)
        #expect(running.activity == "using tools")
        #expect(running.state(modifiedAt: .now.addingTimeInterval(-120), now: .now) == .running)

        let attention = RibbitSessionEventSummary.parse(#"{"type":"approval_request"}"#)
        #expect(attention.attentionKind == .permission)
        #expect(attention.state(modifiedAt: .now, now: .now) == .attention)

        let ready = RibbitSessionEventSummary.parse(#"{"type":"task_complete"}"#)
        #expect(ready.activity == "ready for another prompt")
        #expect(ready.state(modifiedAt: .now, now: .now) == .paused)
    }

    @Test func agentSummaryRetainsProviderIdentityAndProject() {
        let summary = RibbitSessionEventSummary.parse(
            #"{"session_id":"session-42","cwd":"/tmp/ribbit"}"#
        )
        #expect(summary.sessionID == "session-42")
        #expect(summary.project == "ribbit")
    }

    @Test func codexSourceFindsRecentSessionFixture() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-agent-source-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sessionID = "019f8100-4a17-7090-a5f8-2422a88f38a7"
        let file = root.appendingPathComponent(
            "rollout-2026-07-20T15-28-27-\(sessionID).jsonl"
        )
        try """
        {"type":"session_meta","payload":{"cwd":"/tmp/ribbit"}}
        {"type":"function_call"}
        """.write(to: file, atomically: true, encoding: .utf8)

        let sessions = RibbitLocalSessionFileSource(agent: .codex, root: root).scan()

        #expect(sessions.count == 1)
        #expect(sessions.first?.agent == .codex)
        #expect(sessions.first?.providerSessionID == sessionID)
        #expect(sessions.first?.project == "ribbit")
        #expect(sessions.first?.activity == "using tools")
    }

    @Test func codexSourceUsesCanonicalMetadataInsteadOfNestedTranscriptIDs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-codex-route-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let canonicalID = "019f8100-4a17-7090-a5f8-2422a88f38a7"
        let file = root.appendingPathComponent(
            "rollout-2026-07-20T15-28-27-\(canonicalID).jsonl"
        )
        try """
        {"type":"session_meta","payload":{"id":"\(canonicalID)","session_id":"legacy-id","cwd":"/tmp/ribbit","thread_source":"user"}}
        {"type":"custom_tool_call_output","payload":{"output":"{\\"session_id\\":\\"unrelated-tool-id\\"}"}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let session = try #require(
            RibbitLocalSessionFileSource(agent: .codex, root: root).scan().first
        )
        #expect(session.providerSessionID == canonicalID)
        #expect(
            RibbitAgentFocusRouter.codexURL(for: session)?.absoluteString
                == "codex://threads/\(canonicalID)"
        )
    }

    @Test func codexSubagentRoutesBackToItsVisibleParentTask() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-codex-subagent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let parentID = "019f9172-0b65-72f2-92ac-6a6774ba20bf"
        let childID = "019f9173-2122-79b1-a4ad-91e524cd8cb1"
        let file = root.appendingPathComponent(
            "rollout-2026-07-23T20-07-49-\(childID).jsonl"
        )
        try """
        {"type":"session_meta","payload":{"id":"\(childID)","session_id":"\(parentID)","parent_thread_id":"\(parentID)","forked_from_id":"\(parentID)","thread_source":"subagent","cwd":"/tmp/ribbit"}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let session = try #require(
            RibbitLocalSessionFileSource(agent: .codex, root: root).scan().first
        )
        #expect(session.providerSessionID == parentID)
    }

    @Test func exactRibbitTerminalIdentityWinsSessionResolution() {
        let exactID = UUID()
        let otherID = UUID()
        let session = RibbitAgentSession(
            id: "codex:42",
            providerSessionID: "42",
            agent: .codex,
            title: "codex session",
            project: "same-project",
            activity: "thinking",
            state: .running,
            lastUpdated: .now,
            sourceURL: nil,
            isBridgeSession: true,
            attentionKind: nil,
            attentionDetail: nil,
            focusTarget: RibbitSessionFocusTarget(
                surface: .ribbit,
                terminalSessionID: exactID.uuidString.lowercased(),
                workingDirectory: "/tmp/same-project"
            )
        )
        let terminals = [
            RibbitTerminalIdentity(
                id: otherID,
                projectID: UUID(),
                workingDirectory: "/tmp/same-project",
                projectRoot: "/tmp/same-project"
            ),
            RibbitTerminalIdentity(
                id: exactID,
                projectID: UUID(),
                workingDirectory: "/tmp/same-project",
                projectRoot: "/tmp/same-project"
            )
        ]

        #expect(RibbitAgentSessionResolver.terminalID(for: session, among: terminals) == exactID)
    }

    @Test func sessionResolutionUsesOnlyUnambiguousDirectoryFallback() {
        let firstID = UUID()
        let secondID = UUID()
        var session = RibbitAgentSession(
            id: "claude:42",
            providerSessionID: "42",
            agent: .claude,
            title: "claude session",
            project: "project",
            activity: "thinking",
            state: .running,
            lastUpdated: .now,
            sourceURL: nil,
            isBridgeSession: false,
            attentionKind: nil,
            attentionDetail: nil,
            focusTarget: RibbitSessionFocusTarget(
                surface: .application,
                workingDirectory: "/tmp/project"
            )
        )
        let first = RibbitTerminalIdentity(
            id: firstID,
            projectID: nil,
            workingDirectory: "/tmp/project",
            projectRoot: "/tmp/project"
        )
        let second = RibbitTerminalIdentity(
            id: secondID,
            projectID: nil,
            workingDirectory: "/tmp/other",
            projectRoot: "/tmp/other"
        )

        #expect(RibbitAgentSessionResolver.terminalID(
            for: session,
            among: [first, second]
        ) == firstID)
        session.focusTarget?.workingDirectory = nil
        #expect(RibbitAgentSessionResolver.terminalID(
            for: session,
            among: [first, first]
        ) == nil)
    }

    @Test func bridgeEventRoundTripPreservesRibbitTerminalTarget() throws {
        let terminalID = UUID()
        let event = RibbitAgentBridgeEvent(
            id: "codex:thread-42",
            providerSessionID: "thread-42",
            agent: .codex,
            title: "codex session",
            project: "ribbit",
            activity: "using tools",
            state: .running,
            attentionKind: nil,
            attentionDetail: nil,
            focusTarget: RibbitSessionFocusTarget(
                surface: .ribbit,
                applicationName: "ribbit",
                terminalSessionID: terminalID.uuidString.lowercased(),
                workingDirectory: "/tmp/ribbit"
            )
        )

        let restored = try JSONDecoder().decode(
            RibbitAgentBridgeEvent.self,
            from: JSONEncoder().encode(event)
        )

        #expect(restored.focusTarget?.surface == .ribbit)
        #expect(restored.focusTarget?.terminalSessionID == terminalID.uuidString.lowercased())
    }

    @Test func liveBridgeEventAssignsAndClearsTheExactTerminalBadge() {
        let terminalID = UUID()
        let monitor = RibbitAgentMonitor(
            homeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("ribbit-empty-home-\(UUID().uuidString)")
        )
        var assignments: [UUID: RibbitAgentSession] = [:]
        monitor.start(
            terminalIdentities: {
                [
                    RibbitTerminalIdentity(
                        id: terminalID,
                        projectID: nil,
                        workingDirectory: "/tmp/ribbit",
                        projectRoot: "/tmp/ribbit"
                    )
                ]
            },
            onAssignmentsChanged: { assignments = $0 },
            startsBridge: false,
            schedulesRefresh: false
        )
        var event = RibbitAgentBridgeEvent(
            id: "codex:42",
            providerSessionID: "42",
            agent: .codex,
            title: "codex session",
            project: "ribbit",
            activity: "using tools",
            state: .running,
            attentionKind: nil,
            attentionDetail: nil,
            focusTarget: RibbitSessionFocusTarget(
                surface: .ribbit,
                terminalSessionID: terminalID.uuidString
            )
        )

        monitor.apply(event)
        #expect(assignments[terminalID]?.activity == "using tools")

        event.state = .completed
        monitor.apply(event)
        #expect(assignments[terminalID] == nil)
    }

    @Test func bridgeProjectsSubagentsAndCronJobsOntoTheirTerminal() {
        let terminalID = UUID()
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-empty-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let monitor = RibbitAgentMonitor(homeURL: homeURL)
        let target = RibbitSessionFocusTarget(
            surface: .ribbit,
            terminalSessionID: terminalID.uuidString
        )
        var event = RibbitAgentBridgeEvent(
            id: "claude:42",
            providerSessionID: "42",
            agent: .claude,
            title: "claude session",
            project: "ribbit",
            activity: "using Agent",
            state: .running,
            focusTarget: target,
            canvasAction: .start,
            canvasActivityID: "tool-1",
            canvasActivityKind: .subagent,
            canvasActivityType: "general-purpose",
            canvasTask: "scan processes"
        )

        let started = Date(timeIntervalSince1970: 100)
        monitor.apply(event, now: started)
        #expect(monitor.canvasActivities.count == 1)
        #expect(monitor.canvasActivities[0].parentTerminalID == terminalID)
        #expect(monitor.canvasActivities[0].state == .working)
        #expect(monitor.canvasActivities[0].task == "scan processes")

        event.canvasAction = .finish
        event.canvasDurationMilliseconds = 1_500
        event.canvasTokens = 800
        monitor.apply(event, now: started.addingTimeInterval(2))
        #expect(monitor.canvasActivities[0].state == .done)
        #expect(monitor.canvasActivities[0].durationMilliseconds == 1_500)
        #expect(monitor.canvasActivities[0].tokens == 800)

        event.canvasAction = .start
        event.canvasActivityID = "cron:42"
        event.canvasActivityKind = .cron
        event.canvasActivityType = nil
        event.canvasTask = "scan every morning"
        event.canvasSchedule = "0 9 * * *"
        monitor.apply(event)
        #expect(monitor.canvasActivities.count == 2)
        let restored = RibbitAgentMonitor(homeURL: homeURL)
        #expect(restored.canvasActivities.count == 1)
        #expect(restored.canvasActivities[0].kind == .cron)
        #expect(restored.canvasActivities[0].schedule == "0 9 * * *")

        event.canvasAction = .remove
        event.canvasActivityID = nil
        monitor.apply(event)
        #expect(monitor.canvasActivities.map(\.kind) == [.subagent])
    }

    @Test @MainActor
    func monitorKeepsDistinctTasksInOneWorkspaceAndMergesExactDuplicates() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-agent-merge-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionsRoot = root
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionsRoot,
            withIntermediateDirectories: true
        )
        let bridgeID = "019f82ec-6959-70c2-92ba-75f369069fb3"
        let exactTranscript = sessionsRoot.appendingPathComponent(
            "rollout-2026-07-23T20-07-49-\(bridgeID).jsonl"
        )
        try """
        {"type":"session_meta","payload":{"id":"\(bridgeID)","session_id":"\(bridgeID)","cwd":"/tmp/ribbit","thread_source":"user"}}
        {"type":"event_msg","payload":{"type":"task_started"}}
        """.write(to: exactTranscript, atomically: true, encoding: .utf8)
        let secondID = "019f9173-2122-79b1-a4ad-91e524cd8cb1"
        let secondTranscript = sessionsRoot.appendingPathComponent(
            "rollout-2026-07-23T20-08-49-\(secondID).jsonl"
        )
        try """
        {"type":"session_meta","payload":{"id":"\(secondID)","session_id":"\(secondID)","cwd":"/tmp/ribbit","thread_source":"user"}}
        {"type":"event_msg","payload":{"type":"task_started"}}
        """.write(to: secondTranscript, atomically: true, encoding: .utf8)

        let bridge = RibbitAgentSession(
            id: "codex:\(bridgeID)",
            providerSessionID: bridgeID,
            agent: .codex,
            title: "codex session",
            project: "ribbit",
            activity: "using tools",
            state: .running,
            lastUpdated: .now,
            sourceURL: nil,
            isBridgeSession: true,
            attentionKind: nil,
            attentionDetail: nil,
            focusTarget: .init(
                surface: .codex,
                applicationName: "ChatGPT",
                workingDirectory: "/tmp/ribbit"
            )
        )
        RibbitAgentStateStore.persist(
            [bridge],
            to: root.appendingPathComponent(
                "Library/Application Support/ribbit/agent-sessions.json"
            )
        )

        let monitor = RibbitAgentMonitor(homeURL: root)
        monitor.start(
            terminalIdentities: { [] },
            onAssignmentsChanged: { _ in },
            startsBridge: false,
            schedulesRefresh: false
        )

        #expect(Set(monitor.sessions.map(\.id)) == [
            bridge.id,
            "codex:\(secondID)",
        ])
        #expect(monitor.sessions.first { $0.id == bridge.id }?
            .focusTarget?.surface == .codex)
    }

    @Test func genericTerminalBridgeYieldsToCodexTranscriptDestination() {
        let bridge = RibbitSessionFocusTarget(
            surface: .application,
            applicationName: "Terminal",
            workingDirectory: "/tmp/ribbit"
        )
        let local = RibbitSessionFocusTarget(
            surface: .codex,
            applicationName: "ChatGPT",
            workingDirectory: "/tmp/ribbit"
        )

        let resolved = RibbitAgentMonitor.resolvedFocusTarget(
            bridge: bridge,
            local: local
        )

        #expect(resolved?.surface == .codex)
        #expect(resolved?.applicationName == "ChatGPT")
    }

    @Test func exactRibbitBridgeDestinationBeatsCodexTranscriptFallback() {
        let terminalID = UUID()
        let bridge = RibbitSessionFocusTarget(
            surface: .ribbit,
            applicationName: "ribbit",
            terminalSessionID: terminalID.uuidString,
            workingDirectory: "/tmp/ribbit"
        )
        let local = RibbitSessionFocusTarget(
            surface: .codex,
            applicationName: "ChatGPT",
            workingDirectory: "/tmp/ribbit"
        )

        let resolved = RibbitAgentMonitor.resolvedFocusTarget(
            bridge: bridge,
            local: local
        )

        #expect(resolved == bridge)
    }

    @Test func claudeProcessLivenessSupportsMonitorCleanup() {
        #expect(RibbitAgentMonitor.processIsRunning(
            ProcessInfo.processInfo.processIdentifier
        ))
        #expect(!RibbitAgentMonitor.processIsRunning(-1))
    }

    @Test func focusTargetRoundTripPreservesClaudeOwnershipAndTmuxPane() throws {
        let target = RibbitSessionFocusTarget(
            surface: .terminal,
            applicationName: "Terminal",
            tty: "/dev/ttys001",
            workingDirectory: "/tmp/ribbit",
            processID: 4242,
            tmuxTarget: "work:2.1",
            tmuxSocketPath: "/tmp/tmux-501/default"
        )

        let restored = try JSONDecoder().decode(
            RibbitSessionFocusTarget.self,
            from: JSONEncoder().encode(target)
        )

        #expect(restored == target)
    }

    @Test @MainActor
    func staleRibbitTerminalBridgeIsRemovedWhenItsTabNoLongerExists() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-stale-agent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let missingTerminalID = UUID()
        let session = RibbitAgentSession(
            id: "codex:stale",
            providerSessionID: "stale",
            agent: .codex,
            title: "codex session",
            project: "ribbit",
            activity: "ready for another prompt",
            state: .paused,
            lastUpdated: .now,
            sourceURL: nil,
            isBridgeSession: true,
            attentionKind: nil,
            attentionDetail: nil,
            focusTarget: .init(
                surface: .ribbit,
                applicationName: "ribbit",
                terminalSessionID: missingTerminalID.uuidString
            )
        )
        RibbitAgentStateStore.persist(
            [session],
            to: root.appendingPathComponent(
                "Library/Application Support/ribbit/agent-sessions.json"
            )
        )
        let monitor = RibbitAgentMonitor(homeURL: root)
        monitor.start(
            terminalIdentities: { [] },
            onAssignmentsChanged: { _ in },
            startsBridge: false,
            schedulesRefresh: false
        )

        #expect(monitor.sessions.isEmpty)
        let restored = RibbitAgentStateStore.loadOrMigrate(homeURL: root)
        #expect(restored.isEmpty)
    }

    @Test func agentBridgeParsesCRLFContentLength() {
        let header = """
        POST /v1/events HTTP/1.1\r
        Host: 127.0.0.1\r
        Content-Length: 124
        """
        #expect(RibbitAgentBridgeServer.contentLength(in: header) == 124)
    }

    @Test func dismantlingPresentationDoesNotDetachThePersistentGhosttySurface() {
        let terminal = RibbitGhosttyView(inputTestHarness: .init(
            isBinding: { _ in false },
            sendKey: { _, _ in true },
            sendBindingAction: { _ in true }
        ))
        let container = NSView()
        container.addSubview(terminal)

        TerminalRepresentable.dismantleNSView(
            terminal,
            coordinator: TerminalRepresentable.Coordinator()
        )

        #expect(terminal.superview === container)
    }

    @Test func versionOneWorkspaceMigratesWithNoContextLinks() throws {
        let json = """
        {
          "version": 1,
          "selectedTabID": null,
          "mode": "tabs",
          "camera": {"x": 0, "y": 0, "zoom": 1},
          "tabs": []
        }
        """

        let document = try JSONDecoder().decode(
            WorkspaceDocument.self,
            from: Data(json.utf8)
        )

        #expect(document.version == 1)
        #expect(document.contextEdges.isEmpty)
    }

    @Test func directedContextLinksPersistAcrossWorkspaceRelaunch() throws {
        let fixture = try temporaryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let workspaces = fixture.root.appendingPathComponent("workspaces", isDirectory: true)
        let first = AppModel(
            projectURL: fixture.project,
            registryURL: fixture.registry,
            workspaceDirectoryURL: workspaces,
            terminalBackendPreference: .directShell
        )
        let source = try #require(first.selectedTab)
        first.newNote()
        let target = try #require(first.selectedTab)
        first.addContextLink(from: source, to: target)
        let edge = try #require(first.contextEdges.first)
        #expect(edge.sourceTabID == source.id)
        #expect(edge.targetTabID == target.id)

        let restored = AppModel(
            projectURL: fixture.project,
            registryURL: fixture.registry,
            workspaceDirectoryURL: workspaces,
            terminalBackendPreference: .directShell
        )

        #expect(restored.contextEdges == [edge])
    }

    @Test func initialCanvasNodesDoNotOverlap() {
        let first = CanvasNodeFrame.initial(kind: .terminal, index: 0)
        let second = CanvasNodeFrame.initial(kind: .note, index: 1)
        let firstRect = CGRect(
            x: first.x,
            y: first.y,
            width: first.width,
            height: first.height
        )
        let secondRect = CGRect(
            x: second.x,
            y: second.y,
            width: second.width,
            height: second.height
        )
        #expect(!firstRect.intersects(secondRect))
    }

    @Test func ribbitContextCommandListsAndReadsOnlyLinkedSources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-context-command-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = try RibbitCommandInstaller.install(in: root)
        let command = bin.appendingPathComponent("ribbit")
        let noteID = UUID()
        let note = root.appendingPathComponent("linked-note.txt")
        try "linked context marker\n".write(to: note, atomically: true, encoding: .utf8)
        let indexURL = root.appendingPathComponent("context.json")
        let index = RibbitContextIndex(
            targetTerminalID: UUID(),
            links: [
                RibbitContextEntry(
                    id: noteID,
                    title: "design notes",
                    kind: .note,
                    contentPath: note.path
                )
            ]
        )
        try JSONEncoder().encode(index).write(to: indexURL)

        func run(_ arguments: [String]) throws -> (Int32, String) {
            let process = Process()
            let output = Pipe()
            process.executableURL = command
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["RIBBIT_CONTEXT_INDEX"] = indexURL.path
            process.environment = environment
            process.standardOutput = output
            process.standardError = output
            try process.run()
            process.waitUntilExit()
            return (
                process.terminationStatus,
                String(
                    decoding: output.fileHandleForReading.readDataToEndOfFile(),
                    as: UTF8.self
                )
            )
        }

        let listed = try run(["context", "list"])
        #expect(listed.0 == 0)
        #expect(listed.1.lowercased().contains(noteID.uuidString.lowercased()))
        #expect(listed.1.contains("design notes"))

        let read = try run(["context", "read", "design notes"])
        #expect(read.0 == 0)
        #expect(read.1 == "linked context marker\n")

        let missing = try run(["context", "read", "unlinked"])
        #expect(missing.0 == 1)
        #expect(missing.1.contains("linked context not found"))
    }

    @Test func providerResumeCommandsAreExplicitAndShellSafe() {
        #expect(RibbitProviderResume.command(
            agent: .codex,
            sessionID: "codex:abc-123"
        ) == "codex resume 'abc-123'")
        #expect(RibbitProviderResume.command(
            agent: .claude,
            sessionID: "session'quoted"
        ) == "claude --resume 'session'\"'\"'quoted'")
        #expect(RibbitProviderResume.command(
            agent: .cursor,
            sessionID: "cursor-session"
        ) == nil)
        #expect(RibbitProviderResume.command(agent: .codex, sessionID: nil) == nil)
    }

    @Test func codexFocusURLUsesCanonicalProviderSessionID() throws {
        let session = RibbitAgentSession(
            id: "codex:thread-123",
            providerSessionID: "codex:thread-123",
            agent: .codex,
            title: "codex",
            project: "ribbit",
            activity: "ready",
            state: .paused,
            lastUpdated: .now,
            sourceURL: nil,
            isBridgeSession: true,
            attentionKind: nil,
            attentionDetail: nil,
            focusTarget: .init(surface: .codex)
        )
        #expect(RibbitAgentFocusRouter.codexURL(for: session)?.absoluteString
            == "codex://threads/thread-123")
    }

    @Test func explicitCodexTargetsBypassRibbitsTerminalMatching() {
        #expect(RibbitSessionFocusTarget.Surface.codex.routesOutsideRibbit)
        #expect(RibbitSessionFocusTarget.Surface.cursor.routesOutsideRibbit)
        #expect(RibbitSessionFocusTarget.Surface.iTerm.routesOutsideRibbit)
        #expect(RibbitSessionFocusTarget.Surface.application.routesOutsideRibbit)
        #expect(!RibbitSessionFocusTarget.Surface.ribbit.routesOutsideRibbit)
        #expect(!RibbitSessionFocusTarget.Surface.terminal.routesOutsideRibbit)
    }

    @Test func agentTransitionsNotifyOnlyOnNewReadyOrAttentionStates() {
        let now = Date()
        func session(_ state: RibbitAgentState) -> RibbitAgentSession {
            RibbitAgentSession(
                id: "codex:one",
                providerSessionID: "one",
                agent: .codex,
                title: "codex",
                project: "ribbit",
                activity: state.label,
                state: state,
                lastUpdated: now,
                sourceURL: nil,
                isBridgeSession: true,
                attentionKind: state == .attention ? .permission : nil,
                attentionDetail: nil,
                focusTarget: nil
            )
        }

        let ready = RibbitAgentTransition.detect(
            previous: [session(.running)],
            current: [session(.paused)]
        )
        #expect(ready.ready.count == 1)
        #expect(ready.needsAttention.isEmpty)

        let attention = RibbitAgentTransition.detect(
            previous: [session(.running)],
            current: [session(.attention)]
        )
        #expect(attention.ready.isEmpty)
        #expect(attention.needsAttention.count == 1)

        #expect(RibbitAgentTransition.detect(
            previous: [session(.attention)],
            current: [session(.attention)]
        ).isEmpty)
    }

    @Test func workspacePersistsProviderRecoveryMetadata() throws {
        let record = WorkspaceTabRecord(
            id: UUID(),
            kind: .terminal,
            title: "codex",
            text: "",
            isDirty: false,
            terminalTint: .green,
            canvasFrame: nil,
            filePath: nil,
            terminalDirectoryPath: "/tmp",
            lastKnownAgent: .codex,
            providerSessionID: "thread-123"
        )
        let document = WorkspaceDocument(
            selectedTabID: record.id,
            mode: .tabs,
            camera: .initial,
            tabs: [record]
        )
        let restored = try JSONDecoder().decode(
            WorkspaceDocument.self,
            from: JSONEncoder().encode(document)
        )
        #expect(restored.version == WorkspaceDocument.currentVersion)
        #expect(restored.tabs.first?.lastKnownAgent == .codex)
        #expect(restored.tabs.first?.providerSessionID == "thread-123")
    }

    @Test func externalAgentPinsPersistWithCanvasPosition() throws {
        let fixture = try temporaryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let workspaces = fixture.root.appendingPathComponent("workspaces", isDirectory: true)
        let model = AppModel(
            projectURL: fixture.project,
            registryURL: fixture.registry,
            workspaceDirectoryURL: workspaces,
            terminalBackendPreference: .directShell
        )
        let session = RibbitAgentSession(
            id: "codex:external-pin",
            providerSessionID: "external-pin",
            agent: .codex,
            title: "external codex",
            project: "sample-project",
            activity: "working",
            state: .running,
            lastUpdated: .now,
            sourceURL: nil,
            isBridgeSession: true,
            attentionKind: nil,
            attentionDetail: nil,
            focusTarget: .init(surface: .codex)
        )
        model.pinAgent(session, at: CGPoint(x: 211, y: 144))
        let pin = try #require(model.externalAgentPins.first)
        #expect(pin.canvasFrame.x == 211)
        #expect(pin.canvasFrame.y == 144)
        let moved = pin.canvasFrame.movedBy(width: 123, height: 77)
        model.updateExternalAgentPinFrame(moved, for: pin)

        let restored = AppModel(
            projectURL: fixture.project,
            registryURL: fixture.registry,
            workspaceDirectoryURL: workspaces,
            terminalBackendPreference: .directShell
        )

        #expect(restored.workspaceMode == .canvas)
        #expect(restored.externalAgentPins.count == 1)
        #expect(restored.externalAgentPins.first?.session.id == session.id)
        #expect(restored.externalAgentPins.first?.canvasFrame == moved)
    }

    @Test func olderWorkspaceMigratesAndIgnoresRemovedCanvasGroups() throws {
        let json = """
        {
          "version": 3,
          "mode": "tabs",
          "camera": {"x": 0, "y": 0, "zoom": 1},
          "tabs": [],
          "contextEdges": [],
          "canvasGroups": "removed"
        }
        """
        let document = try JSONDecoder().decode(
            WorkspaceDocument.self,
            from: Data(json.utf8)
        )
        #expect(document.version == 3)
        #expect(document.externalAgentPins.isEmpty)
    }

    @Test func nootAgentStateMigratesOnceWithoutDeletingLegacyData() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-noot-migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let legacyURL = home
            .appendingPathComponent("Library/Application Support/Noot", isDirectory: true)
            .appendingPathComponent("sessions.json")
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacy: [[String: Any]] = [[
            "id": "codex:legacy-thread",
            "providerSessionID": "codex:legacy-thread",
            "agent": "codex",
            "title": "legacy codex",
            "project": "ribbit",
            "activity": "ready",
            "state": "paused",
            "lastUpdated": Date().timeIntervalSinceReferenceDate,
            "isBridgeSession": true,
            "focusTarget": [
                "surface": "codex",
                "terminalSessionID": UUID().uuidString.lowercased()
            ]
        ]]
        try JSONSerialization.data(withJSONObject: legacy).write(to: legacyURL)

        let migrated = RibbitAgentStateStore.loadOrMigrate(homeURL: home)

        #expect(migrated.count == 1)
        #expect(migrated.first?.providerSessionID == "legacy-thread")
        #expect(FileManager.default.fileExists(atPath: legacyURL.path))
        #expect(FileManager.default.fileExists(
            atPath: home.appendingPathComponent(
                "Library/Application Support/ribbit/agent-sessions.json"
            ).path
        ))
    }

    @Test func notchProjectionPrioritizesAttentionAndCapsOrdinarySessions() throws {
        let now = Date.now
        let sessions = [
            notchSession(id: "ready", state: .paused, updatedAt: now),
            notchSession(id: "run-old", state: .running, updatedAt: now.addingTimeInterval(-10)),
            notchSession(id: "run-new", state: .running, updatedAt: now),
            notchSession(id: "idle", state: .idle, updatedAt: now),
            notchSession(
                id: "attention",
                state: .attention,
                updatedAt: now,
                attentionKind: .permission
            ),
        ]

        let attention = RibbitAgentNotchProjection(
            sessions: sessions,
            maximumDisplayedSessions: 2
        )
        #expect(attention.life == .attention)
        #expect(attention.attentionCount == 1)
        #expect(attention.runningCount == 2)
        #expect(attention.readyCount == 1)
        #expect(attention.displayedSessions.map(\.id) == ["attention"])

        let ordinary = RibbitAgentNotchProjection(
            sessions: sessions.filter { $0.id != "attention" },
            maximumDisplayedSessions: 2
        )
        #expect(ordinary.life == .running)
        #expect(ordinary.displayedSessions.map(\.id) == ["run-new", "run-old"])
        #expect(!ordinary.visibleSessions.contains { $0.id == "idle" })
    }

    @Test @MainActor
    func monitorKeepsActionableApprovalsAndOnlyTheLatestConversationItems() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-approval-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let monitor = RibbitAgentMonitor(homeURL: root)

        for index in 0..<14 {
            monitor.apply(RibbitAgentBridgeEvent(
                id: "claude:session-1",
                providerSessionID: "session-1",
                agent: .claude,
                title: "claude session",
                project: "ribbit",
                activity: "working",
                state: .running,
                attentionKind: nil,
                attentionDetail: nil,
                approvalID: nil,
                approvalToolName: nil,
                approvalSummary: nil,
                conversationID: "item-\(index)",
                conversationRole: index.isMultiple(of: 2) ? .user : .tool,
                conversationText: "activity \(index)",
                focusTarget: nil,
                canvasAction: nil,
                canvasActivityID: nil,
                canvasActivityKind: nil,
                canvasActivityType: nil,
                canvasTask: nil,
                canvasSchedule: nil,
                canvasDurationMilliseconds: nil,
                canvasTokens: nil,
                canvasToolUses: nil
            ))
        }
        monitor.apply(RibbitAgentBridgeEvent(
            id: "claude:session-1",
            providerSessionID: "session-1",
            agent: .claude,
            title: "claude session",
            project: "ribbit",
            activity: "permission requested",
            state: .attention,
            attentionKind: .permission,
            attentionDetail: "git status --short",
            approvalID: "approval-1",
            approvalToolName: "Bash",
            approvalSummary: "git status --short",
            conversationID: "approval-item",
            conversationRole: .status,
            conversationText: "Approval requested · Bash: git status --short",
            focusTarget: nil,
            canvasAction: nil,
            canvasActivityID: nil,
            canvasActivityKind: nil,
            canvasActivityType: nil,
            canvasTask: nil,
            canvasSchedule: nil,
            canvasDurationMilliseconds: nil,
            canvasTokens: nil,
            canvasToolUses: nil
        ))

        #expect(monitor.approvalRequests.first?.toolName == "Bash")
        #expect(monitor.approvalRequests.first?.summary == "git status --short")
        #expect(monitor.conversationItemsBySessionID["claude:session-1"]?.count == 12)
        #expect(
            monitor.conversationItemsBySessionID["claude:session-1"]?.last?.id
                == "approval-item"
        )
    }

    @Test func notchDismissalReturnsOnlyForANewLivePhaseOrNewAttention() {
        let dismissedAt = Date.now
        var running = notchSession(
            id: "codex:42",
            state: .running,
            updatedAt: dismissedAt.addingTimeInterval(-1)
        )
        let record = RibbitAgentDismissalRecord(
            session: running,
            dismissedAt: dismissedAt
        )

        running.activity = "using another tool"
        running.lastUpdated = dismissedAt.addingTimeInterval(5)
        let stillHidden = RibbitAgentDismissalPolicy.reconciled(
            [running.id: record],
            with: [running]
        )
        #expect(stillHidden[running.id] != nil)

        var permission = running
        permission.state = .attention
        permission.attentionKind = .permission
        permission.attentionDetail = "approve shell access"
        permission.lastUpdated = dismissedAt.addingTimeInterval(10)
        #expect(RibbitAgentDismissalPolicy.reconciled(
            stillHidden,
            with: [permission]
        )[running.id] == nil)

        let armed = RibbitAgentDismissalPolicy.reconciled(
            stillHidden,
            with: []
        )
        #expect(armed[running.id]?.isArmedForNextLivePhase == true)
        let nextRun = notchSession(
            id: running.id,
            state: .running,
            updatedAt: dismissedAt.addingTimeInterval(20)
        )
        #expect(RibbitAgentDismissalPolicy.reconciled(
            armed,
            with: [nextRun]
        )[running.id] == nil)
    }

    @Test func notchPresentationKeepsPinnedOpenUntilExplicitCollapse() {
        var state = RibbitNotchPresentationState()
        #expect(!state.isExpanded)
        state.expandEphemerally()
        #expect(state.mode == .expandedEphemeral)
        state.expandAndPin()
        state.expandEphemerally()
        #expect(state.mode == .expandedPinned)
        state.collapse()
        #expect(state.mode == .compact)
    }

    @Test @MainActor
    func notchRoutesFocusThenCollapsesLikeNootsWorkingOverlay() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-notch-focus-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = try #require(
            UserDefaults(suiteName: "ribbit-notch-focus-\(UUID().uuidString)")
        )
        let monitor = RibbitAgentMonitor(homeURL: root)
        var focusedSessionID: String?
        let state = RibbitAgentNotchState(
            monitor: monitor,
            settings: AppSettings(defaults: defaults),
            persistedDismissalsURL: root.appendingPathComponent("dismissals.json"),
            focusSession: { focusedSessionID = $0.id }
        )
        let session = notchSession(
            id: "codex:thread-42",
            state: .running,
            updatedAt: .now
        )

        state.expandAndPin()
        state.focus(session)

        #expect(!state.isExpanded)
        #expect(focusedSessionID == session.id)
    }

    @Test func notchGeometryUsesTheHardwareGapAndStaysTopAnchored() {
        let metrics = RibbitNotchScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 40, width: 1512, height: 904),
            safeAreaTop: 38,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 650, height: 38),
            auxiliaryTopRightArea: CGRect(x: 862, y: 944, width: 650, height: 38),
            backingScaleFactor: 2
        )
        #expect(RibbitAgentNotchGeometry.hasPhysicalNotch(metrics))
        #expect(RibbitAgentNotchGeometry.hardwareNotchWidth(metrics) == 212)
        let compact = RibbitAgentNotchGeometry.compactSize(for: metrics)
        #expect(compact == CGSize(width: 280, height: 38))
        let compactFrame = RibbitAgentNotchGeometry.topAnchoredFrame(
            size: compact,
            on: metrics
        )
        #expect(compactFrame.maxY == metrics.frame.maxY)

        let expanded = RibbitAgentNotchGeometry.expandedSize(
            for: metrics,
            displayedSessionCount: 3
        )
        let expandedFrame = RibbitAgentNotchGeometry.topAnchoredFrame(
            size: expanded,
            on: metrics
        )
        #expect(expandedFrame.maxY == compactFrame.maxY)
        #expect(expandedFrame.width == 650)
        #expect(expandedFrame.height == 208)
    }

    @Test func notchExpansionCurveIsSmoothMonotonicAndNeverOvershoots() {
        let samples = stride(from: 0.0, through: 1.0, by: 0.05).map {
            RibbitAgentNotchController.fluidExpansionProgress($0)
        }

        #expect(samples.first == 0)
        #expect(samples.last == 1)
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(samples.allSatisfy { (0...1).contains($0) })
    }

    @Test func notchExpandedWidthPresetsOnlyChangeTheOpenGeometry() {
        let metrics = RibbitNotchScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 40, width: 1512, height: 904),
            safeAreaTop: 38,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 650, height: 38),
            auxiliaryTopRightArea: CGRect(x: 862, y: 944, width: 650, height: 38),
            backingScaleFactor: 2
        )
        let compact = RibbitAgentNotchGeometry.compactSize(for: metrics)
        let widths = RibbitNotchExpandedWidth.allCases.map {
            RibbitAgentNotchGeometry.expandedSize(
                for: metrics,
                displayedSessionCount: 2,
                contentWidth: $0.contentWidth
            ).width
        }

        #expect(compact == CGSize(width: 280, height: 38))
        #expect(widths == [518, 650, 782, 914])
    }

    @Test func conversationTrackerAddsOnlyACompactStripToTheNotch() {
        let metrics = RibbitNotchScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 40, width: 1512, height: 904),
            safeAreaTop: 38,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 650, height: 38),
            auxiliaryTopRightArea: CGRect(x: 862, y: 944, width: 650, height: 38),
            backingScaleFactor: 2
        )
        let base = RibbitAgentNotchGeometry.expandedSize(
            for: metrics,
            displayedSessionCount: 3
        )
        let tracked = RibbitAgentNotchGeometry.expandedSize(
            for: metrics,
            displayedSessionCount: 3,
            detailHeight: RibbitAgentNotchGeometry.conversationDetailHeight
        )

        #expect(tracked.height - base.height == 54)
    }

    @Test func notchGlassKeepsCompactBlackAndSeparatesDepthFromOpacity() {
        #expect(
            RibbitGlassCompositing.animatedTintOpacity(
                opacity: 0,
                depth: 1,
                reveal: 0
            ) == 1
        )
        #expect(
            RibbitGlassCompositing.expandedTintOpacity(
                opacity: 0,
                depth: 0
            ) == 1
        )
        #expect(
            RibbitGlassCompositing.expandedTintOpacity(
                opacity: 0,
                depth: 1
            ) == 0
        )
        #expect(
            RibbitGlassCompositing.expandedTintOpacity(
                opacity: 0.35,
                depth: 1
            ) == 0.35
        )
        #expect(
            RibbitGlassCompositing.expandedTintOpacity(
                opacity: 1,
                depth: 1
            ) == 1
        )
    }

    @Test func openNotchKeepsTheCollapsedPixelHeightBlackBeforeFading() {
        let compact = RibbitAgentNotchGeometry.blackoutGradientStops(
            surfaceHeight: 38,
            compactHeight: 38
        )
        #expect(compact.solidEnd == 1)
        #expect(compact.fadeEnd == 1)

        let expanded = RibbitAgentNotchGeometry.blackoutGradientStops(
            surfaceHeight: 208,
            compactHeight: 38
        )
        #expect(expanded.solidEnd == 38.0 / 208.0)
        #expect(expanded.fadeEnd > expanded.solidEnd)
        #expect(expanded.fadeEnd < 1)
    }

    @Test func opacityAndBlurAreIndependentForGlassSurfaces() {
        #expect(RibbitGlassCompositing.sidebarTintOpacity(0) == 0)
        #expect(RibbitGlassCompositing.sidebarEffectIntensity(0) == 0)
        #expect(RibbitGlassCompositing.sidebarTintOpacity(1) == 0.92)
        #expect(RibbitGlassCompositing.sidebarEffectIntensity(1) == 0.70)
        #expect(
            RibbitGlassCompositing.effectIntensity(
                blur: 0,
                reveal: 1
            ) == 0
        )
        #expect(
            RibbitGlassCompositing.effectIntensity(
                blur: 1,
                reveal: 1
            ) == 0.72
        )
    }

    @Test func notchCornerRadiusGrowsIntoAContinuousExpandedSilhouette() {
        #expect(
            RibbitAgentNotchGeometry.surfaceCornerRadius(for: 30)
                == RibbitAgentNotchGeometry.compactSurfaceCornerRadius
        )
        #expect(
            RibbitAgentNotchGeometry.surfaceCornerRadius(for: 138)
                == RibbitAgentNotchGeometry.expandedSurfaceCornerRadius
        )
        let middle = RibbitAgentNotchGeometry.surfaceCornerRadius(for: 84)
        #expect(middle > RibbitAgentNotchGeometry.compactSurfaceCornerRadius)
        #expect(middle < RibbitAgentNotchGeometry.expandedSurfaceCornerRadius)
        #expect(
            RibbitAgentNotchGeometry.topCornerRadius(for: 30)
                == RibbitAgentNotchGeometry.compactTopCornerRadius
        )
        #expect(
            RibbitAgentNotchGeometry.topCornerRadius(for: 138)
                == RibbitAgentNotchGeometry.expandedTopCornerRadius
        )
    }

    @Test func notchGeometryFallsBackBelowTheMenuBarWithoutHardware() {
        let metrics = RibbitNotchScreenMetrics(
            frame: CGRect(x: 100, y: 0, width: 1200, height: 900),
            visibleFrame: CGRect(x: 100, y: 40, width: 1200, height: 820),
            safeAreaTop: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            backingScaleFactor: 2
        )
        #expect(!RibbitAgentNotchGeometry.hasPhysicalNotch(metrics))
        let compact = RibbitAgentNotchGeometry.compactSize(for: metrics)
        #expect(compact == CGSize(width: 112, height: 30))
        let frame = RibbitAgentNotchGeometry.topAnchoredFrame(
            size: compact,
            on: metrics
        )
        #expect(frame.midX == metrics.frame.midX)
        #expect(frame.maxY == metrics.visibleFrame.maxY - 4)
    }

    private func temporaryFixture() throws -> (root: URL, project: URL, registry: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-tests-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("sample-project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        return (root, project, root.appendingPathComponent("support/projects.json"))
    }

    private func notchSession(
        id: String,
        state: RibbitAgentState,
        updatedAt: Date,
        attentionKind: RibbitAttentionKind? = nil
    ) -> RibbitAgentSession {
        RibbitAgentSession(
            id: id,
            providerSessionID: id,
            agent: .codex,
            title: "codex session",
            project: "ribbit",
            activity: state == .paused ? "ready" : "working",
            state: state,
            lastUpdated: updatedAt,
            sourceURL: nil,
            isBridgeSession: true,
            attentionKind: attentionKind,
            attentionDetail: nil,
            focusTarget: .init(surface: .codex)
        )
    }
}
