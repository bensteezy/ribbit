import AppKit
import Foundation
import GhosttyKit

enum RibbitMouseButton: Int, CaseIterable {
    case left = 0
    case right = 1
    case middle = 2
    case four = 3
    case five = 4
    case six = 5
    case seven = 6
    case eight = 7
    case nine = 8
    case ten = 9
    case eleven = 10

    init?(appKitButtonNumber: Int) {
        self.init(rawValue: appKitButtonNumber)
    }

    var ghosttyValue: ghostty_input_mouse_button_e {
        switch self {
        case .left: GHOSTTY_MOUSE_LEFT
        case .right: GHOSTTY_MOUSE_RIGHT
        case .middle: GHOSTTY_MOUSE_MIDDLE
        case .four: GHOSTTY_MOUSE_FOUR
        case .five: GHOSTTY_MOUSE_FIVE
        case .six: GHOSTTY_MOUSE_SIX
        case .seven: GHOSTTY_MOUSE_SEVEN
        case .eight: GHOSTTY_MOUSE_EIGHT
        case .nine: GHOSTTY_MOUSE_NINE
        case .ten: GHOSTTY_MOUSE_TEN
        case .eleven: GHOSTTY_MOUSE_ELEVEN
        }
    }
}

enum AgentTerminalInput {
    static func isReservedRibbitShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([
            .command, .shift, .option, .control
        ])
        guard modifiers == .command || modifiers == [.command, .shift],
              let characters = event.charactersIgnoringModifiers?.lowercased()
        else { return false }
        if modifiers == [.command, .shift] {
            return ["s", "[", "]"].contains(characters)
        }
        return [
            "t", "n", "o", "s", "f", "w", "q", ",", "k",
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "-", "=", "+"
        ].contains(characters)
    }

    static func fallbackReturnSequence(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        enhancedKeyboardEnabled: Bool
    ) -> [UInt8]? {
        guard !enhancedKeyboardEnabled, keyCode == 36 || keyCode == 76 else { return nil }

        let relevantModifiers = modifiers.intersection([.shift, .option, .control, .command])
        if relevantModifiers == .shift {
            return [0x0a]
        }
        if relevantModifiers == .option {
            return [0x1b, 0x0d]
        }
        return nil
    }

    static func fallbackReturnBindingAction(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        enhancedKeyboardEnabled: Bool
    ) -> String? {
        guard let sequence = fallbackReturnSequence(
            keyCode: keyCode,
            modifiers: modifiers,
            enhancedKeyboardEnabled: enhancedKeyboardEnabled
        ) else { return nil }

        return "text:" + sequence
            .map { String(format: "\\x%02x", $0) }
            .joined()
    }

    static func shellEscaped(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    static func insertionText(for values: [String]) -> String {
        guard !values.isEmpty else { return "" }
        return values.map(shellEscaped).joined(separator: " ") + " "
    }
}

struct TerminalInputTestHarness {
    enum KeyAction: Equatable {
        case press
        case repeatKey
        case release
    }

    var isBinding: (NSEvent) -> Bool
    var sendKey: (NSEvent, KeyAction) -> Bool
    var sendBindingAction: (String) -> Bool
    var observeKeyDetails: ((String?, Bool) -> Void)? = nil
    var observeText: ((String) -> Void)? = nil
    var observeBytes: (([UInt8]) -> Void)? = nil
}

enum TerminalDropReader {
    static let supportedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .png,
        .tiff
    ]

    static func insertionText(
        from pasteboard: NSPasteboard,
        attachmentDirectoryURL: URL
    ) throws -> String? {
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if !fileURLs.isEmpty {
            return AgentTerminalInput.insertionText(for: fileURLs.map(\.path))
        }

        if let imageURL = try saveImage(from: pasteboard, in: attachmentDirectoryURL) {
            return AgentTerminalInput.insertionText(for: [imageURL.path])
        }

        if let urlString = pasteboard.string(forType: .URL), !urlString.isEmpty {
            return AgentTerminalInput.insertionText(for: [urlString])
        }
        return nil
    }

    private static func saveImage(from pasteboard: NSPasteboard, in directoryURL: URL) throws -> URL? {
        let pngData: Data?
        if let data = pasteboard.data(forType: .png) {
            pngData = data
        } else if let data = pasteboard.data(forType: .tiff),
                  let representation = NSBitmapImageRep(data: data) {
            pngData = representation.representation(using: .png, properties: [:])
        } else {
            pngData = nil
        }
        guard let pngData else { return nil }

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "drop-\(formatter.string(from: .now))-\(UUID().uuidString.prefix(6).lowercased()).png"
        let destination = directoryURL.appendingPathComponent(filename, isDirectory: false)
        try pngData.write(to: destination, options: .atomic)
        return destination
    }
}
