import AppKit
import SwiftUI

@MainActor
enum RibbitTheme {
    private static var palette: RibbitPalette { AppSettings.shared.colorScheme.palette }

    static var canvas: Color { Color(nsColor: palette.canvas) }
    static var surface: Color { Color(nsColor: palette.surface) }
    static var raised: Color { Color(nsColor: palette.raised) }
    static var sidebar: Color { Color(nsColor: palette.sidebar) }
    static var rule: Color { Color(nsColor: palette.rule) }
    static var muted: Color { Color(nsColor: palette.muted) }
    static var ink: Color { Color(nsColor: palette.ink) }
    static var accent: Color { Color(nsColor: palette.accent) }
    static let accentDim = Color(nsColor: NSColor(srgbRed: 0.14, green: 0.38, blue: 0.24, alpha: 1))
    static let focus = Color(nsColor: NSColor(srgbRed: 0.48, green: 0.98, blue: 0.66, alpha: 1))
    static let danger = Color(nsColor: NSColor(srgbRed: 0.95, green: 0.38, blue: 0.35, alpha: 1))

    static var nsCanvas: NSColor { palette.canvas }
    static var nsInk: NSColor { palette.ink }
    static var nsAccent: NSColor { palette.accent }

    enum Space {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 40
    }
}

extension TerminalTint {
    @MainActor
    var color: Color {
        switch self {
        case .green: RibbitTheme.accent
        case .blue: Color(nsColor: .systemBlue)
        case .purple: Color(nsColor: .systemPurple)
        case .orange: Color(nsColor: .systemOrange)
        case .red: RibbitTheme.danger
        case .pink: Color(nsColor: .systemPink)
        }
    }
}

struct RibbitLayoutMetrics: Equatable {
    let windowWidth: CGFloat
    var projectTextScale: CGFloat = 1
    var tabTextScale: CGFloat = 1
    var fileTextScale: CGFloat = 1

    private var scale: CGFloat {
        min(1, max(0, (windowWidth - 720) / 720))
    }

    private func fluid(_ minimum: CGFloat, _ maximum: CGFloat) -> CGFloat {
        minimum + (maximum - minimum) * scale
    }

    var projectRailWidth: CGFloat { fluid(128, 216) }
    var inspectorWidth: CGFloat { fluid(136, 224) }
    var sessionRowHeight: CGFloat { fluid(38, 46) * max(1, projectTextScale) }
    var tabBarHeight: CGFloat { fluid(36, 42) * max(1, tabTextScale) }
    var tabMinimumWidth: CGFloat { fluid(96, 128) }
    var tabMaximumWidth: CGFloat { fluid(148, 196) }
    var fileRowHeight: CGFloat { fluid(20, 24) * max(1, fileTextScale) }
    var fileFontSize: CGFloat { fluid(10, 11) * fileTextScale }
    var treeIndent: CGFloat { fluid(8, 12) }

    var isCompact: Bool { windowWidth < 1_000 }
    var isNarrow: Bool { windowWidth < 820 }
    var showsSessionMetadata: Bool { windowWidth >= 900 }
    var showsShortcutHints: Bool { windowWidth >= 1_080 }
    var showsProjectPath: Bool { windowWidth >= 920 }
}

struct RibbitButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? RibbitTheme.ink : RibbitTheme.muted)
            .background(selected ? RibbitTheme.raised : Color.clear)
            .opacity(configuration.isPressed ? 0.66 : 1)
            .contentShape(Rectangle())
    }
}
