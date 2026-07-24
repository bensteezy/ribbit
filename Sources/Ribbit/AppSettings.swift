import AppKit
import Combine
import SwiftUI

enum RibbitColorScheme: String, CaseIterable, Identifiable {
    case ribbit
    case midnight
    case graphite

    var id: String { rawValue }

    var palette: RibbitPalette {
        switch self {
        case .ribbit:
            RibbitPalette(
                canvas: NSColor(srgbRed: 0.047, green: 0.055, blue: 0.071, alpha: 1),
                surface: NSColor(srgbRed: 0.066, green: 0.074, blue: 0.092, alpha: 1),
                raised: NSColor(srgbRed: 0.078, green: 0.086, blue: 0.105, alpha: 1),
                sidebar: NSColor(srgbRed: 0.066, green: 0.072, blue: 0.091, alpha: 0.90),
                rule: NSColor(srgbRed: 0.15, green: 0.17, blue: 0.20, alpha: 1),
                muted: NSColor(srgbRed: 0.57, green: 0.59, blue: 0.64, alpha: 1),
                ink: NSColor(srgbRed: 0.92, green: 0.94, blue: 0.93, alpha: 1),
                accent: NSColor(srgbRed: 0.20, green: 0.92, blue: 0.47, alpha: 1)
            )
        case .midnight:
            RibbitPalette(
                canvas: NSColor(srgbRed: 0.025, green: 0.043, blue: 0.075, alpha: 1),
                surface: NSColor(srgbRed: 0.039, green: 0.063, blue: 0.105, alpha: 1),
                raised: NSColor(srgbRed: 0.055, green: 0.086, blue: 0.14, alpha: 1),
                sidebar: NSColor(srgbRed: 0.035, green: 0.057, blue: 0.095, alpha: 0.94),
                rule: NSColor(srgbRed: 0.12, green: 0.19, blue: 0.29, alpha: 1),
                muted: NSColor(srgbRed: 0.51, green: 0.61, blue: 0.74, alpha: 1),
                ink: NSColor(srgbRed: 0.89, green: 0.94, blue: 1, alpha: 1),
                accent: NSColor(srgbRed: 0.28, green: 0.68, blue: 1, alpha: 1)
            )
        case .graphite:
            RibbitPalette(
                canvas: NSColor(srgbRed: 0.075, green: 0.075, blue: 0.078, alpha: 1),
                surface: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.105, alpha: 1),
                raised: NSColor(srgbRed: 0.135, green: 0.135, blue: 0.14, alpha: 1),
                sidebar: NSColor(srgbRed: 0.09, green: 0.09, blue: 0.095, alpha: 0.94),
                rule: NSColor(srgbRed: 0.21, green: 0.21, blue: 0.22, alpha: 1),
                muted: NSColor(srgbRed: 0.58, green: 0.58, blue: 0.60, alpha: 1),
                ink: NSColor(srgbRed: 0.94, green: 0.94, blue: 0.94, alpha: 1),
                accent: NSColor(srgbRed: 0.95, green: 0.68, blue: 0.26, alpha: 1)
            )
        }
    }
}

enum RibbitNotchDisplayTarget: String, CaseIterable, Identifiable {
    case builtIn = "built-in display"
    case main = "main display"
    case followRibbit = "follow ribbit"

    var id: String { rawValue }
}

enum RibbitNotchExpandedWidth: String, CaseIterable, Identifiable {
    case slim
    case standard
    case wide
    case ultra

    var id: String { rawValue }

    var contentWidth: CGFloat {
        switch self {
        case .slim: 480
        case .standard: 612
        case .wide: 744
        case .ultra: 876
        }
    }
}

