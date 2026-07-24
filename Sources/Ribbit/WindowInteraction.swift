import AppKit
import SwiftUI

@MainActor
enum RibbitWindowConfigurator {
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("ribbit-main-window")
    static var reopenMainWindow: (() -> Void)?

    static func configureMainSceneWindows() {
        NSApp.windows
            .filter { window in
                let identifier = window.identifier?.rawValue ?? ""
                return identifier == mainWindowIdentifier.rawValue
                    || identifier.hasPrefix("main-AppWindow")
            }
            .forEach(configure)
    }

    static func configure(_ window: NSWindow) {
        guard !window.styleMask.contains(.nonactivatingPanel) else { return }
        window.identifier = mainWindowIdentifier
        window.title = "ribbit"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert([.fullSizeContentView, .resizable, .miniaturizable, .closable])

        // Canvas nodes provide their own drag gestures. Treating the entire
        // content background as a titlebar makes a node drag move the NSWindow
        // at the same time.
        window.isMovableByWindowBackground = false
        // Ribbit keeps the agent monitor alive after the workspace window is
        // closed. Retain that window so a monitor row or Dock click can reveal
        // the same workspace instead of losing the focus target.
        window.isReleasedWhenClosed = false

        let usesGlass = AppSettings.shared.glassySurfacesEnabled
        window.isOpaque = !usesGlass
        window.backgroundColor = usesGlass ? .clear : RibbitTheme.nsCanvas
        window.minSize = NSSize(width: 720, height: 520)
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.center()
    }

    static func showMainWindow() {
        if let window = NSApp.windows.first(where: {
            $0.identifier == mainWindowIdentifier
                && !$0.styleMask.contains(.nonactivatingPanel)
        }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            reopenMainWindow?()
        }
    }
}

struct RibbitWindowDragRegion: NSViewRepresentable {
    var onActivate: () -> Void

    func makeNSView(context: Context) -> RibbitWindowDragView {
        let view = RibbitWindowDragView()
        view.onActivate = onActivate
        return view
    }

    func updateNSView(_ nsView: RibbitWindowDragView, context: Context) {
        nsView.onActivate = onActivate
    }
}

final class RibbitWindowDragView: NSView {
    var onActivate: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        onActivate?()
        window?.performDrag(with: event)
    }
}
