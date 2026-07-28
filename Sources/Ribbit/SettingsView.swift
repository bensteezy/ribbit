import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var tmuxStatus: TmuxStatusModel
    @StateObject private var agentHooks = RibbitAgentHookStatusModel()

    init(settings: AppSettings, tmuxStatus: TmuxStatusModel = TmuxStatusModel()) {
        self.settings = settings
        self.tmuxStatus = tmuxStatus
    }

    var body: some View {
        ZStack {
            Color(nsColor: settings.colorScheme.palette.canvas)
                .ignoresSafeArea()

            RibbitVisualEffectView(
                material: .hudWindow,
                blendingMode: .behindWindow
            )
            .opacity(0.28)
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header

                    HStack(alignment: .top, spacing: 20) {
                        LiveNotchPreview(settings: settings)
                            .frame(maxWidth: .infinity)

                        VStack(spacing: 14) {
                            layoutCard
                            glassCard
                            behaviorCard
                        }
                        .frame(width: 408)
                    }

                    HStack(alignment: .top, spacing: 20) {
                        typeCard
                        systemCard
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 28)
                .padding(.bottom, 34)
            }
        }
        .frame(width: 980, height: 760)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 7) {
                Text("Tune the open notch and side panel. Every change previews instantly.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(RibbitTheme.muted)
            }
            .frame(maxWidth: .infinity)

            Button("restore defaults") {
                settings.reset()
            }
            .buttonStyle(RibbitGlassButtonStyle())
        }
        .frame(minHeight: 54)
    }

    private var layoutCard: some View {
        SettingsCard(title: "layout") {
            SettingsControlLabel(
                title: "expanded width",
                value: settings.notchExpandedWidth.rawValue
            )
            SettingsChoiceBar(
                values: RibbitNotchExpandedWidth.allCases,
                selection: $settings.notchExpandedWidth,
                label: \.rawValue
            )
            .disabled(!settings.notchMonitorEnabled)

            Divider().overlay(RibbitTheme.rule)

            SettingsControlLabel(
                title: "color scheme",
                value: settings.colorScheme.rawValue
            )
            SettingsChoiceBar(
                values: RibbitColorScheme.allCases,
                selection: $settings.colorScheme,
                label: \.rawValue
            )
        }
    }

    private var glassCard: some View {
        SettingsCard(title: "liquid glass") {
            SettingsToggleRow(
                title: "dark glass surfaces",
                subtitle: "Use real desktop blur in the open notch and left project rail.",
                isOn: $settings.glassySurfacesEnabled
            )

            Divider().overlay(RibbitTheme.rule)

            SettingsSliderRow(
                title: "notch opacity",
                value: $settings.notchOpacity
            )
            .disabled(!settings.glassySurfacesEnabled)

            SettingsSliderRow(
                title: "notch background blur",
                value: $settings.notchBlur
            )
            .disabled(!settings.glassySurfacesEnabled)

            SettingsSliderRow(
                title: "notch depth",
                value: $settings.glassDepth
            )
            .disabled(!settings.glassySurfacesEnabled)

            Divider().overlay(RibbitTheme.rule)

            SettingsSliderRow(
                title: "left sidebar opacity",
                value: $settings.sidebarOpacity
            )
            .disabled(!settings.glassySurfacesEnabled)

            SettingsSliderRow(
                title: "left sidebar background blur",
                value: $settings.sidebarBlur
            )
            .disabled(!settings.glassySurfacesEnabled)
        }
    }

    private var behaviorCard: some View {
        SettingsCard(title: "behavior") {
            SettingsToggleRow(
                title: "show agent monitor",
                subtitle: "Keep live agent status in the notch.",
                isOn: $settings.notchMonitorEnabled
            )
            SettingsToggleRow(
                title: "expand on hover",
                subtitle: "Open without requiring a click.",
                isOn: $settings.notchExpandOnHover
            )
            .disabled(!settings.notchMonitorEnabled)
            SettingsToggleRow(
                title: "collapse on mouse leave",
                subtitle: "Return to the compact notch automatically.",
                isOn: $settings.notchAutoCollapse
            )
            .disabled(!settings.notchMonitorEnabled)
        }
    }

    private var typeCard: some View {
        SettingsCard(title: "text size") {
            SettingsPointSliderRow(
                title: "project rail",
                value: $settings.projectRailTextSize,
                range: 10...16
            )
            SettingsPointSliderRow(
                title: "tab strip",
                value: $settings.tabTextSize,
                range: 10...16
            )
            SettingsPointSliderRow(
                title: "terminal",
                value: $settings.terminalTextSize,
                range: 11...22
            )
            SettingsPointSliderRow(
                title: "note editor",
                value: $settings.editorTextSize,
                range: 11...22
            )
            SettingsPointSliderRow(
                title: "files pane",
                value: $settings.filesTextSize,
                range: 9...16
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var systemCard: some View {
        SettingsCard(title: "agents & persistence") {
            SettingsStatusRow(
                title: "terminal persistence",
                value: tmuxStatus.availability.isAvailable
                    ? "active"
                    : "tmux needed",
                isReady: tmuxStatus.availability.isAvailable
            )

            ForEach(RibbitAgentKind.allCases) { agent in
                SettingsStatusRow(
                    title: agent.displayName,
                    value: agentStatusLabel(agentHooks.states[agent] ?? .checking),
                    isReady: agentHooks.states[agent]?.isReady == true
                )
            }

            SettingsToggleRow(
                title: "agent notifications",
                subtitle: "Notify when work needs you or becomes ready.",
                isOn: $settings.agentNotificationsEnabled
            )

            HStack {
                Button("recheck") {
                    tmuxStatus.recheck()
                    agentHooks.refresh()
                }
                .buttonStyle(RibbitGlassButtonStyle())

                Spacer()

                Button("install or repair hooks") {
                    agentHooks.installOrRepair()
                }
                .buttonStyle(RibbitGlassButtonStyle(isProminent: true))
                .disabled(agentHooks.isWorking)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func agentStatusLabel(_ state: RibbitAgentHookState) -> String {
        switch state {
        case .checking: "checking"
        case .ready: "connected"
        case .needsSetup: "setup needed"
        case .unavailable(let detail): detail
        }
    }
}

private struct LiveNotchPreview: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsCard(title: "live notch preview", badge: settings.notchExpandedWidth.rawValue) {
            ZStack {
                previewAtmosphere

                VStack(spacing: 0) {
                    previewHeader
                    previewRow(
                        icon: "terminal",
                        title: "tux-term",
                        detail: "editing the settings preview",
                        tint: RibbitTheme.accent
                    )
                    Divider().overlay(Color.white.opacity(0.08))
                    previewRow(
                        icon: "sparkles",
                        title: "power-paws",
                        detail: "planning release checks",
                        tint: .orange
                    )
                    Divider().overlay(Color.white.opacity(0.08))
                    previewRow(
                        icon: "cursorarrow.rays",
                        title: "cursor",
                        detail: "ready for a prompt",
                        tint: .blue
                    )
                }
                .frame(width: previewWidth)
                .background {
                    if settings.glassySurfacesEnabled {
                        RibbitNotchGlassSurface(
                            opacity: settings.notchOpacity,
                            depth: settings.glassDepth,
                            blur: settings.notchBlur,
                            compactHeight: 40,
                            material: .underWindowBackground
                        )
                    } else {
                        Color.black
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.30), radius: 22, y: 12)
                .animation(
                    .timingCurve(0.16, 1, 0.30, 1, duration: 0.24),
                    value: settings.notchExpandedWidth
                )
            }
            .frame(maxWidth: .infinity, minHeight: 344)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Label("controls update instantly", systemImage: "bolt.fill")
                Spacer()
                Text("open notch only")
            }
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(RibbitTheme.muted)
        }
    }

    private var previewWidth: CGFloat {
        switch settings.notchExpandedWidth {
        case .slim: 300
        case .standard: 344
        case .wide: 388
        case .ultra: 430
        }
    }

    private var previewAtmosphere: some View {
        ZStack {
            Color(nsColor: settings.colorScheme.palette.canvas)
            Circle()
                .fill(Color.pink.opacity(0.20))
                .frame(width: 230, height: 230)
                .blur(radius: 48)
                .offset(x: 126, y: 106)
            Circle()
                .fill(Color.purple.opacity(0.18))
                .frame(width: 190, height: 190)
                .blur(radius: 52)
                .offset(x: -130, y: 118)
        }
    }

    private var previewHeader: some View {
        HStack {
            FrogMascotView(pixelSize: 1.4)
            Text("3 SESSIONS")
            Spacer()
            Circle()
                .fill(RibbitTheme.accent)
                .frame(width: 5, height: 5)
            Text("LIVE")
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.78))
        .padding(.horizontal, 15)
        .frame(height: 40)
    }

    private func previewRow(
        icon: String,
        title: String,
        detail: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.055), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.white.opacity(0.52))
                    .lineLimit(1)
            }

            Spacer()

            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 15)
        .frame(height: 57)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    var badge: String?
    @ViewBuilder var content: Content

    init(
        title: String,
        badge: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.badge = badge
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(RibbitTheme.muted)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(RibbitTheme.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
            }

            content
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(nsColor: AppSettings.shared.colorScheme.palette.raised).opacity(0.74))
                .background {
                    RibbitVisualEffectView(
                        material: .hudWindow,
                        blendingMode: .withinWindow
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.075), lineWidth: 0.7)
        }
    }
}