struct RibbitPalette {
    let canvas: NSColor
    let surface: NSColor
    let raised: NSColor
    let sidebar: NSColor
    let rule: NSColor
    let muted: NSColor
    let ink: NSColor
    let accent: NSColor
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var colorScheme: RibbitColorScheme {
        didSet { defaults.set(colorScheme.rawValue, forKey: Keys.colorScheme) }
    }
    @Published var projectRailTextSize: Double {
        didSet { defaults.set(projectRailTextSize, forKey: Keys.projectRailTextSize) }
    }
    @Published var tabTextSize: Double {
        didSet { defaults.set(tabTextSize, forKey: Keys.tabTextSize) }
    }
    @Published var terminalTextSize: Double {
        didSet { defaults.set(terminalTextSize, forKey: Keys.terminalTextSize) }
    }
    @Published var editorTextSize: Double {
        didSet { defaults.set(editorTextSize, forKey: Keys.editorTextSize) }
    }
    @Published var filesTextSize: Double {
        didSet { defaults.set(filesTextSize, forKey: Keys.filesTextSize) }
    }
    @Published var glassySurfacesEnabled: Bool {
        didSet {
            defaults.set(
                glassySurfacesEnabled,
                forKey: Keys.glassySurfacesEnabled
            )
        }
    }
    @Published var sidebarOpacity: Double {
        didSet { defaults.set(sidebarOpacity, forKey: Keys.sidebarOpacity) }
    }
    @Published var sidebarBlur: Double {
        didSet { defaults.set(sidebarBlur, forKey: Keys.sidebarBlur) }
    }
    @Published var glassDepth: Double {
        didSet { defaults.set(glassDepth, forKey: Keys.glassDepth) }
    }
    @Published var agentNotificationsEnabled: Bool {
        didSet {
            defaults.set(agentNotificationsEnabled, forKey: Keys.agentNotificationsEnabled)
        }
    }
    @Published var notchMonitorEnabled: Bool {
        didSet { defaults.set(notchMonitorEnabled, forKey: Keys.notchMonitorEnabled) }
    }
    @Published var notchExpandOnHover: Bool {
        didSet { defaults.set(notchExpandOnHover, forKey: Keys.notchExpandOnHover) }
    }
    @Published var notchHoverDelay: Double {
        didSet { defaults.set(notchHoverDelay, forKey: Keys.notchHoverDelay) }
    }
    @Published var notchAutoCollapse: Bool {
        didSet { defaults.set(notchAutoCollapse, forKey: Keys.notchAutoCollapse) }
    }
    @Published var notchAttentionRevealDwell: Double {
        didSet {
            defaults.set(
                notchAttentionRevealDwell,
                forKey: Keys.notchAttentionRevealDwell
            )
        }
    }
    @Published var notchDisplayTarget: RibbitNotchDisplayTarget {
        didSet {
            defaults.set(
                notchDisplayTarget.rawValue,
                forKey: Keys.notchDisplayTarget
            )
        }
    }
    @Published var notchShowActivityDetail: Bool {
        didSet {
            defaults.set(
                notchShowActivityDetail,
                forKey: Keys.notchShowActivityDetail
            )
        }
    }
    @Published var notchHideInFullScreen: Bool {
        didSet {
            defaults.set(
                notchHideInFullScreen,
                forKey: Keys.notchHideInFullScreen
            )
        }
    }
    @Published var notchExpandedWidth: RibbitNotchExpandedWidth {
        didSet {
            defaults.set(
                notchExpandedWidth.rawValue,
                forKey: Keys.notchExpandedWidth
            )
        }
    }
    @Published var notchOpacity: Double {
        didSet { defaults.set(notchOpacity, forKey: Keys.notchOpacity) }
    }
    @Published var notchBlur: Double {
        didSet { defaults.set(notchBlur, forKey: Keys.notchBlur) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        colorScheme = RibbitColorScheme(rawValue: defaults.string(forKey: Keys.colorScheme) ?? "") ?? .ribbit
        let legacyInterfaceSize = defaults.object(forKey: Keys.legacyInterfaceTextSize) == nil
            ? 12 : defaults.double(forKey: Keys.legacyInterfaceTextSize)
        projectRailTextSize = Self.savedSize(defaults, key: Keys.projectRailTextSize, fallback: legacyInterfaceSize)
        tabTextSize = Self.savedSize(defaults, key: Keys.tabTextSize, fallback: legacyInterfaceSize)
        terminalTextSize = defaults.object(forKey: Keys.terminalTextSize) == nil
            ? 14 : defaults.double(forKey: Keys.terminalTextSize)
        editorTextSize = Self.savedSize(defaults, key: Keys.editorTextSize, fallback: 14)
        filesTextSize = Self.savedSize(defaults, key: Keys.filesTextSize, fallback: max(10, legacyInterfaceSize - 1))
        glassySurfacesEnabled = Self.savedBool(
            defaults,
            key: Keys.glassySurfacesEnabled,
            fallback: false
        )
        let savedSidebarOpacity = Self.savedUnitInterval(
            defaults,
            key: Keys.sidebarOpacity,
            fallback: 0.82
        )
        sidebarOpacity = savedSidebarOpacity
        sidebarBlur = Self.savedUnitInterval(
            defaults,
            key: Keys.sidebarBlur,
            fallback: savedSidebarOpacity * 0.55 / 0.70
        )
        let savedGlassDepth = Self.savedUnitInterval(
            defaults,
            key: Keys.glassDepth,
            fallback: 0.62
        )
        glassDepth = savedGlassDepth
        agentNotificationsEnabled = defaults.bool(forKey: Keys.agentNotificationsEnabled)
        notchMonitorEnabled = Self.savedBool(
            defaults,
            key: Keys.notchMonitorEnabled,
            fallback: Self.hasPhysicalNotch
        )
        notchExpandOnHover = Self.savedBool(
            defaults,
            key: Keys.notchExpandOnHover,
            fallback: true
        )
        notchHoverDelay = Self.savedDouble(
            defaults,
            key: Keys.notchHoverDelay,
            fallback: 0.15
        )
        notchAutoCollapse = Self.savedBool(
            defaults,
            key: Keys.notchAutoCollapse,
            fallback: true
        )
        notchAttentionRevealDwell = Self.savedDouble(
            defaults,
            key: Keys.notchAttentionRevealDwell,
            fallback: 5
        )
        notchDisplayTarget = RibbitNotchDisplayTarget(
            rawValue: defaults.string(forKey: Keys.notchDisplayTarget) ?? ""
        ) ?? .builtIn
        notchShowActivityDetail = Self.savedBool(
            defaults,
            key: Keys.notchShowActivityDetail,
            fallback: true
        )
        notchHideInFullScreen = Self.savedBool(
            defaults,
            key: Keys.notchHideInFullScreen,
            fallback: false
        )
        notchExpandedWidth = RibbitNotchExpandedWidth(
            rawValue: defaults.string(forKey: Keys.notchExpandedWidth) ?? ""
        ) ?? .standard
        notchOpacity = Self.savedUnitInterval(
            defaults,
            key: Keys.notchOpacity,
            fallback: 0.78
        )
        notchBlur = Self.savedUnitInterval(
            defaults,
            key: Keys.notchBlur,
            fallback: savedGlassDepth * 0.58 / 0.72
        )
    }

    func reset() {
        colorScheme = .ribbit
        projectRailTextSize = 12
        tabTextSize = 12
        terminalTextSize = 14
        editorTextSize = 14
        filesTextSize = 11
        glassySurfacesEnabled = false
        sidebarOpacity = 0.82
        sidebarBlur = 0.64
        glassDepth = 0.62
        agentNotificationsEnabled = false
        notchMonitorEnabled = Self.hasPhysicalNotch
        notchExpandOnHover = true
        notchHoverDelay = 0.15
        notchAutoCollapse = true
        notchAttentionRevealDwell = 5
        notchDisplayTarget = .builtIn
        notchShowActivityDetail = true
        notchHideInFullScreen = false
        notchExpandedWidth = .standard
        notchOpacity = 0.78
        notchBlur = 0.50
    }

    private static func savedSize(_ defaults: UserDefaults, key: String, fallback: Double) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }

    private static func savedDouble(
        _ defaults: UserDefaults,
        key: String,
        fallback: Double
    ) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }

    private static func savedBool(
        _ defaults: UserDefaults,
        key: String,
        fallback: Bool
    ) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private static func savedUnitInterval(
        _ defaults: UserDefaults,
        key: String,
        fallback: Double
    ) -> Double {
        min(max(savedDouble(defaults, key: key, fallback: fallback), 0), 1)
    }

    private static var hasPhysicalNotch: Bool {
        NSScreen.screens.contains {
            $0.safeAreaInsets.top > 0
                && $0.auxiliaryTopLeftArea != nil
                && $0.auxiliaryTopRightArea != nil
        }
    }

    private enum Keys {
        static let colorScheme = "appearance.colorScheme"
        static let legacyInterfaceTextSize = "appearance.interfaceTextSize"
        static let projectRailTextSize = "appearance.projectRailTextSize"
        static let tabTextSize = "appearance.tabTextSize"
        static let terminalTextSize = "appearance.terminalTextSize"
        static let editorTextSize = "appearance.editorTextSize"
        static let filesTextSize = "appearance.filesTextSize"
        static let glassySurfacesEnabled = "appearance.glassySurfacesEnabled"
        static let sidebarOpacity = "appearance.sidebarOpacity"
        static let sidebarBlur = "appearance.sidebarBlur"
        static let glassDepth = "appearance.glassDepth"
        static let agentNotificationsEnabled = "agents.notificationsEnabled"
        static let notchMonitorEnabled = "agents.notch.enabled"
        static let notchExpandOnHover = "agents.notch.expandOnHover"
        static let notchHoverDelay = "agents.notch.hoverDelay"
        static let notchAutoCollapse = "agents.notch.autoCollapse"
        static let notchAttentionRevealDwell = "agents.notch.attentionRevealDwell"
        static let notchDisplayTarget = "agents.notch.displayTarget"
        static let notchShowActivityDetail = "agents.notch.showActivityDetail"
        static let notchHideInFullScreen = "agents.notch.hideInFullScreen"
        static let notchExpandedWidth = "agents.notch.expandedWidth"
        static let notchOpacity = "agents.notch.opacity"
        static let notchBlur = "agents.notch.blur"
    }
}

