import AppKit
import SwiftUI

struct RibbitAgentNotchRootView: View {
    @ObservedObject var state: RibbitAgentNotchState

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                surface

                RibbitExpandedNotchView(state: state)
                    .opacity(expandedContentOpacity)
                    .offset(y: (1 - expandedContentOpacity) * -3)
                    .allowsHitTesting(state.isExpanded)

                RibbitCompactNotchView(state: state)
                    .frame(
                        width: proxy.size.width,
                        height: state.viewMetrics.headerHeight
                    )
                    .opacity(compactContentOpacity)
                    .allowsHitTesting(!state.isExpanded)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipShape(surfaceShape)
            .contentShape(Rectangle())
            .onHover(perform: state.setIslandHovering)
            .onTapGesture {
                if !state.isExpanded {
                    state.expandAndPin()
                }
            }
            .contextMenu {
                Button("agent monitor settings…") {
                    NSApp.sendAction(
                        Selector(("showSettingsWindow:")),
                        to: nil,
                        from: nil
                    )
                    NSApp.activate(ignoringOtherApps: true)
                }
                Divider()
                Button("hide agent monitor") {
                    state.settings.notchMonitorEnabled = false
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var surface: some View {
        if state.settings.glassySurfacesEnabled {
            RibbitNotchGlassSurface(
                opacity: state.settings.notchOpacity,
                depth: state.settings.glassDepth,
                blur: state.settings.notchBlur,
                compactHeight: state.viewMetrics.headerHeight,
                reveal: glassReveal,
                material: .underWindowBackground,
                blendingMode: .behindWindow
            )
            .overlay {
                surfaceShape
                    .stroke(
                        Color.white.opacity(
                            glassReveal
                                * (0.045 + state.settings.glassDepth * 0.065)
                        ),
                        lineWidth: 0.5
                    )
            }
        } else {
            if state.viewMetrics.hasPhysicalNotch {
                RibbitTopAttachedNotchShape()
                    .fill(Color.black)
            } else {
                RibbitFloatingNotchShape()
                .fill(Color.black)
                .overlay {
                    RibbitFloatingNotchShape()
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                }
            }
        }
    }

    private var surfaceShape: AnyShape {
        if state.viewMetrics.hasPhysicalNotch {
            return AnyShape(RibbitTopAttachedNotchShape())
        }
        return AnyShape(RibbitFloatingNotchShape())
    }

    private var glassReveal: Double {
        Double(Self.smoothstep(state.expansionProgress, from: 0.08, to: 0.74))
    }

    private var compactContentOpacity: Double {
        Double(1 - Self.smoothstep(state.expansionProgress, from: 0.04, to: 0.28))
    }

    private var expandedContentOpacity: Double {
        Double(Self.smoothstep(state.expansionProgress, from: 0.24, to: 0.68))
    }

    private static func smoothstep(
        _ value: CGFloat,
        from lower: CGFloat,
        to upper: CGFloat
    ) -> CGFloat {
        let progress = min(max((value - lower) / (upper - lower), 0), 1)
        return progress * progress * (3 - 2 * progress)
    }
}

private struct RibbitCompactNotchView: View {
    @ObservedObject var state: RibbitAgentNotchState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            RibbitNotchFrog(
                color: statusColor,
                animated: state.projection.life == .running && !reduceMotion
            )
            .frame(width: 18, height: 18)

            if !state.viewMetrics.hasPhysicalNotch {
                Text(compactLabel)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor)
                    .padding(.leading, 6)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                if state.projection.life == .attention {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 4, height: 4)
                }
                Text("\(state.projection.visibleSessions.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor)
            }
            .frame(minWidth: 18, alignment: .trailing)
        }
        .padding(
            .horizontal,
            RibbitAgentNotchGeometry.compactSurfaceCornerRadius
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var compactLabel: String {
        switch state.projection.life {
        case .attention: "needs you"
        case .running: "running"
        case .ready: "ready"
        case .quiet: "ribbit"
        }
    }

    private var accessibilityLabel: String {
        "ribbit, \(state.projection.visibleSessions.count) agents, \(compactLabel)"
    }

    private var statusColor: Color {
        switch state.projection.life {
        case .attention: RibbitNotchColors.attention
        case .running: RibbitNotchColors.running
        case .ready: RibbitNotchColors.ready
        case .quiet: RibbitNotchColors.tertiaryText
        }
    }
}

private struct RibbitExpandedNotchView: View {
    @ObservedObject var state: RibbitAgentNotchState

