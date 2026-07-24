import AppKit
import Foundation
import GhosttyKit

final class RibbitGhosttyView: NSView, @preconcurrency NSTextInputClient {
    private(set) var surface: ghostty_surface_t?
    var attachmentDirectoryURL = TerminalSession.defaultSupportURL
        .appendingPathComponent("attachments", isDirectory: true)
        .appendingPathComponent("base", isDirectory: true)
    var onTitleChanged: ((String) -> Void)?
    var onDirectoryChanged: ((String) -> Void)?
    var onProcessExit: (() -> Void)?
    var onActivated: (() -> Void)?
    var font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    var cellSize = CGSize.zero
    var rendererHealthy = true

    private var findField: NSSearchField?
    private var trackingAreaToken: NSTrackingArea?
    private var localKeyUpMonitor: Any?
    private var inputTestHarness: TerminalInputTestHarness?
    private var fallbackReturnKeyCodes = Set<UInt16>()
    private var markedText = NSMutableAttributedString(string: "")
    private var keyTextAccumulator: [String]?
    private var appliedFontSize: Double?
    private var appliedColorSchemeName: String?
    private var lastSurfaceScale: Double?
    private var lastSurfacePixelSize: CGSize?
    private var presentationNeedsRefresh = true
    private(set) var presentationRefreshCount = 0
    var enhancedKeyboardInputEnabled = false

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { false }