struct LegacySettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var tmuxStatus: TmuxStatusModel
    @StateObject private var agentHooks = RibbitAgentHookStatusModel()

    init(settings: AppSettings, tmuxStatus: TmuxStatusModel = TmuxStatusModel()) {
        self.settings = settings
        self.tmuxStatus = tmuxStatus
    }

    var body: some View {
        Form {
            Section("appearance") {
                Picker("color scheme", selection: $settings.colorScheme) {
                    ForEach(RibbitColorScheme.allCases) { scheme in
                        Text(scheme.rawValue).tag(scheme)
                    }
                }

                TextSizeSettingRow("project rail", value: $settings.projectRailTextSize, range: 10...16)
                TextSizeSettingRow("tab strip", value: $settings.tabTextSize, range: 10...16)
                TextSizeSettingRow("terminal", value: $settings.terminalTextSize, range: 11...22)
                TextSizeSettingRow("note editor", value: $settings.editorTextSize, range: 11...22)
                TextSizeSettingRow("files pane", value: $settings.filesTextSize, range: 9...16)

                Toggle(
                    "use dark glass surfaces",
                    isOn: $settings.glassySurfacesEnabled
                )

                OpacitySettingRow(
                    "side panel opacity",
                    value: $settings.sidebarOpacity
                )
                .disabled(!settings.glassySurfacesEnabled)

                OpacitySettingRow(
                    "side panel background blur",
                    value: $settings.sidebarBlur
                )
                .disabled(!settings.glassySurfacesEnabled)

                OpacitySettingRow(
                    "glass depth",
                    value: $settings.glassDepth
                )
                .disabled(!settings.glassySurfacesEnabled)

                Text("Glass styling is optional. Opacity changes update the project side panel and agent monitor immediately.")
                    .font(.system(size: 11))
                    .foregroundStyle(RibbitTheme.muted)

                HStack {
                    Spacer()
                    Button("restore defaults") { settings.reset() }
                }
            }

            TmuxStatusSection(status: tmuxStatus)
            AgentHooksSection(status: agentHooks)
            AgentNotchSettingsSection(settings: settings)
            Section("agent notifications") {
                Toggle(
                    "notify when an agent needs you or becomes ready",
                    isOn: $settings.agentNotificationsEnabled
                )
                Text("Notifications are local and optional. Clicking one returns to its matched ribbit terminal when possible.")
                    .font(.system(size: 11))
                    .foregroundStyle(RibbitTheme.muted)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 540, height: 760)
        .preferredColorScheme(.dark)
    }
}

private struct AgentNotchSettingsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Section("agent monitor") {
            Toggle(
                "show agent monitor in notch",
                isOn: $settings.notchMonitorEnabled
            )
            Toggle(
                "expand on hover",
                isOn: $settings.notchExpandOnHover
            )
            .disabled(!settings.notchMonitorEnabled)

            LabeledContent("hover delay") {
                Picker("", selection: $settings.notchHoverDelay) {
                    Text("0.10 s").tag(0.10)
                    Text("0.15 s").tag(0.15)
                    Text("0.25 s").tag(0.25)
                    Text("0.40 s").tag(0.40)
                }
                .labelsHidden()
                .frame(width: 100)
            }
            .disabled(!settings.notchMonitorEnabled || !settings.notchExpandOnHover)

            Toggle(
                "collapse on mouse leave",
                isOn: $settings.notchAutoCollapse
            )
            .disabled(!settings.notchMonitorEnabled)

