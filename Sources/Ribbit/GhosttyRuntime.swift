import AppKit
import Foundation
import GhosttyKit

final class GhosttyRuntime: @unchecked Sendable {
    static let shared = GhosttyRuntime()

    private(set) var app: ghostty_app_t!
    private var config: ghostty_config_t!

    private init() {
        Self.configureDevelopmentResources()

        let executable = strdup("ribbit")
        defer { free(executable) }
        var argv: [UnsafeMutablePointer<CChar>?] = [executable, nil]
        let initialized = argv.withUnsafeMutableBufferPointer {
            ghostty_init(1, $0.baseAddress)
        }
        precondition(initialized == GHOSTTY_SUCCESS, "libghostty failed to initialize")

        let savedSize = UserDefaults.standard.object(forKey: "appearance.terminalTextSize") == nil
            ? 14
            : UserDefaults.standard.double(forKey: "appearance.terminalTextSize")
        guard let config = Self.makeConfig(fontSize: savedSize) else {
            preconditionFailure("libghostty failed to create its configuration")
        }
        self.config = config

        var runtimeConfig = ghostty_runtime_config_s(
            userdata: nil,
            supports_selection_clipboard: false,
            wakeup_cb: { userdata in GhosttyRuntime.wakeup(userdata) },
            action_cb: { app, target, action in
                GhosttyRuntime.handleAction(app, target: target, action: action)
            },
            read_clipboard_cb: { userdata, location, state in
                GhosttyRuntime.readClipboard(userdata, location: location, state: state)
            },
            confirm_read_clipboard_cb: { userdata, string, state, request in
                GhosttyRuntime.confirmReadClipboard(userdata, string: string, state: state, request: request)
            },
            write_clipboard_cb: { userdata, location, content, count, confirm in
                GhosttyRuntime.writeClipboard(
                    userdata,
                    location: location,
                    content: content,
                    count: count,
                    confirm: confirm
                )
            },
            close_surface_cb: { userdata, processAlive in
                GhosttyRuntime.closeSurface(userdata, processAlive: processAlive)
            }
        )
        runtimeConfig.userdata = Unmanaged.passUnretained(self).toOpaque()

        guard let app = ghostty_app_new(&runtimeConfig, config) else {
            preconditionFailure("libghostty failed to create its application runtime")
        }
        self.app = app

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            ghostty_app_set_focus(self.app, true)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            ghostty_app_set_focus(self.app, false)
        }
    }

    func update(surface: ghostty_surface_t, fontSize: Double) {
        guard let config = Self.makeConfig(fontSize: fontSize) else { return }
        ghostty_surface_update_config(surface, config)
        ghostty_config_free(config)
    }

    private static func makeConfig(fontSize: Double) -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }
        let schemeName = UserDefaults.standard.string(forKey: "appearance.colorScheme") ?? ""
        let palette = (RibbitColorScheme(rawValue: schemeName) ?? .ribbit).palette
        let text = """
        font-size = \(fontSize)
        background = \(palette.canvas.ghosttyHex)
        foreground = \(palette.ink.ghosttyHex)
        cursor-color = \(palette.accent.ghosttyHex)
        cursor-style = block
        cursor-style-blink = false
        window-padding-x = 8
        window-padding-y = 8
        window-padding-balance = false
        scrollback-limit = 52428800
        copy-on-select = false
        confirm-close-surface = false
        """

        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ribbit", isDirectory: true)
            .appendingPathComponent("ghostty", isDirectory: true)
        let file = directory.appendingPathComponent("ribbit.ghostty")
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try text.write(to: file, atomically: true, encoding: .utf8)
            file.path.withCString { ghostty_config_load_file(config, $0) }
            ghostty_config_finalize(config)
            return config
        } catch {
            ghostty_config_free(config)
            return nil
        }
    }

    private static func configureDevelopmentResources() {
        guard getenv("GHOSTTY_RESOURCES_DIR") == nil else { return }
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resources = sourceRoot
            .appendingPathComponent("Vendor", isDirectory: true)
            .appendingPathComponent("GhosttyResources", isDirectory: true)
            .appendingPathComponent("ghostty", isDirectory: true)
        if FileManager.default.fileExists(atPath: resources.path) {
            setenv("GHOSTTY_RESOURCES_DIR", resources.path, 0)
        }
    }

    private static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let userdata else { return }
        let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(userdata).takeUnretainedValue()
        DispatchQueue.main.async {
            ghostty_app_tick(runtime.app)
        }
    }

    private static func handleAction(
        _ app: ghostty_app_t?,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        guard let view = surfaceView(from: target) else {
            return action.tag == GHOSTTY_ACTION_RENDER
        }

        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            let value = action.action.set_title.title.map(String.init(cString:)) ?? ""
            DispatchQueue.main.async {
                view.terminalTitleChanged(value)
            }
        case GHOSTTY_ACTION_PWD:
            let value = action.action.pwd.pwd.map(String.init(cString:)) ?? ""
            DispatchQueue.main.async {
                view.workingDirectoryChanged(value)
            }
        case GHOSTTY_ACTION_CELL_SIZE:
            let size = CGSize(
                width: Int(action.action.cell_size.width),
                height: Int(action.action.cell_size.height)
            )
            DispatchQueue.main.async {
                view.cellSize = size
            }
        case GHOSTTY_ACTION_RING_BELL:
            DispatchQueue.main.async {
                NSSound.beep()
            }
        case GHOSTTY_ACTION_RENDERER_HEALTH:
            let healthy = action.action.renderer_health == GHOSTTY_RENDERER_HEALTH_HEALTHY
            DispatchQueue.main.async {
                view.rendererHealthy = healthy
            }
        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            DispatchQueue.main.async {
                view.processDidExit()
            }
        case GHOSTTY_ACTION_START_SEARCH:
            let needle = action.action.start_search.needle.map(String.init(cString:)) ?? ""
            DispatchQueue.main.async {
                view.showFind(initialText: needle)
            }
        case GHOSTTY_ACTION_OPEN_URL:
            let raw = action.action.open_url.url.map(String.init(cString:)) ?? ""
            DispatchQueue.main.async {
                let url = URL(string: raw) ?? URL(fileURLWithPath: raw)
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }

        switch action.tag {
        case GHOSTTY_ACTION_NEW_WINDOW,
             GHOSTTY_ACTION_NEW_TAB,
             GHOSTTY_ACTION_NEW_SPLIT,
             GHOSTTY_ACTION_CLOSE_TAB,
             GHOSTTY_ACTION_CLOSE_WINDOW:
            return false
        default:
            return true
        }
    }

    private static func surfaceView(from target: ghostty_target_s) -> RibbitGhosttyView? {
        guard target.tag == GHOSTTY_TARGET_SURFACE,
              let surface = target.target.surface,
              let userdata = ghostty_surface_userdata(surface) else { return nil }
        return Unmanaged<RibbitGhosttyView>.fromOpaque(userdata).takeUnretainedValue()
    }

    private static func surfaceView(from userdata: UnsafeMutableRawPointer?) -> RibbitGhosttyView? {
        guard let userdata else { return nil }
        return Unmanaged<RibbitGhosttyView>.fromOpaque(userdata).takeUnretainedValue()
    }

    private static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        let callbackUserdata = CallbackPointer(userdata)
        let callbackState = CallbackPointer(state)
        return onMainActor {
            guard location == GHOSTTY_CLIPBOARD_STANDARD,
                  let view = surfaceView(from: callbackUserdata.value),
                  let surface = view.surface,
                  let text = NSPasteboard.general.string(forType: .string) else {
                return false
            }
            text.withCString {
                ghostty_surface_complete_clipboard_request(
                    surface,
                    $0,
                    callbackState.value,
                    false
                )
            }
            return true
        }
    }

    private static func confirmReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        string: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        let callbackUserdata = CallbackPointer(userdata)
        let callbackState = CallbackPointer(state)
        onMainActor {
            guard let view = surfaceView(from: callbackUserdata.value),
                  let surface = view.surface else { return }
            "".withCString {
                ghostty_surface_complete_clipboard_request(
                    surface,
                    $0,
                    callbackState.value,
                    false
                )
            }
        }
    }

    private struct CallbackPointer: @unchecked Sendable {
        let value: UnsafeMutableRawPointer?

        init(_ value: UnsafeMutableRawPointer?) {
            self.value = value
        }
    }

    private static func onMainActor<T: Sendable>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(body)
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(body)
        }
    }

    private static func writeClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        count: Int,
        confirm: Bool
    ) {
        guard location == GHOSTTY_CLIPBOARD_STANDARD,
              !confirm,
              let content,
              count > 0 else { return }
        for index in 0..<count {
            guard let mime = content[index].mime,
                  String(cString: mime) == "text/plain",
                  let value = content[index].data else { continue }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(cString: value), forType: .string)
            return
        }
    }

    private static func closeSurface(
        _ userdata: UnsafeMutableRawPointer?,
        processAlive: Bool
    ) {
        guard let view = surfaceView(from: userdata) else { return }
        DispatchQueue.main.async {
            view.processDidExit()
        }
    }
}

private extension NSColor {
    var ghosttyHex: String {
        let color = usingColorSpace(.sRGB) ?? self
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
