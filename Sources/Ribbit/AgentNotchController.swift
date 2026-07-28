import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class RibbitAgentNotchController: NSObject {
    let state: RibbitAgentNotchState

    private let model: AppModel
    private let settings: AppSettings
    private let panel = RibbitAgentNotchPanel()
    private var cancellables = Set<AnyCancellable>()
    private var frameAnimationDisplayLink: CADisplayLink?
    private var frameAnimationStart = CGRect.zero
    private var frameAnimationTarget = CGRect.zero
    private var frameAnimationScreen: NSScreen?
    private var frameAnimationStartedAt: CFTimeInterval = 0
    private var frameAnimationDuration: CFTimeInterval = 0
    private var frameAnimationIsExpanding = false
    private var frameAnimationSurfaceStart: CGFloat = 0
    private var frameAnimationSurfaceTarget: CGFloat = 0
    private weak var lastTargetScreen: NSScreen?
    private var isStarted = false

    init(model: AppModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        state = RibbitAgentNotchState(
            monitor: model.agentMonitor,
            settings: settings,
            focusSession: { [weak model] session in
                model?.focusAgentSession(session)
            }
        )
        super.init()

        let hostingView = NSHostingView(
            rootView: RibbitAgentNotchRootView(state: state)
        )
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        hostingView.layer?.allowsEdgeAntialiasing = true
        hostingView.layer?.drawsAsynchronously = true
        hostingView.layer?.allowsGroupOpacity = false
        panel.contentView = hostingView
        panel.contentView?.autoresizingMask = [.width, .height]
        panel.acceptsMouseMovedEvents = true
        panel.onEscape = { [weak state] in
            state?.collapse()
        }

        state.$presentation
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resizeAndPresent(animated: true)
            }
            .store(in: &cancellables)

        state.$projection
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resizeAndPresent(animated: true)
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.resizeAndPresent(animated: false)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.resizeAndPresent(animated: false)
        }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] notification in
            guard let self,
                  self.settings.notchDisplayTarget == .followRibbit,
                  let window = notification.object as? NSWindow,
                  window !== self.panel else { return }
            self.resizeAndPresent(animated: false)
        }
        .store(in: &cancellables)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        resizeAndPresent(animated: false)
    }

    func stop() {
        cancelFrameAnimation()
        state.stop()
        panel.orderOut(nil)
        cancellables.removeAll()
        isStarted = false
    }

    private func resizeAndPresent(animated: Bool) {
        guard isStarted, settings.notchMonitorEnabled else {
            cancelFrameAnimation()
            panel.orderOut(nil)
            return
        }
        guard !shouldHideForRibbitFullScreen(),
              let screen = targetScreen() else {
            cancelFrameAnimation()
            panel.orderOut(nil)
            return
        }

        lastTargetScreen = screen
        let metrics = RibbitNotchScreenMetrics(screen: screen)
        state.updateViewMetrics(RibbitAgentNotchViewMetrics(
            hasPhysicalNotch: RibbitAgentNotchGeometry.hasPhysicalNotch(metrics),
            hardwareNotchWidth: RibbitAgentNotchGeometry.hardwareNotchWidth(metrics),
            headerHeight: RibbitAgentNotchGeometry.hasPhysicalNotch(metrics)
                ? metrics.safeAreaTop
                : RibbitAgentNotchGeometry.fallbackCompactSize.height
        ))
        let size = state.isExpanded
            ? RibbitAgentNotchGeometry.expandedSize(
                for: metrics,
                displayedSessionCount: state.projection.displayedSessions.count,
                detailHeight: state.detailPanelHeight,
                contentWidth: settings.notchExpandedWidth.contentWidth
            )
            : RibbitAgentNotchGeometry.compactSize(for: metrics)
        let targetFrame = RibbitAgentNotchGeometry.topAnchoredFrame(
            size: size,
            on: metrics
        )
        let physicalNotch = RibbitAgentNotchGeometry.hasPhysicalNotch(metrics)
        panel.hasShadow = !physicalNotch

        if animated,
           panel.hasPresented,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            animatePanel(to: targetFrame, on: screen)
        } else {
            cancelFrameAnimation()
            apply(targetFrame)
            state.updateExpansionProgress(state.isExpanded ? 1 : 0)
        }
        panel.hasPresented = true
        panel.orderFrontRegardless()
    }

    private func targetScreen() -> NSScreen? {
        switch settings.notchDisplayTarget {
        case .builtIn:
            return NSScreen.screens.first(where: {
                let metrics = RibbitNotchScreenMetrics(screen: $0)
                return RibbitAgentNotchGeometry.hasPhysicalNotch(metrics)
            }) ?? NSScreen.main ?? NSScreen.screens.first

        case .main:
            return NSScreen.main ?? NSScreen.screens.first

        case .followRibbit:
            if let key = NSApp.keyWindow, key !== panel, let screen = key.screen {
                return screen
            }
            if let main = NSApp.mainWindow, main !== panel, let screen = main.screen {
                return screen
            }
            return lastTargetScreen ?? NSScreen.main ?? NSScreen.screens.first
        }
    }

    private func shouldHideForRibbitFullScreen() -> Bool {
        guard settings.notchHideInFullScreen else { return false }
        return NSApp.windows.contains {
            $0 !== panel
                && $0.isVisible
                && $0.styleMask.contains(.fullScreen)
        }
    }

    private func animatePanel(to targetFrame: CGRect, on screen: NSScreen) {
        if frameAnimationDisplayLink != nil,
           frameAnimationTarget == targetFrame {
            return
        }

        let startFrame = panel.frame
        guard startFrame != targetFrame else { return }
        cancelFrameAnimation()
        frameAnimationStart = startFrame
        frameAnimationTarget = targetFrame
        frameAnimationScreen = screen
        frameAnimationStartedAt = CACurrentMediaTime()
        frameAnimationIsExpanding = targetFrame.height > startFrame.height
        frameAnimationSurfaceStart = state.expansionProgress
        frameAnimationSurfaceTarget = state.isExpanded ? 1 : 0
        frameAnimationDuration = frameAnimationIsExpanding ? 0.32 : 0.24

        let displayLink = screen.displayLink(
            target: self,
            selector: #selector(stepFrameAnimation(_:))
        )
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60,
            maximum: Float(screen.maximumFramesPerSecond),
            preferred: Float(screen.maximumFramesPerSecond)
        )
        frameAnimationDisplayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    @objc private func stepFrameAnimation(_ displayLink: CADisplayLink) {
        guard displayLink === frameAnimationDisplayLink,
              let screen = frameAnimationScreen else {
            displayLink.invalidate()
            return
        }

        let elapsed = CACurrentMediaTime() - frameAnimationStartedAt
        let linear = min(max(elapsed / frameAnimationDuration, 0), 1)
        let eased = frameAnimationIsExpanding
            ? Self.fluidExpansionProgress(CGFloat(linear))
            : Self.easedProgress(CGFloat(linear))
        let size = CGSize(
            width: frameAnimationStart.width
                + (frameAnimationTarget.width - frameAnimationStart.width) * eased,
            height: frameAnimationStart.height
                + (frameAnimationTarget.height - frameAnimationStart.height) * eased
        )
        let metrics = RibbitNotchScreenMetrics(screen: screen)
        apply(RibbitAgentNotchGeometry.topAnchoredFrame(size: size, on: metrics))
        state.updateExpansionProgress(
            frameAnimationSurfaceStart
                + (frameAnimationSurfaceTarget - frameAnimationSurfaceStart) * eased
        )

        if linear >= 1 {
            apply(frameAnimationTarget)
            state.updateExpansionProgress(frameAnimationSurfaceTarget)
            cancelFrameAnimation()
        }
    }

    private func cancelFrameAnimation() {
        frameAnimationDisplayLink?.invalidate()
        frameAnimationDisplayLink = nil
        frameAnimationScreen = nil
        frameAnimationIsExpanding = false
    }

    private func apply(_ frame: CGRect) {
        panel.setFrame(frame, display: true, animate: false)
    }

    nonisolated static func fluidExpansionProgress(
        _ linearProgress: CGFloat
    ) -> CGFloat {
        let progress = min(max(linearProgress, 0), 1)
        let response: CGFloat = 9
        let raw = 1 - exp(-response * progress) * (1 + response * progress)
        let end = 1 - exp(-response) * (1 + response)
        return min(max(raw / end, 0), 1)
    }

    nonisolated static func easedProgress(_ linearProgress: CGFloat) -> CGFloat {
        let progress = min(max(linearProgress, 0), 1)
        var lower: CGFloat = 0
        var upper: CGFloat = 1
        var parameter = progress
        for _ in 0..<10 {
            let x = cubicBezier(parameter, control1: 0.40, control2: 0.20)
            if x < progress {
                lower = parameter
            } else {
                upper = parameter
            }
            parameter = (lower + upper) / 2
        }
        return cubicBezier(parameter, control1: 0.0, control2: 1.0)
    }

    nonisolated private static func cubicBezier(
        _ parameter: CGFloat,
        control1: CGFloat,
        control2: CGFloat
    ) -> CGFloat {
        let inverse = 1 - parameter
        return 3 * inverse * inverse * parameter * control1
            + 3 * inverse * parameter * parameter * control2
            + parameter * parameter * parameter
    }
}

private final class RibbitAgentNotchPanel: NSPanel {
    var hasPresented = false
    var onEscape: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }
        onEscape?()
    }
}