    init(
        frame: NSRect = NSRect(x: 0, y: 0, width: 800, height: 600),
        directory: URL,
        fontSize: Double,
        environment: [String: String],
        command: String? = nil
    ) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = RibbitTheme.nsCanvas.cgColor
        registerForDraggedTypes(TerminalDropReader.supportedTypes)
        font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        createSurface(
            directory: directory,
            fontSize: fontSize,
            environment: environment,
            command: command
        )
        appliedFontSize = fontSize
        appliedColorSchemeName = UserDefaults.standard.string(
            forKey: "appearance.colorScheme"
        )
    }

    init(
        frame: NSRect = NSRect(x: 0, y: 0, width: 800, height: 600),
        inputTestHarness: TerminalInputTestHarness
    ) {
        self.inputTestHarness = inputTestHarness
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func terminate() {
        guard let surface else { return }
        ghostty_surface_free(surface)
        self.surface = nil
    }

    func updateAppearance(fontSize: Double) {
        let colorSchemeName = UserDefaults.standard.string(
            forKey: "appearance.colorScheme"
        )
        guard appliedFontSize != fontSize
                || appliedColorSchemeName != colorSchemeName
        else { return }
        appliedFontSize = fontSize
        appliedColorSchemeName = colorSchemeName
        font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        layer?.backgroundColor = RibbitTheme.nsCanvas.cgColor
        guard let surface else { return }
        GhosttyRuntime.shared.update(surface: surface, fontSize: fontSize)
    }

    func refreshAfterMount(force: Bool = false) {
        let geometryChanged = updateSurfaceGeometry()
        guard let surface else { return }
        guard force || geometryChanged || presentationNeedsRefresh else {
            return
        }
        presentationNeedsRefresh = false
        presentationRefreshCount += 1
        ghostty_surface_set_focus(surface, window?.firstResponder === self)
        ghostty_surface_refresh(surface)
        needsDisplay = true
    }

    func terminalTitleChanged(_ title: String) {
        onTitleChanged?(title)
    }

    func workingDirectoryChanged(_ directory: String) {
        onDirectoryChanged?(directory)
    }

    func processDidExit() {
        onProcessExit?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLocalKeyUpMonitor()
        updateSurfaceGeometry()
        guard window != nil else {
            presentationNeedsRefresh = true
            return
        }
        refreshAfterMount()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateSurfaceGeometry()
    }

    override func layout() {
        super.layout()
        updateSurfaceGeometry()
        if let findField {
            findField.frame = NSRect(
                x: max(8, bounds.width - 256),
                y: max(8, bounds.height - 38),
                width: min(240, max(120, bounds.width - 16)),
                height: 28
            )
        }
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        if let surface { ghostty_surface_set_focus(surface, true) }
        return true
    }

    override func resignFirstResponder() -> Bool {
        if let surface { ghostty_surface_set_focus(surface, false) }
        return super.resignFirstResponder()
    }

    override func updateTrackingAreas() {
        if let trackingAreaToken { removeTrackingArea(trackingAreaToken) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        trackingAreaToken = area
        super.updateTrackingAreas()
    }

    override func keyDown(with event: NSEvent) {
        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        if !hasMarkedText(), handleModifiedReturnFallback(event, action: action) { return }

        let markedTextBefore = hasMarkedText()
        let translationEvent = translatedEvent(for: event)
        keyTextAccumulator = []
        interpretKeyEvents([translationEvent])
        let accumulatedText = keyTextAccumulator ?? []
        keyTextAccumulator = nil

        syncPreedit(clearIfNeeded: markedTextBefore)
        let composing = hasMarkedText() || markedTextBefore

        if !accumulatedText.isEmpty {
            for text in accumulatedText where !Self.shouldSuppressComposingControlInput(
                text,
                composing: composing
            ) {
                _ = sendKey(
                    event,
                    action: action,
                    textOverride: text,
                    composing: false
                )
            }
            return
        }

        guard !Self.shouldSuppressComposingControlInput(
            event.characters,
            composing: composing
        ) else { return }
        _ = sendKey(event, action: action, composing: composing)
    }

    override func keyUp(with event: NSEvent) {
        if fallbackReturnKeyCodes.remove(event.keyCode) != nil { return }
        _ = sendKey(event, action: GHOSTTY_ACTION_RELEASE)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard inputTestHarness != nil || window?.firstResponder === self else { return false }

        // Ribbit's documented application commands own their chords even when
        // Ghostty has a default window/tab binding for the same key. Unknown
        // Command chords still ask Ghostty first so user terminal bindings work.
        if AgentTerminalInput.isReservedRibbitShortcut(event) {
            return false
        }

        // A configured Ghostty binding gets first refusal. This is important
        // for user-defined bindings and Ghostty's performable/unconsumed
        // behavior: AppKit must not run a Ribbit menu command as well.
        if isTerminalBinding(event) {
            keyDown(with: event)
            return true
        }

        // Command shortcuts that Ghostty doesn't own continue through the
        // responder chain to Ribbit's SwiftUI commands and standard AppKit
        // copy/paste actions.
        if event.modifierFlags.contains(.command) { return false }

        // AppKit may offer control chords as key equivalents before keyDown.
        // They are terminal input unless Ghostty consumed them above.
        if event.modifierFlags.contains(.control) {
            keyDown(with: event)
            return true
        }

        return false
    }

    override func flagsChanged(with event: NSEvent) {
        guard Self.modifierMask(for: event.keyCode) != nil else {
            super.flagsChanged(with: event)
            return
        }
        _ = sendKey(
            event,
            action: Self.isModifierPressed(event)
                ? GHOSTTY_ACTION_PRESS
                : GHOSTTY_ACTION_RELEASE
        )
    }

    @objc func copy(_ sender: Any?) {
        guard let surface else { return }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let pointer = text.text else { return }
        let value = String(
            data: Data(bytes: pointer, count: Int(text.text_len)),
            encoding: .utf8
        ) ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    @objc func paste(_ sender: Any?) {
        sendBindingAction("paste_from_clipboard")
    }

    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        hasMarkedText()
            ? NSRange(location: 0, length: markedText.length)
            : NSRange(location: NSNotFound, length: 0)
    }

    func selectedRange() -> NSRange {
        guard let surface else {
            return NSRange(location: NSNotFound, length: 0)
        }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else {
            return NSRange(location: NSNotFound, length: 0)
        }
        defer { ghostty_surface_free_text(surface, &text) }
        return NSRange(location: Int(text.offset_start), length: Int(text.offset_len))
    }

    func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        switch string {
        case let attributed as NSAttributedString:
            markedText = NSMutableAttributedString(attributedString: attributed)
        case let value as String:
            markedText = NSMutableAttributedString(string: value)
        default:
            return
        }
        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func unmarkText() {
        guard hasMarkedText() else { return }
        markedText.mutableString.setString("")
        syncPreedit()
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSAttributedString? {
        guard range.length > 0, let surface else { return nil }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text),
              let pointer = text.text
        else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        actualRange?.pointee = selectedRange()
        return NSAttributedString(
            string: String(
                data: Data(bytes: pointer, count: Int(text.text_len)),
                encoding: .utf8
            ) ?? "",
            attributes: [.font: font]
        )
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    func firstRect(
        forCharacterRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSRect {
        guard let surface else {
            return window?.convertToScreen(convert(bounds, to: nil))
                ?? convert(bounds, to: nil)
        }

        var x = 0.0
        var y = 0.0
        var width: Double = max(1, Double(cellSize.width))
        var height: Double = max(Double(font.pointSize), Double(cellSize.height))
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)
        if range.length == 0 {
            width = 0
        }
        let viewRect = NSRect(
            x: x,
            y: bounds.height - y,
            width: width,
            height: height
        )
        let windowRect = convert(viewRect, to: nil)
        actualRange?.pointee = range
        return window?.convertToScreen(windowRect) ?? windowRect
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard inputTestHarness != nil || NSApp?.currentEvent != nil else { return }
        let value: String
        switch string {
        case let attributed as NSAttributedString:
            value = attributed.string
        case let text as String:
            value = text
        default:
            return
        }

        unmarkText()
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(value)
        } else {
            sendText(value)
        }
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(moveToBeginningOfDocument(_:)):
            sendBindingAction("scroll_to_top")
        case #selector(moveToEndOfDocument(_:)):
            sendBindingAction("scroll_to_bottom")
        default:
            break
        }
    }

    func showFind(initialText: String = "") {
        if let findField {
            if !initialText.isEmpty { findField.stringValue = initialText }
            window?.makeFirstResponder(findField)
            return
        }
        let field = NSSearchField(frame: .zero)
        field.placeholderString = "find"
        field.stringValue = initialText
        field.target = self
        field.action = #selector(findChanged(_:))
        field.sendsSearchStringImmediately = true
        field.bezelStyle = .roundedBezel
        addSubview(field)
        findField = field
        needsLayout = true
        window?.makeFirstResponder(field)
    }

    func clearScreen() {
        sendBindingAction("clear_screen")
    }

    func readJournalText() -> String {
        guard let surface else { return "" }
        let topLeft = ghostty_point_s(
            tag: GHOSTTY_POINT_SURFACE,
            coord: GHOSTTY_POINT_COORD_TOP_LEFT,
            x: 0,
            y: 0
        )
        let bottomRight = ghostty_point_s(
            tag: GHOSTTY_POINT_SURFACE,
            coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
            x: 0,
            y: 0
        )
        let selection = ghostty_selection_s(
            top_left: topLeft,
            bottom_right: bottomRight,
            rectangle: false
        )
        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text), let pointer = text.text else {
            return ""
        }
        defer { ghostty_surface_free_text(surface, &text) }
        return String(
            data: Data(bytes: pointer, count: Int(text.text_len)),
            encoding: .utf8
        ) ?? ""
    }

    override func mouseDown(with event: NSEvent) {
        onActivated?()
        window?.makeFirstResponder(self)
        sendMousePosition(event)
        if let surface {
            _ = ghostty_surface_mouse_button(
                surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, Self.modifiers(event.modifierFlags)
            )
        }
    }

    override func mouseUp(with event: NSEvent) {
        sendMousePosition(event)
        if let surface {
            _ = ghostty_surface_mouse_button(
                surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, Self.modifiers(event.modifierFlags)
            )
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onActivated?()
        window?.makeFirstResponder(self)
        sendMousePosition(event)
        if let surface,
           ghostty_surface_mouse_button(
            surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, Self.modifiers(event.modifierFlags)
           ) { return }
        super.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        sendMousePosition(event)
        if let surface,
           ghostty_surface_mouse_button(
            surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, Self.modifiers(event.modifierFlags)
           ) { return }
        super.rightMouseUp(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        onActivated?()
        window?.makeFirstResponder(self)
        sendMousePosition(event)
        guard let surface,
              let button = RibbitMouseButton(
                  appKitButtonNumber: event.buttonNumber
              )?.ghosttyValue,
              ghostty_surface_mouse_button(
                  surface,
                  GHOSTTY_MOUSE_PRESS,
                  button,
                  Self.modifiers(event.modifierFlags)
              )
        else {
            super.otherMouseDown(with: event)
            return
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        sendMousePosition(event)
        guard let surface,
              let button = RibbitMouseButton(
                  appKitButtonNumber: event.buttonNumber
              )?.ghosttyValue,
              ghostty_surface_mouse_button(
                  surface,
                  GHOSTTY_MOUSE_RELEASE,
                  button,
                  Self.modifiers(event.modifierFlags)
              )
        else {
            super.otherMouseUp(with: event)
            return
        }
    }

    override func mouseMoved(with event: NSEvent) { sendMousePosition(event) }
    override func mouseDragged(with event: NSEvent) { sendMousePosition(event) }
    override func rightMouseDragged(with event: NSEvent) { sendMousePosition(event) }
    override func otherMouseDragged(with event: NSEvent) { sendMousePosition(event) }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        let multiplier = event.hasPreciseScrollingDeltas ? 2.0 : 1.0
        var scrollModifiers: ghostty_input_scroll_mods_t = 0
        if event.hasPreciseScrollingDeltas { scrollModifiers |= 1 }
        ghostty_surface_mouse_scroll(
            surface,
            event.scrollingDeltaX * multiplier,
            event.scrollingDeltaY * multiplier,
            scrollModifiers
        )
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.availableType(from: TerminalDropReader.supportedTypes) == nil ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        do {
            guard let text = try TerminalDropReader.insertionText(
                from: sender.draggingPasteboard,
                attachmentDirectoryURL: attachmentDirectoryURL
            ) else { return false }
            sendText(text)
            window?.makeFirstResponder(self)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    @objc private func findChanged(_ sender: NSSearchField) {
        sendBindingAction("search:\(sender.stringValue)")
    }

    private func createSurface(
        directory: URL,
        fontSize: Double,
        environment: [String: String],
        command: String?
    ) {
        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(self).toOpaque())
        )
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.scale_factor = Double(
            window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        )
        config.font_size = Float(fontSize)

        let workingDirectory = strdup(directory.path)
        config.working_directory = UnsafePointer(workingDirectory)
        let launchCommand: UnsafeMutablePointer<CChar>? = command.map { strdup($0)! }
        config.command = launchCommand.map { UnsafePointer<CChar>($0) }
        var allocations: [UnsafeMutablePointer<CChar>] = []
        var environmentValues: [ghostty_env_var_s] = environment.map { key, value in
            let cKey = strdup(key)!
            let cValue = strdup(value)!
            allocations.append(cKey)
            allocations.append(cValue)
            return ghostty_env_var_s(key: UnsafePointer(cKey), value: UnsafePointer(cValue))
        }
        defer {
            free(workingDirectory)
            free(launchCommand)
            allocations.forEach { free($0) }
        }

        surface = environmentValues.withUnsafeMutableBufferPointer { buffer in
            config.env_vars = buffer.baseAddress
            config.env_var_count = buffer.count
            return ghostty_surface_new(GhosttyRuntime.shared.app, &config)
        }
        updateSurfaceGeometry()
    }

    @discardableResult
    private func sendKey(
        _ event: NSEvent,
        action: ghostty_input_action_e,
        textOverride: String? = nil,
        composing: Bool = false
    ) -> Bool {
        if let inputTestHarness {
            inputTestHarness.observeKeyDetails?(textOverride, composing)
            return inputTestHarness.sendKey(event, Self.testAction(action))
        }
        guard let surface else { return false }
        var key = ghostty_input_key_s()
        key.action = action
        key.mods = Self.modifiers(event.modifierFlags)
        let translationMods = ghostty_surface_key_translation_mods(surface, key.mods)
        key.consumed_mods = Self.removingControlAndSuper(from: translationMods)
        key.keycode = UInt32(event.keyCode)
        key.composing = composing
        if let value = event.characters(byApplyingModifiers: []),
           value.unicodeScalars.count == 1 {
            key.unshifted_codepoint = value.unicodeScalars.first?.value ?? 0
        }

        let translationFlags = Self.eventModifiers(translationMods)
        let text = textOverride ?? event.ghosttyCharacters(applying: translationFlags)
        guard action != GHOSTTY_ACTION_RELEASE, let text else {
            return ghostty_surface_key(surface, key)
        }
        return text.withCString {
            key.text = $0
            return ghostty_surface_key(surface, key)
        }
    }

    func sendText(_ text: String) {
        if let inputTestHarness {
            inputTestHarness.observeText?(text)
            return
        }
        guard let surface else { return }
        text.withCString { ghostty_surface_text(surface, $0, UInt(text.utf8.count)) }
    }

    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if hasMarkedText() {
            let value = markedText.string
            value.withCString {
                ghostty_surface_preedit(surface, $0, UInt(value.utf8.count))
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    @discardableResult
    private func sendBindingAction(_ action: String) -> Bool {
        if let inputTestHarness {
            return inputTestHarness.sendBindingAction(action)
        }
        guard let surface else { return false }
        return action.withCString {
            ghostty_surface_binding_action(surface, $0, UInt(action.utf8.count))
        }
    }

    private func isTerminalBinding(_ event: NSEvent) -> Bool {
        if let inputTestHarness {
            return inputTestHarness.isBinding(event)
        }
        guard let surface else { return false }

        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_PRESS
        key.mods = Self.modifiers(event.modifierFlags)
        key.consumed_mods = Self.removingControlAndSuper(
            from: ghostty_surface_key_translation_mods(surface, key.mods)
        )
        key.keycode = UInt32(event.keyCode)
        key.composing = false
        if let value = event.characters(byApplyingModifiers: []),
           value.unicodeScalars.count == 1 {
            key.unshifted_codepoint = value.unicodeScalars.first?.value ?? 0
        }

        var flags = ghostty_binding_flags_e(0)
        guard let text = event.ghosttyCharacters else {
            return ghostty_surface_key_is_binding(surface, key, &flags)
        }
        return text.withCString {
            key.text = $0
            return ghostty_surface_key_is_binding(surface, key, &flags)
        }
    }

    private func handleModifiedReturnFallback(
        _ event: NSEvent,
        action: ghostty_input_action_e
    ) -> Bool {
        guard action == GHOSTTY_ACTION_PRESS || action == GHOSTTY_ACTION_REPEAT,
              !isTerminalBinding(event),
              let bytes = AgentTerminalInput.fallbackReturnSequence(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                enhancedKeyboardEnabled: enhancedKeyboardInputEnabled
              )
        else { return false }

        sendRawBytes(bytes)
        fallbackReturnKeyCodes.insert(event.keyCode)
        return true
    }

    private func sendRawBytes(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        if let inputTestHarness {
            inputTestHarness.observeBytes?(bytes)
            return
        }
        guard let surface else { return }
        bytes.withUnsafeBytes { buffer in
            guard let address = buffer.baseAddress else { return }
            ghostty_surface_text(
                surface,
                address.assumingMemoryBound(to: CChar.self),
                UInt(buffer.count)
            )
        }
    }

    private func translatedEvent(for event: NSEvent) -> NSEvent {
        guard let surface else { return event }
        let translated = ghostty_surface_key_translation_mods(
            surface,
            Self.modifiers(event.modifierFlags)
        )
        let translatedFlags = Self.eventModifiers(translated)
        var finalFlags = event.modifierFlags
        for flag in [
            NSEvent.ModifierFlags.shift,
            .control,
            .option,
            .command
        ] {
            if translatedFlags.contains(flag) {
                finalFlags.insert(flag)
            } else {
                finalFlags.remove(flag)
            }
        }
        guard finalFlags != event.modifierFlags else { return event }
        return NSEvent.keyEvent(
            with: event.type,
            location: event.locationInWindow,
            modifierFlags: finalFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: event.characters(byApplyingModifiers: finalFlags) ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            isARepeat: event.isARepeat,
            keyCode: event.keyCode
        ) ?? event
    }

    private static func shouldSuppressComposingControlInput(
        _ text: String?,
        composing: Bool
    ) -> Bool {
        guard composing, let text, text.utf8.count == 1,
              let byte = text.utf8.first
        else { return false }
        return byte < 0x20 || byte == 0x7f
    }

    private func updateLocalKeyUpMonitor() {
        if let localKeyUpMonitor {
            NSEvent.removeMonitor(localKeyUpMonitor)
            self.localKeyUpMonitor = nil
        }
        guard window != nil else { return }

        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) {
            [weak self] event in
            guard let self,
                  event.modifierFlags.contains(.command),
                  event.window === self.window,
                  self.window?.firstResponder === self
            else { return event }

            self.keyUp(with: event)
            return nil
        }
    }

    private func sendMousePosition(_ event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(
            surface,
            point.x,
            bounds.height - point.y,
            Self.modifiers(event.modifierFlags)
        )
    }

    @discardableResult
    private func updateSurfaceGeometry() -> Bool {
        guard let surface, bounds.width > 0, bounds.height > 0 else {
            return false
        }
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        let size = convertToBacking(bounds).size
        let pixelSize = CGSize(
            width: max(1, size.width.rounded()),
            height: max(1, size.height.rounded())
        )
        var changed = false

        if lastSurfaceScale != scale {
            ghostty_surface_set_content_scale(surface, scale, scale)
            lastSurfaceScale = scale
            changed = true
        }
        if lastSurfacePixelSize != pixelSize {
            ghostty_surface_set_size(
                surface,
                UInt32(pixelSize.width),
                UInt32(pixelSize.height)
            )
            lastSurfacePixelSize = pixelSize
            changed = true
        }
        return changed
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { raw |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { raw |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { raw |= GHOSTTY_MODS_CAPS.rawValue }
        if flags.rawValue & UInt(NX_DEVICERSHIFTKEYMASK) != 0 {
            raw |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue
        }
        if flags.rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0 {
            raw |= GHOSTTY_MODS_CTRL_RIGHT.rawValue
        }
        if flags.rawValue & UInt(NX_DEVICERALTKEYMASK) != 0 {
            raw |= GHOSTTY_MODS_ALT_RIGHT.rawValue
        }
        if flags.rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0 {
            raw |= GHOSTTY_MODS_SUPER_RIGHT.rawValue
        }
        return ghostty_input_mods_e(raw)
    }

    private static func eventModifiers(_ modifiers: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if modifiers.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { result.insert(.shift) }
        if modifiers.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { result.insert(.control) }
        if modifiers.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { result.insert(.option) }
        if modifiers.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { result.insert(.command) }
        if modifiers.rawValue & GHOSTTY_MODS_CAPS.rawValue != 0 { result.insert(.capsLock) }
        return result
    }

    private static func removingControlAndSuper(
        from modifiers: ghostty_input_mods_e
    ) -> ghostty_input_mods_e {
        let removed = GHOSTTY_MODS_CTRL.rawValue
            | GHOSTTY_MODS_SUPER.rawValue
            | GHOSTTY_MODS_CTRL_RIGHT.rawValue
            | GHOSTTY_MODS_SUPER_RIGHT.rawValue
        return ghostty_input_mods_e(modifiers.rawValue & ~removed)
    }

    private static func modifierMask(for keyCode: UInt16) -> UInt32? {
        switch keyCode {
        case 0x39: GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: GHOSTTY_MODS_SUPER.rawValue
        default: nil
        }
    }

    private static func isModifierPressed(_ event: NSEvent) -> Bool {
        guard let mask = modifierMask(for: event.keyCode) else { return false }
        let mods = modifiers(event.modifierFlags)
        guard mods.rawValue & mask != 0 else { return false }

        return switch event.keyCode {
        case 0x3C: event.modifierFlags.rawValue & UInt(NX_DEVICERSHIFTKEYMASK) != 0
        case 0x3E: event.modifierFlags.rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0
        case 0x3D: event.modifierFlags.rawValue & UInt(NX_DEVICERALTKEYMASK) != 0
        case 0x36: event.modifierFlags.rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0
        default: true
        }
    }

    private static func testAction(
        _ action: ghostty_input_action_e
    ) -> TerminalInputTestHarness.KeyAction {
        switch action {
        case GHOSTTY_ACTION_REPEAT: .repeatKey
        case GHOSTTY_ACTION_RELEASE: .release
        default: .press
        }
    }
}

private extension NSEvent {
    var ghosttyCharacters: String? {
        ghosttyCharacters(applying: modifierFlags)
    }

    func ghosttyCharacters(applying modifiers: NSEvent.ModifierFlags) -> String? {
        guard let characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifiers.subtracting(.control))
            }
            if (0xF700...0xF8FF).contains(scalar.value) { return nil }
        }
        return self.characters(byApplyingModifiers: modifiers) ?? characters
    }
}
