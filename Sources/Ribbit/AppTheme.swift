// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4
// Hallmark · component: native glass controls · genre: atmospheric · theme: ribbit
// States: native SwiftUI default · hover · focus · active · disabled · value feedback
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

enum RibbitGlassCompositing {
    static func expandedTintOpacity(opacity: Double, depth: Double) -> Double {
        1 - clamp(depth) * (1 - clamp(opacity))
    }

    static func animatedTintOpacity(
        opacity: Double,
        depth: Double,
        reveal: Double
    ) -> Double {
        let reveal = clamp(reveal)
        return (1 - reveal)
            + reveal * expandedTintOpacity(opacity: opacity, depth: depth)
    }

    static func effectIntensity(blur: Double, reveal: Double) -> Double {
        clamp(blur) * clamp(reveal) * 0.72
    }

    static func sidebarTintOpacity(_ opacity: Double) -> Double {
        clamp(opacity) * 0.92
    }

    static func sidebarEffectIntensity(_ blur: Double) -> Double {
        clamp(blur) * 0.70
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

struct RibbitGlassSurface: View {
    let tint: Color
    let opacity: Double
    let depth: Double
    let blur: Double
    var reveal: Double = 1
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    var body: some View {
        ZStack {
            RibbitVisualEffectView(
                material: material,
                blendingMode: blendingMode,
                intensity: RibbitGlassCompositing.effectIntensity(
                    blur: blur,
                    reveal: reveal
                )
            )
            tint.opacity(
                RibbitGlassCompositing.animatedTintOpacity(
                    opacity: opacity,
                    depth: depth,
                    reveal: reveal
                )
            )
            Color.white.opacity(
                clampedDepth * clampedReveal * 0.035
            )
        }
        .accessibilityHidden(true)
    }

    private var clampedDepth: Double { min(max(depth, 0), 1) }
    private var clampedReveal: Double { min(max(reveal, 0), 1) }
}

/// The production notch surface. Its top band always masks the physical
/// display notch at full black; glass only begins below the compact height.
struct RibbitNotchGlassSurface: View {
    let opacity: Double
    let depth: Double
    let blur: Double
    let compactHeight: CGFloat
    var reveal: Double = 1
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    var body: some View {
        GeometryReader { proxy in
            let stops = RibbitAgentNotchGeometry.blackoutGradientStops(
                surfaceHeight: proxy.size.height,
                compactHeight: compactHeight
            )

            ZStack {
                RibbitGlassSurface(
                    tint: .black,
                    opacity: opacity,
                    depth: depth,
                    blur: blur,
                    reveal: reveal,
                    material: material,
                    blendingMode: blendingMode
                )

                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: stops.solidEnd),
                        .init(color: .clear, location: stops.fadeEnd),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .accessibilityHidden(true)
    }
}

struct RibbitSidebarGlassSurface: View {
    let opacity: Double
    let blur: Double
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    var body: some View {
        ZStack {
            RibbitVisualEffectView(
                material: .hudWindow,
                blendingMode: blendingMode,
                intensity: RibbitGlassCompositing.sidebarEffectIntensity(
                    blur
                )
            )
            Color.black.opacity(
                RibbitGlassCompositing.sidebarTintOpacity(opacity)
            )
            Color.white.opacity(clampedOpacity * 0.018)
        }
        .accessibilityHidden(true)
    }

    private var clampedOpacity: Double {
        min(max(opacity, 0), 1)
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