private struct SettingsControlLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(RibbitTheme.ink)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(RibbitTheme.muted)
        }
        .font(.system(size: 12, weight: .medium))
    }
}

private struct SettingsChoiceBar<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let label: KeyPath<Value, String>

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Button {
                    selection = value
                } label: {
                    Text(value[keyPath: label])
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .foregroundStyle(
                            selection == value
                                ? RibbitTheme.ink
                                : RibbitTheme.muted
                        )
                        .background(
                            selection == value
                                ? Color.white.opacity(0.10)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.17), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RibbitTheme.ink)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(RibbitTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(RibbitTheme.ink)

            Slider(value: $value, in: 0...1, step: 0.01)
                .controlSize(.small)
        }
    }
}

private struct SettingsPointSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value)) pt")
                    .monospacedDigit()
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(RibbitTheme.ink)

            Slider(value: $value, in: range, step: 1)
                .controlSize(.small)
        }
    }
}

private struct SettingsStatusRow: View {
    let title: String
    let value: String
    let isReady: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(RibbitTheme.ink)
            Spacer()
            Circle()
                .fill(isReady ? RibbitTheme.accent : .orange)
                .frame(width: 6, height: 6)
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(isReady ? RibbitTheme.accent : .orange)
        }
    }
}

private struct RibbitGlassButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isProminent ? Color.black : RibbitTheme.ink)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                isProminent
                    ? RibbitTheme.accent.opacity(configuration.isPressed ? 0.74 : 0.92)
                    : Color.white.opacity(configuration.isPressed ? 0.06 : 0.09),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(isProminent ? 0.14 : 0.08), lineWidth: 0.7)
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private extension TmuxStatusModel.Availability {
    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

private extension RibbitAgentHookState {
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}
