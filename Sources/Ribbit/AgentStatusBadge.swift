import SwiftUI

struct AgentStatusBadge: View {
    let session: RibbitAgentSession
    var compact = false
    var onActivate: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(stateColor)
                .frame(width: 6, height: 6)
            if !compact {
                Text("\(session.agent.displayName) · \(session.state.label)")
                    .lineLimit(1)
            }
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .foregroundStyle(session.needsAttention ? stateColor : RibbitTheme.muted)
        .padding(.horizontal, compact ? 3 : 6)
        .frame(height: 18)
        .background(stateColor.opacity(session.needsAttention ? 0.14 : 0.08))
        .clipShape(Capsule())
        .help("\(session.agent.displayName): \(session.activity)")
        .accessibilityLabel(
            "\(session.agent.displayName), \(session.state.label), \(session.activity)"
        )
        .accessibilityAddTraits(onActivate == nil ? [] : .isButton)
        .onTapGesture {
            onActivate?()
        }
    }

    private var stateColor: Color {
        switch session.state {
        case .attention: .red
        case .waiting: .orange
        case .running: RibbitTheme.accent
        case .paused: .blue
        case .idle: RibbitTheme.muted
        case .completed: .cyan
        }
    }
}