            Picker("expanded width", selection: $settings.notchExpandedWidth) {
                ForEach(RibbitNotchExpandedWidth.allCases) { width in
                    Text(width.rawValue).tag(width)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!settings.notchMonitorEnabled)

            OpacitySettingRow(
                "notch opacity",
                value: $settings.notchOpacity
            )
            .disabled(
                !settings.notchMonitorEnabled
                    || !settings.glassySurfacesEnabled
            )

            OpacitySettingRow(
                "notch background blur",
                value: $settings.notchBlur
            )
            .disabled(
                !settings.notchMonitorEnabled
                    || !settings.glassySurfacesEnabled
            )

            LabeledContent("attention reveal") {
                Picker("", selection: $settings.notchAttentionRevealDwell) {
                    Text("3 s").tag(3.0)
                    Text("5 s").tag(5.0)
                    Text("8 s").tag(8.0)
                    Text("until dismissed").tag(0.0)
                }
                .labelsHidden()
                .frame(width: 140)
            }
            .disabled(!settings.notchMonitorEnabled)

            Picker("display", selection: $settings.notchDisplayTarget) {
                ForEach(RibbitNotchDisplayTarget.allCases) { target in
                    Text(target.rawValue).tag(target)
                }
            }
            .disabled(!settings.notchMonitorEnabled)

            Toggle(
                "show agent activity detail",
                isOn: $settings.notchShowActivityDetail
            )
            .disabled(!settings.notchMonitorEnabled)
            Toggle(
                "hide in full screen",
                isOn: $settings.notchHideInFullScreen
            )
            .disabled(!settings.notchMonitorEnabled)
        }
    }
}

private struct AgentHooksSection: View {
    @ObservedObject var status: RibbitAgentHookStatusModel

    var body: some View {
        Section("agent activity") {
            Text("Optional observer hooks show live Codex, Claude, and Cursor state on the matching terminal. They never approve, deny, or change agent actions.")
                .font(.system(size: 11))
                .foregroundStyle(RibbitTheme.muted)

            ForEach(RibbitAgentKind.allCases) { agent in
                LabeledContent(agent.displayName) {
                    hookLabel(status.states[agent] ?? .checking)
                }
            }

            if let message = status.message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(RibbitTheme.muted)
            }

            HStack {
                Button("recheck") { status.refresh() }
                    .disabled(status.isWorking)
                Spacer()
                Button("install or repair hooks") { status.installOrRepair() }
                    .disabled(status.isWorking)
            }
        }
    }

    @ViewBuilder
    private func hookLabel(_ state: RibbitAgentHookState) -> some View {
        switch state {
        case .checking:
            ProgressView().controlSize(.small)
        case .ready:
            Label("connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(RibbitTheme.accent)
        case .needsSetup:
            Label("setup needed", systemImage: "circle.dashed")
                .foregroundStyle(.orange)
        case .unavailable(let detail):
            Label(detail, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

private struct TmuxStatusSection: View {
    @ObservedObject var status: TmuxStatusModel

    var body: some View {
        Section("terminal persistence") {
            switch status.availability {
            case .available(let path, let version):
                LabeledContent {
                    Label("persistence active", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(RibbitTheme.accent)
                } label: {
                    Text("tmux available")
                }
                Text([version, path].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(RibbitTheme.muted)
                    .textSelection(.enabled)

            case .unavailable:
                LabeledContent {
                    Label("terminals stop with ribbit", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } label: {
                    Text("tmux unavailable")
                }
                Text("Install tmux to keep shells and agents running when ribbit quits or crashes.")
                    .font(.system(size: 11))
                    .foregroundStyle(RibbitTheme.muted)
                HStack(spacing: 8) {
                    Text(TmuxStatusModel.installationCommand)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button("copy") { status.copyInstallationCommand() }
                }
            }

            HStack {
                Spacer()
                Button("recheck") { status.recheck() }
            }
        }
    }
}

private struct TextSizeSettingRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) {
        self.title = title
        _value = value
        self.range = range
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                Slider(value: $value, in: range, step: 1)
                    .frame(width: 190)
                Text("\(Int(value)) pt")
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }
        }
    }
}

private struct OpacitySettingRow: View {
    let title: String
    @Binding var value: Double

    init(_ title: String, value: Binding<Double>) {
        self.title = title
        _value = value
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                Slider(value: $value, in: 0...1, step: 0.05)
                    .frame(width: 190)
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
        }
    }
}
