import AppKit
import SwiftUI

enum TerminalFocusPolicy {
    static func shouldFocus(
        wasActive: Bool,
        isActive: Bool,
        appIsActive: Bool
    ) -> Bool {
        isActive && !wasActive && appIsActive
    }
}

struct TerminalRepresentable: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    @ObservedObject var settings: AppSettings
    var fontScale: CGFloat = 1
    var isActive = true

    final class Coordinator {
        var wasActive = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> RibbitGhosttyView {
        session.applyAppearance(fontSize: resolvedFontSize)
        context.coordinator.wasActive = isActive
        if isActive {
            DispatchQueue.main.async { session.focus() }
        }
        return session.view
    }

    func updateNSView(_ nsView: RibbitGhosttyView, context: Context) {
        session.applyAppearance(fontSize: resolvedFontSize)
        if TerminalFocusPolicy.shouldFocus(
            wasActive: context.coordinator.wasActive,
            isActive: isActive,
            appIsActive: context.environment.controlActiveState == .key
        ) {
            DispatchQueue.main.async { session.focus() }
        }
        context.coordinator.wasActive = isActive
    }

    static func dismantleNSView(
        _ nsView: RibbitGhosttyView,
        coordinator: Coordinator
    ) {
        // TerminalSession owns this persistent Metal-backed surface. SwiftUI
        // may move it between canvas and tab presentation, but dismantling one
        // representable must never tear down the shared terminal.
    }

    private var resolvedFontSize: Double {
        CanvasInteractionMetrics.terminalFontSize(
            base: settings.terminalTextSize,
            zoom: fontScale
        )
    }
}