    var body: some View {
        VStack(spacing: 0) {
            header

            if state.projection.displayedSessions.isEmpty {
                emptyState
            } else {
                ForEach(
                    Array(state.projection.displayedSessions.enumerated()),
                    id: \.element.id
                ) { index, session in
                    RibbitNotchSessionRow(state: state, session: session)
                    if index < state.projection.displayedSessions.count - 1 {
                        Rectangle()
                            .fill(RibbitNotchColors.divider)
                            .frame(height: 1)
                            .padding(.horizontal, 12)
                    }
                }
            }

            if let attention = state.projection.primaryAttention {
                RibbitNotchAttentionDetail(state: state, session: attention)
            }
            Spacer(minLength: 8)
        }
        .padding(
            .horizontal,
            RibbitAgentNotchGeometry.expandedTopCornerRadius
        )
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var header: some View {
        HStack(spacing: 0) {
            RibbitNotchStateSummary(state: state)
                .frame(maxWidth: .infinity, alignment: .leading)

            if state.viewMetrics.hasPhysicalNotch {
                Color.clear
                    .frame(width: state.viewMetrics.hardwareNotchWidth)
            }

            HStack(spacing: 0) {
                Button {
                    state.settings.agentNotificationsEnabled.toggle()
                } label: {
                    Image(systemName: state.settings.agentNotificationsEnabled
                        ? "speaker.wave.2.fill"
                        : "speaker.slash.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(state.settings.agentNotificationsEnabled
                    ? "mute agent notifications"
                    : "enable agent notifications")

                Button {
                    NSApp.sendAction(
                        Selector(("showSettingsWindow:")),
                        to: nil,
                        from: nil
                    )
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("ribbit settings")
            }
            .foregroundStyle(RibbitNotchColors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: state.viewMetrics.headerHeight)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            RibbitNotchFrog(color: RibbitNotchColors.tertiaryText, animated: false)
                .frame(width: 18, height: 16)
            Text("waiting for agents")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(RibbitNotchColors.secondaryText)
            Text("start codex, claude, or cursor to see it here")
                .font(.system(size: 8.5))
                .foregroundStyle(RibbitNotchColors.tertiaryText)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: RibbitAgentNotchGeometry.rowHeight
        )
    }
}

private struct RibbitNotchStateSummary: View {
    @ObservedObject var state: RibbitAgentNotchState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if state.projection.attentionCount > 0 {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 6, weight: .black))
                Text("\(state.projection.attentionCount) NEEDS YOU")
            } else if state.projection.runningCount > 0 {
                RibbitNotchFrog(
                    color: RibbitNotchColors.running,
                    animated: !reduceMotion
                )
                .frame(width: 16, height: 14)
                Text("\(state.projection.runningCount) RUNNING")
            } else if state.projection.readyCount > 0 {
                Image(systemName: "pause.fill")
                    .font(.system(size: 6, weight: .bold))
                Text("\(state.projection.readyCount) READY")
            } else {
                Circle()
                    .frame(width: 4, height: 4)
                Text("NO LIVE WORK")
            }
        }
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .foregroundStyle(summaryColor)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var summaryColor: Color {
        switch state.projection.life {
        case .attention: RibbitNotchColors.attention
        case .running: RibbitNotchColors.running
        case .ready: RibbitNotchColors.ready
        case .quiet: RibbitNotchColors.secondaryText
        }
    }
}

private struct RibbitNotchSessionRow: View {
    @ObservedObject var state: RibbitAgentNotchState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var dismissHovering = false
    let session: RibbitAgentSession

