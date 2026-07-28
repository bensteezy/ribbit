import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        GeometryReader { proxy in
            let metrics = RibbitLayoutMetrics(
                windowWidth: proxy.size.width,
                projectTextScale: settings.projectRailTextSize / 12,
                tabTextScale: settings.tabTextSize / 12,
                fileTextScale: settings.filesTextSize / 11
            )

            HStack(spacing: 0) {
                ProjectRail(model: model, settings: settings, metrics: metrics)
                    .frame(width: metrics.projectRailWidth)

                Divider().overlay(RibbitTheme.rule)

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        TabStrip(model: model, settings: settings, metrics: metrics)
                        Divider().overlay(RibbitTheme.rule)
                        WorkspaceModeControl(model: model)
                            .padding(.horizontal, 8)
                    }
                    .frame(height: metrics.tabBarHeight)
                    .background(RibbitTheme.surface)
                    Divider().overlay(RibbitTheme.rule)
                    WorkspaceCanvas(
                        model: model,
                        settings: settings,
                        viewportSize: CGSize(
                            width: max(
                                1,
                                proxy.size.width
                                    - metrics.projectRailWidth
                                    - metrics.inspectorWidth
                                    - 2
                            ),
                            height: max(
                                1,
                                proxy.size.height - metrics.tabBarHeight - 1
                            )
                        )
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().overlay(RibbitTheme.rule)

                FileInspector(model: model, settings: settings, metrics: metrics)
                    .frame(width: metrics.inspectorWidth)
            }
            .background(
                settings.glassySurfacesEnabled
                    ? Color.clear
                    : RibbitTheme.canvas
            )
            .font(.system(size: settings.tabTextSize, weight: .regular, design: .default))
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct WorkspaceModeControl: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(WorkspaceMode.allCases) { mode in
                Button {
                    model.setWorkspaceMode(mode)
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 30, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.workspaceMode == mode ? RibbitTheme.ink : RibbitTheme.muted)
                .background(model.workspaceMode == mode ? RibbitTheme.raised : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .help(mode == .tabs ? "tab mode" : "canvas mode")
            }
        }
    }
}