    var body: some View {
        HStack(spacing: 0) {
            Button {
                state.focus(session)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: agentSymbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(stateColor)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.06), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.project)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(RibbitNotchColors.primaryText)
                            .lineLimit(1)
                        if state.settings.notchShowActivityDetail {
                            Text(session.state == .paused
                                ? "ready \(sessionRelativeUpdated)"
                                : session.activity)
                                .font(.system(size: 8.5))
                                .foregroundStyle(
                                    session.needsAttention
                                        ? stateColor
                                        : RibbitNotchColors.secondaryText
                                )
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(stateColor)
                                .frame(width: 4, height: 4)
                            Text(stateLabel)
                                .font(.system(
                                    size: 8,
                                    weight: .bold,
                                    design: .monospaced
                                ))
                                .foregroundStyle(stateColor)
                        }
                        Text(destinationLabel)
                            .font(.system(
                                size: 6.5,
                                weight: .medium,
                                design: .monospaced
                            ))
                            .foregroundStyle(RibbitNotchColors.tertiaryText)
                    }
                    .frame(minWidth: 70, alignment: .trailing)
                }
                .padding(.leading, 13)
                .padding(.trailing, 3)
                .frame(
                    maxWidth: .infinity,
                    minHeight: RibbitAgentNotchGeometry.rowHeight
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(RibbitNotchRowButtonStyle(reduceMotion: reduceMotion))
            .accessibilityLabel(
                "\(stateLabel), open \(session.agent.displayName) for \(session.project)"
            )

            Button {
                state.hide(session)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(dismissHovering || isHovering
                        ? RibbitNotchColors.secondaryText
                        : RibbitNotchColors.tertiaryText)
                    .frame(width: 28, height: 28)
                    .background(
                        dismissHovering
                            ? Color.white.opacity(0.12)
                            : Color.clear,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .frame(width: 38, height: RibbitAgentNotchGeometry.rowHeight)
            .contentShape(Rectangle())
            .onHover { dismissHovering = $0 }
            .help("hide until this session becomes active again")
            .accessibilityLabel(
                "hide \(session.project) until this session becomes active again"
            )
            .padding(.trailing, 5)
        }
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color.white.opacity(0.075) : Color.clear)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var stateColor: Color {
        if session.needsAttention { return RibbitNotchColors.attention }
        if session.state == .running { return RibbitNotchColors.running }
        return RibbitNotchColors.ready
    }

    private var stateLabel: String {
        if session.needsAttention { return "NEEDS YOU" }
        if session.state == .running { return "RUNNING" }
        return "READY"
    }

    private var agentSymbol: String {
        switch session.agent {
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .claude: "sparkles"
        case .cursor: "cursorarrow.rays"
        }
    }

    private var destinationLabel: String {
        switch session.focusTarget?.surface {
        case .ribbit: "RIBBIT"
        case .terminal: "TERMINAL"
        case .iTerm: "ITERM"
        case .codex: "CODEX APP"
        case .cursor: "CURSOR"
        case .application:
            session.focusTarget?.tmuxTarget != nil
                ? "TMUX"
                : session.focusTarget?.applicationName?.uppercased() ?? "APP"
        case nil:
            session.agent.displayName.uppercased()
        }
    }

    private var sessionRelativeUpdated: String {
        let seconds = max(0, Int(Date.now.timeIntervalSince(session.lastUpdated)))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3_600)h ago"
    }
}

private struct RibbitNotchAttentionDetail: View {
    @ObservedObject var state: RibbitAgentNotchState
    let session: RibbitAgentSession

    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: attentionSymbol)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(RibbitNotchColors.attention)
                    Text(attentionLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(RibbitNotchColors.primaryText)
                    Spacer()
                }
                Text(session.attentionDetail ?? session.activity)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(RibbitNotchColors.secondaryText)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .background(
                Color.white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )

            HStack(spacing: 7) {
                Button("later") {
                    state.collapse()
                }
                .buttonStyle(RibbitNotchActionButtonStyle(primary: false))

                Button(actionLabel) {
                    state.focus(session)
                }
                .buttonStyle(RibbitNotchActionButtonStyle(primary: true))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 5)
        .frame(
            height: RibbitAgentNotchGeometry.attentionDetailHeight,
            alignment: .top
        )
    }

    private var attentionSymbol: String {
        switch session.attentionKind {
        case .permission: "lock.fill"
        case .question: "questionmark"
        case .plan: "list.bullet.clipboard"
        case .followUp, .none: "exclamationmark.triangle.fill"
        }
    }

    private var attentionLabel: String {
        switch session.attentionKind {
        case .permission: "permission requested"
        case .question: "agent has a question"
        case .plan: "plan ready for review"
        case .followUp, .none: "agent needs you"
        }
    }

    private var actionLabel: String {
        switch session.attentionKind {
        case .permission: "open to approve"
        case .question: "open to answer"
        case .plan: "review plan"
        case .followUp, .none: "open agent"
        }
    }
}