private struct ProjectRail: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let metrics: RibbitLayoutMetrics

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: RibbitTheme.Space.xs) {
                FrogMascotView(pixelSize: 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ribbit")
                        .font(.system(size: max(13, settings.projectRailTextSize + 1), weight: .semibold, design: .monospaced))
                        .foregroundStyle(RibbitTheme.ink)
                    if !metrics.isNarrow {
                        Text(model.workspaceDisplayName)
                            .lineLimit(1)
                            .foregroundStyle(RibbitTheme.muted)
                    }
                }
                Spacer()
            }
            .padding(.top, 44)
            .padding(.horizontal, RibbitTheme.Space.sm)
            .padding(.bottom, RibbitTheme.Space.md)
            .overlay {
                RibbitWindowDragRegion {
                    model.focusSelectedTerminal()
                }
            }

            HStack(spacing: 0) {
                Menu {
                    Button {
                        model.selectBaseWorkspace()
                    } label: {
                        Label("base", systemImage: model.selectedProjectID == nil ? "checkmark" : "house")
                    }

                    if !model.projects.isEmpty {
                        Divider()
                    }
                    ForEach(model.projects) { project in
                        Button {
                            model.selectProject(project)
                        } label: {
                            Label(project.name, systemImage: model.selectedProjectID == project.id ? "checkmark" : "folder")
                        }
                    }
                    Divider()
                    Button("new project…", systemImage: "folder.badge.plus") {
                        model.createProjectManually()
                    }
                    Button("ribbit in existing folder…", systemImage: "folder") {
                        model.chooseProjectFolder()
                    }
                } label: {
                    HStack(spacing: RibbitTheme.Space.xs) {
                        Image(systemName: model.selectedProjectID == nil ? "house" : "folder")
                            .foregroundStyle(RibbitTheme.accent)
                        Text(model.workspaceDisplayName)
                            .lineLimit(1)
                            .frame(maxWidth: metrics.projectRailWidth - 76, alignment: .leading)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(RibbitTheme.muted)
                    }
                    .frame(height: 30, alignment: .leading)
                }
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, RibbitTheme.Space.sm)
            .padding(.bottom, RibbitTheme.Space.sm)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.visibleTabs) { tab in
                        Button {
                            model.activateTab(tab)
                        } label: {
                            HStack(spacing: RibbitTheme.Space.xs) {
                                Image(systemName: tab.kind.systemImage)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(tab.kind == .terminal ? tab.terminalTint.color : RibbitTheme.muted)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Text(tab.title)
                                            .lineLimit(1)
                                        if tab.isDirty {
                                            Circle().fill(RibbitTheme.accent).frame(width: 5, height: 5)
                                        }
                                        if let session = tab.agentSession {
                                            AgentStatusBadge(
                                                session: session,
                                                compact: true,
                                                onActivate: {
                                                    model.focusAgentSession(session)
                                                }
                                            )
                                        }
                                    }
                                    if metrics.showsSessionMetadata {
                                        Text(tab.kind == .terminal ? (tab.terminalSession?.currentDirectory ?? model.projectURL.path) : (tab.fileURL?.deletingLastPathComponent().path ?? "scratch note"))
                                            .font(.system(size: max(9, settings.projectRailTextSize - 2)))
                                            .foregroundStyle(RibbitTheme.muted)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                if model.selectedTabID == tab.id, metrics.showsShortcutHints {
                                    Text(tab.kind == .terminal ? "⌘T" : "⌘N")
                                        .font(.system(size: max(9, settings.projectRailTextSize - 2), design: .monospaced))
                                        .foregroundStyle(RibbitTheme.muted)
                                }
                            }
                            .padding(.horizontal, RibbitTheme.Space.xs)
                            .frame(height: metrics.sessionRowHeight)
                        }
                        .buttonStyle(RibbitButtonStyle(selected: model.selectedTabID == tab.id))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .contextMenu {
                            if tab.kind == .terminal {
                                Button("save transcript as note", systemImage: "text.page.badge.magnifyingglass") {
                                    model.saveTerminalJournal(tab, requestedName: nil)
                                }
                                .disabled(tab.projectID == nil)
                                Button("rename terminal…", systemImage: "pencil") {
                                    model.promptToRenameTerminal(tab)
                                }
                                Menu("color", systemImage: "paintpalette") {
                                    ForEach(TerminalTint.allCases) { tint in
                                        Button {
                                            model.setTerminalTint(tint, for: tab)
                                        } label: {
                                            Label(tint.rawValue, systemImage: tab.terminalTint == tint ? "checkmark.circle.fill" : "circle")
                                        }
                                    }
                                }
                                Divider()
                            }
                            Button("close tab") { model.closeTab(tab) }
                        }
                    }

                    if !model.visibleUnmatchedAgentSessions.isEmpty {
                        Divider()
                            .overlay(RibbitTheme.rule)
                            .padding(.vertical, 6)

                        Text("external agents")
                            .font(.system(
                                size: max(9, settings.projectRailTextSize - 2),
                                weight: .semibold,
                                design: .monospaced
                            ))
                            .foregroundStyle(RibbitTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, RibbitTheme.Space.xs)

                        ForEach(model.visibleUnmatchedAgentSessions) { session in
                            HStack(spacing: 4) {
                                Button {
                                    model.focusAgentSession(session)
                                } label: {
                                    HStack(spacing: RibbitTheme.Space.xs) {
                                        AgentStatusBadge(
                                            session: session,
                                            compact: true
                                        )
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(session.project)
                                                .lineLimit(1)
                                                .foregroundStyle(RibbitTheme.ink)
                                            Text(session.activity)
                                                .font(.system(
                                                    size: max(9, settings.projectRailTextSize - 2)
                                                ))
                                                .lineLimit(1)
                                                .foregroundStyle(RibbitTheme.muted)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    model.pinAgent(session)
                                } label: {
                                    Image(systemName: model.isAgentPinned(session)
                                        ? "pin.fill"
                                        : "pin")
                                        .font(.system(size: 10, weight: .medium))
                                        .frame(width: 28, height: 28)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(model.isAgentPinned(session)
                                    ? RibbitTheme.accent
                                    : RibbitTheme.muted)
                                .help(model.isAgentPinned(session)
                                    ? "show pinned agent on canvas"
                                    : "pin agent to canvas")
                            }
                            .padding(.horizontal, RibbitTheme.Space.xs)
                            .frame(height: metrics.sessionRowHeight)
                            .background(RibbitTheme.raised.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .draggable(session.id)
                        }
                    }
                }
                .padding(.horizontal, RibbitTheme.Space.sm)
            }

            Divider().overlay(RibbitTheme.rule)

            HStack(spacing: 4) {
                Menu {
                    Button("new terminal", systemImage: "terminal") { model.newTerminal() }
                    Button("new note", systemImage: "doc.plaintext") { model.newNote() }
                    Divider()
                    Button("new project…", systemImage: "folder.badge.plus") { model.createProjectManually() }
                } label: {
                    Label("new", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, RibbitTheme.Space.sm)
                        .frame(height: 36)
                }
                .menuStyle(.borderlessButton)
                .foregroundStyle(RibbitTheme.ink)

                Button { model.chooseProjectFolder() } label: {
                    Image(systemName: "folder.badge.gearshape")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(RibbitTheme.muted)
                .help("ribbit in existing folder — ⌘O")
            }
            .padding(.horizontal, RibbitTheme.Space.xs)
        }
        .font(.system(size: settings.projectRailTextSize))
        .background {
            if settings.glassySurfacesEnabled {
                RibbitSidebarGlassSurface(
                    opacity: settings.sidebarOpacity,
                    blur: settings.sidebarBlur,
                    blendingMode: .behindWindow
                )
            } else {
                RibbitTheme.sidebar
            }
        }
    }
}

private struct TabStrip: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let metrics: RibbitLayoutMetrics

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.visibleTabs) { tab in
                    HStack(spacing: 8) {
                        Image(systemName: tab.kind.systemImage)
                            .foregroundStyle(tab.kind == .terminal ? tab.terminalTint.color : RibbitTheme.muted)
                        Text(tab.title)
                            .lineLimit(1)
                        if tab.isDirty {
                            Circle().fill(RibbitTheme.accent).frame(width: 5, height: 5)
                        }
                        if let session = tab.agentSession {
                            AgentStatusBadge(
                                session: session,
                                onActivate: {
                                    model.focusAgentSession(session)
                                }
                            )
                        }
                        Button { model.closeTab(tab) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(RibbitTheme.muted)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 8)
                    .frame(
                        minWidth: metrics.tabMinimumWidth,
                        maxWidth: metrics.tabMaximumWidth,
                        minHeight: max(28, metrics.tabBarHeight - 12)
                    )
                    .background(model.selectedTabID == tab.id ? RibbitTheme.raised : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(alignment: .bottom) {
                        if tab.kind == .terminal, model.selectedTabID == tab.id {
                            Rectangle()
                                .fill(tab.terminalTint.color)
                                .frame(height: 2)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.activateTab(tab) }
                    .contextMenu {
                        if tab.kind == .terminal {
                            Button("save transcript as note", systemImage: "text.page.badge.magnifyingglass") {
                                model.saveTerminalJournal(tab, requestedName: nil)
                            }
                            .disabled(tab.projectID == nil)
                            Button("rename terminal…", systemImage: "pencil") {
                                model.promptToRenameTerminal(tab)
                            }
                            Menu("color", systemImage: "paintpalette") {
                                ForEach(TerminalTint.allCases) { tint in
                                    Button {
                                        model.setTerminalTint(tint, for: tab)
                                    } label: {
                                        Label(tint.rawValue, systemImage: tab.terminalTint == tint ? "checkmark.circle.fill" : "circle")
                                    }
                                }
                            }
                            Divider()
                        }
                        Button("close tab") { model.closeTab(tab) }
                    }
                }

                Button { model.newTerminal() } label: {
                    Image(systemName: "plus")
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(RibbitTheme.muted)
                .help("new terminal — ⌘T")
            }
            .padding(.leading, 12)
            .padding(.trailing, 20)
            .padding(.top, 8)
        }
        .font(.system(size: settings.tabTextSize))
        .background(RibbitTheme.surface)
    }
}

private struct WorkspaceCanvas: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let viewportSize: CGSize

    var body: some View {
        Group {
            if model.workspaceMode == .canvas {
                TerminalCanvasWorkspace(
                    model: model,
                    settings: settings,
                    viewportSize: viewportSize
                )
                    .id(model.selectedProjectID?.uuidString ?? "base")
            } else if let tab = model.selectedTab {
                switch tab.kind {
                case .terminal:
                    if let session = tab.terminalSession {
                        ZStack(alignment: .top) {
                            TerminalRepresentable(session: session, settings: settings)
                                .id(tab.id)
                                .padding([.top, .leading], RibbitTheme.Space.xs)
                            if let message = session.recoveryState.message {
                                TerminalRecoveryBanner(
                                    message: message,
                                    actionTitle: model.canResumeProviderSession(in: tab)
                                        ? "resume \(tab.lastKnownAgent?.displayName ?? "agent")"
                                        : nil,
                                    onAction: {
                                        model.resumeProviderSession(in: tab)
                                    },
                                    onDismiss: session.dismissRecoveryNotice
                                )
                                .padding(10)
                            }
                        }
                        .background(RibbitTheme.canvas)
                    }
                case .note:
                    NoteEditor(text: Binding(
                        get: { tab.text },
                        set: { model.updateNoteText($0, for: tab) }
                    ), fontSize: settings.editorTextSize) {
                        tab.isDirty = true
                    }
                }
            } else {
                VStack(spacing: 16) {
                    FrogMascotView(pixelSize: 8)
                    Text("open a terminal or note")
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundStyle(RibbitTheme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(RibbitTheme.canvas)
    }
}

struct TerminalRecoveryBanner: View {
    let message: String
    var actionTitle: String?
    var onAction: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(RibbitTheme.ink)
            Spacer(minLength: 8)
            if let actionTitle {
                Button(actionTitle) { onAction?() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Button("dismiss", action: onDismiss)
                .buttonStyle(.plain)
                .foregroundStyle(RibbitTheme.muted)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        .background(RibbitTheme.raised.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.orange.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }
}