private struct RibbitNotchRowButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.06),
                value: configuration.isPressed
            )
    }
}

private struct RibbitNotchActionButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(primary ? Color.black : RibbitNotchColors.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(
                primary
                    ? Color.white.opacity(configuration.isPressed ? 0.74 : 0.94)
                    : Color.white.opacity(configuration.isPressed ? 0.10 : 0.055),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct RibbitNotchFrog: View {
    let color: Color
    let animated: Bool

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
                sprite(
                    pose: FrogPixelArt.workingPoses[
                        FrogPixelArt.workingPoseIndex(at: timeline.date)
                    ]
                )
            }
        } else {
            sprite(pose: FrogPixelArt.restingPose)
        }
    }

    private func sprite(pose: [String]) -> some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let pixel: CGFloat = 1.5
            let width = CGFloat(pose.first?.count ?? 0) * pixel
            let height = CGFloat(pose.count) * pixel
            let origin = CGPoint(
                x: floor((size.width - width) / 2),
                y: floor((size.height - height) / 2)
            )

            for (row, line) in pose.enumerated() {
                for (column, value) in line.enumerated() where value != "." {
                    let pixelColor: Color
                    switch value {
                    case "#", "m": pixelColor = Color.black
                    case "w": pixelColor = Color.white.opacity(0.86)
                    default: pixelColor = color
                    }
                    context.fill(
                        Path(CGRect(
                            x: origin.x + CGFloat(column) * pixel,
                            y: origin.y + CGFloat(row) * pixel,
                            width: pixel,
                            height: pixel
                        )),
                        with: .color(pixelColor)
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct RibbitTopAttachedNotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let topBleed = rect.minY - 2
        let topRadius = min(
            RibbitAgentNotchGeometry.topCornerRadius(for: rect.height),
            rect.width / 4,
            rect.height / 2
        )
        let leftEdge = rect.minX + topRadius
        let rightEdge = rect.maxX - topRadius
        let bottomRadius = min(
            RibbitAgentNotchGeometry.surfaceCornerRadius(for: rect.height),
            max(0, rect.height - topRadius),
            max(0, (rightEdge - leftEdge) / 2)
        )

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: topBleed))
        path.addQuadCurve(
            to: CGPoint(x: leftEdge, y: rect.minY + topRadius),
            control: CGPoint(x: leftEdge, y: topBleed)
        )
        path.addLine(
            to: CGPoint(x: leftEdge, y: rect.maxY - bottomRadius)
        )
        path.addQuadCurve(
            to: CGPoint(x: leftEdge + bottomRadius, y: rect.maxY),
            control: CGPoint(x: leftEdge, y: rect.maxY)
        )
        path.addLine(
            to: CGPoint(x: rightEdge - bottomRadius, y: rect.maxY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rightEdge, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rightEdge, y: rect.maxY)
        )
        path.addLine(
            to: CGPoint(x: rightEdge, y: rect.minY + topRadius)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: topBleed),
            control: CGPoint(x: rightEdge, y: topBleed)
        )
        path.closeSubpath()
        return path
    }
}

private struct RibbitFloatingNotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(
            cornerRadius: min(
                RibbitAgentNotchGeometry.surfaceCornerRadius(for: rect.height),
                rect.height / 2
            ),
            style: .continuous
        )
        .path(in: rect)
    }
}

private enum RibbitNotchColors {
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.34)
    static let divider = Color.white.opacity(0.10)
    static let running = Color(red: 0.20, green: 0.96, blue: 0.52)
    static let ready = Color(red: 0.30, green: 0.62, blue: 1.00)
    static let attention = Color(red: 1.00, green: 0.36, blue: 0.29)
}
