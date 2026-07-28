import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var tabs: [RibbitTab] = []
    @Published var selectedTabID: UUID?
    @Published var projectURL: URL
    @Published private(set) var projects: [RibbitProject] = []
    @Published private(set) var selectedProjectID: UUID?
    @Published private(set) var workspaceMode: WorkspaceMode = .tabs
    @Published private(set) var canvasCamera: CanvasCamera = .initial
    @Published private(set) var contextEdges: [ContextEdge] = []
    @Published private(set) var externalAgentPins: [ExternalAgentPin] = []
    @Published var selectedContextEdgeID: UUID?
    let agentMonitor: RibbitAgentMonitor
    private let agentNotifier = RibbitAgentNotifier()

    private let registryURL: URL
    private let workspaceDirectoryURL: URL
    private let journalSupportURL: URL
    private let settings: AppSettings
    private let terminalBackendPreference: TerminalBackendPreference
    private var selectedTabIDsByWorkspace: [String: UUID] = [:]
    private var workspaceModes: [String: WorkspaceMode] = [:]
    private var canvasCameras: [String: CanvasCamera] = [:]
    private var contextEdgesByWorkspace: [String: [ContextEdge]] = [:]
    private var externalAgentPinsByWorkspace: [String: [ExternalAgentPin]] = [:]
    private var loadedWorkspaceKeys = Set<String>()

    init(
        projectURL: URL? = nil,
        registryURL: URL? = nil,
        workspaceDirectoryURL: URL? = nil,
        journalSupportURL: URL? = nil,
        settings: AppSettings = .shared,
        terminalBackendPreference: TerminalBackendPreference = .automatic
    ) {
        self.registryURL = registryURL ?? Self.defaultRegistryURL
        if let workspaceDirectoryURL {
            self.workspaceDirectoryURL = workspaceDirectoryURL
        } else if projectURL != nil, registryURL == nil {
            self.workspaceDirectoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ribbit-workspaces-\(UUID().uuidString)", isDirectory: true)
        } else {
            self.workspaceDirectoryURL = self.registryURL.deletingLastPathComponent()
                .appendingPathComponent("workspaces", isDirectory: true)
        }
        if let journalSupportURL {
            self.journalSupportURL = journalSupportURL
        } else if registryURL != nil || workspaceDirectoryURL != nil {
            self.journalSupportURL = self.registryURL.deletingLastPathComponent()
                .appendingPathComponent("journal-support", isDirectory: true)
        } else {
            self.journalSupportURL = TerminalSession.defaultSupportURL
        }
        self.settings = settings
        self.terminalBackendPreference = terminalBackendPreference
        self.agentMonitor = RibbitAgentMonitor()

        let registry = projectURL == nil || registryURL != nil
            ? Self.loadRegistry(from: self.registryURL)
            : nil
        let loadedProjects = registry?.projects.filter {
            FileManager.default.fileExists(atPath: $0.rootPath)
        } ?? []
        let restoredProject = loadedProjects.first { $0.id == registry?.selectedProjectID }
        projects = loadedProjects
        selectedProjectID = restoredProject?.id

        if let projectURL {
            self.projectURL = projectURL.standardizedFileURL
        } else if let restoredProject {
            self.projectURL = restoredProject.rootURL
        } else {
            self.projectURL = FileManager.default.homeDirectoryForCurrentUser
            selectedProjectID = nil
        }
        loadWorkspaceIfNeeded()
        restoreWorkspaceState()
        if visibleTabs.isEmpty { newTerminal() }
        agentNotifier.onActivate = { [weak self] sessionID in
            Task { @MainActor in
                guard let session = self?.agentMonitor.sessions.first(where: {
                    $0.id == sessionID
                }) else { return }
                self?.focusAgentSession(session)
            }
        }
    }

    func startAgentMonitoring() {
        agentMonitor.start(
            terminalIdentities: { [weak self] in
                self?.terminalIdentities ?? []
            },
            onAssignmentsChanged: { [weak self] assignments in
                self?.applyAgentAssignments(assignments)
            },
            onTransition: { [weak self] transition in
                guard self?.settings.agentNotificationsEnabled == true else { return }
                self?.agentNotifier.notify(transition)
            }
        )
    }

    func stopAgentMonitoring() {
        agentMonitor.stop()
    }

    private var terminalIdentities: [RibbitTerminalIdentity] {
        tabs.compactMap { tab in
            guard tab.kind == .terminal, let session = tab.terminalSession else { return nil }
            let root = projects.first(where: { $0.id == tab.projectID })?.rootPath
                ?? FileManager.default.homeDirectoryForCurrentUser.path
            return RibbitTerminalIdentity(
                id: tab.id,
                projectID: tab.projectID,
                workingDirectory: session.currentDirectory,
                projectRoot: root
            )
        }
    }

    private func applyAgentAssignments(
        _ assignments: [UUID: RibbitAgentSession]
    ) {
        var updatedRecoveryMetadata = false
        for tab in tabs where tab.kind == .terminal {
            let assignment = assignments[tab.id]
            tab.agentSession = assignment
            if let assignment,
               tab.lastKnownAgent != assignment.agent
                || tab.providerSessionID != assignment.routableProviderSessionID {
                tab.lastKnownAgent = assignment.agent
                tab.providerSessionID = assignment.routableProviderSessionID
                updatedRecoveryMetadata = true
            }
        }
        refreshExternalAgentPins()
        if updatedRecoveryMetadata { persistCurrentWorkspace() }
        objectWillChange.send()
    }

    var visibleUnmatchedAgentSessions: [RibbitAgentSession] {
        agentMonitor.unmatchedSessions
    }

    func isAgentPinned(_ session: RibbitAgentSession) -> Bool {
        externalAgentPins.contains { $0.session.id == session.id }
    }

    func pinAgent(
        _ session: RibbitAgentSession,
        at canvasPoint: CGPoint? = nil
    ) {
        if let index = externalAgentPins.firstIndex(where: {
            $0.session.id == session.id
        }) {
            if let canvasPoint {
                externalAgentPins[index].canvasFrame.x = canvasPoint.x
                externalAgentPins[index].canvasFrame.y = canvasPoint.y
                externalAgentPinsByWorkspace[workspaceKey] = externalAgentPins
                persistCurrentWorkspace()
            }
            setWorkspaceMode(.canvas)
            return
        }
        var frame = CanvasNodeFrame.initialExternalAgent(
            index: visibleTabs.count + externalAgentPins.count
        )
        if let canvasPoint {
            frame.x = canvasPoint.x
            frame.y = canvasPoint.y
        }
        let pin = ExternalAgentPin(
            session: session,
            canvasFrame: frame
        )
        externalAgentPins.append(pin)
        externalAgentPinsByWorkspace[workspaceKey] = externalAgentPins
        setWorkspaceMode(.canvas)
        persistCurrentWorkspace()
    }

    func unpinAgent(_ pin: ExternalAgentPin) {
        externalAgentPins.removeAll { $0.id == pin.id }
        externalAgentPinsByWorkspace[workspaceKey] = externalAgentPins
        persistCurrentWorkspace()
    }

    func canvasFrame(for nodeID: UUID) -> CanvasNodeFrame? {
        visibleTabs.first { $0.id == nodeID }?.canvasFrame
            ?? externalAgentPins.first { $0.id == nodeID }?.canvasFrame
    }

    func updateExternalAgentPinFrame(
        _ frame: CanvasNodeFrame,
        for pin: ExternalAgentPin
    ) {
        guard let index = externalAgentPins.firstIndex(where: { $0.id == pin.id }) else {
            return
        }
        externalAgentPins[index].canvasFrame = frame
        externalAgentPinsByWorkspace[workspaceKey] = externalAgentPins
        persistCurrentWorkspace()
    }

    func focusAgentPin(_ pin: ExternalAgentPin) {
        let current = agentMonitor.sessions.first { $0.id == pin.session.id }
            ?? pin.session
        focusAgentSession(current)
    }

    private func refreshExternalAgentPins() {
        var changed = false
        for index in externalAgentPins.indices {
            guard let current = agentMonitor.sessions.first(where: {
                $0.id == externalAgentPins[index].session.id
            }), current != externalAgentPins[index].session else { continue }
            externalAgentPins[index].session = current
            changed = true
        }
        guard changed else { return }
        externalAgentPinsByWorkspace[workspaceKey] = externalAgentPins
        persistCurrentWorkspace()
    }

    func focusAgentSession(_ session: RibbitAgentSession) {
        if session.focusTarget?.surface.routesOutsideRibbit == true {
            RibbitAgentFocusRouter.focusExternal(session)
            return
        }

        if let tab = tabs.first(where: {
            $0.agentSession?.id == session.id
                || (
                    $0.lastKnownAgent == session.agent
                        && $0.providerSessionID == session.routableProviderSessionID
                )
        }) {
            if tab.projectID != selectedProjectID {
                if let projectID = tab.projectID,
                   let project = projects.first(where: { $0.id == projectID }) {
                    activateProject(project)
                } else {
                    selectBaseWorkspace()
                }
            }
            selectTab(tab)
            RibbitWindowConfigurator.showMainWindow()
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                tab.terminalSession?.focus()
            }
            return
        }
        RibbitAgentFocusRouter.focusExternal(session)
    }

    func resumeProviderSession(in tab: RibbitTab) {
        guard let agent = tab.lastKnownAgent,
              let command = RibbitProviderResume.command(
                  agent: agent,
                  sessionID: tab.providerSessionID
              ),
              let terminal = tab.terminalSession
        else { return }
        selectTab(tab)
        terminal.sendInput(command + "\r")
        terminal.dismissRecoveryNotice()
        DispatchQueue.main.async { terminal.focus() }
    }

    func canResumeProviderSession(in tab: RibbitTab) -> Bool {
        guard let agent = tab.lastKnownAgent else { return false }
        return RibbitProviderResume.command(
            agent: agent,
            sessionID: tab.providerSessionID
        ) != nil
    }

    private static var defaultRegistryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ribbit", isDirectory: true)
            .appendingPathComponent("projects.json", isDirectory: false)
    }

    var selectedProject: RibbitProject? {
        projects.first { $0.id == selectedProjectID }
    }

    var selectedTab: RibbitTab? {
        visibleTabs.first { $0.id == selectedTabID }
    }

    var visibleTabs: [RibbitTab] {
        tabs.filter { $0.projectID == selectedProjectID }
    }

    var workspaceDisplayName: String {
        selectedProject?.name ?? "base"
    }

    func newTerminal(at directory: URL? = nil) {
        let number = visibleTabs.filter { $0.kind == .terminal }.count + 1
        let title = number == 1 ? "terminal" : "terminal \(number)"
        let id = UUID()
        let session = makeTerminalSession(
            id: id,
            title: title,
            directory: directory ?? projectURL
        )
        let tab = RibbitTab(
            id: id,
            kind: .terminal,
            projectID: selectedProjectID,
            title: title,
            canvasFrame: CanvasNodeFrame.initial(kind: .terminal, index: visibleTabs.count),
            terminalSession: session
        )
        connect(session, to: tab)
        tabs.append(tab)
        selectTab(tab)
        persistCurrentWorkspace()
    }

    func newNote() {
        let number = visibleTabs.filter { $0.kind == .note }.count + 1
        let fallbackTitle = number == 1 ? "untitled.txt" : "untitled \(number).txt"
        var destination: URL?

        if let project = selectedProject {
            do {
                try ensureNotesDirectory(for: project)
                destination = availableNoteURL(in: project.notesURL)
                try "".write(to: destination!, atomically: true, encoding: .utf8)
            } catch {
                presentError(error, message: "ribbit couldn’t create this note.")
            }
        }

        let tab = RibbitTab(
            kind: .note,
            projectID: selectedProjectID,
            title: destination?.lastPathComponent ?? fallbackTitle,
            canvasFrame: CanvasNodeFrame.initial(kind: .note, index: visibleTabs.count),
            fileURL: destination
        )
        tabs.append(tab)
        selectTab(tab)
        persistCurrentWorkspace()
    }

    func selectTab(_ tab: RibbitTab) {
        guard tab.projectID == selectedProjectID else { return }
        guard selectedTabID != tab.id else { return }
        selectedTabID = tab.id
        selectedTabIDsByWorkspace[workspaceKey] = tab.id
        persistCurrentWorkspace()
    }

    func activateTab(_ tab: RibbitTab) {
        selectTab(tab)
        focusSelectedTerminal()
    }

    func setWorkspaceMode(_ mode: WorkspaceMode) {
        workspaceMode = mode
        workspaceModes[workspaceKey] = mode
        persistCurrentWorkspace()
    }

    func resetCanvasLayout() {
        for (index, tab) in visibleTabs.enumerated() {
            tab.canvasFrame = CanvasNodeFrame.initial(kind: tab.kind, index: index)
        }
        for index in externalAgentPins.indices {
            externalAgentPins[index].canvasFrame = .initialExternalAgent(
                index: visibleTabs.count + index
            )
        }
        externalAgentPinsByWorkspace[workspaceKey] = externalAgentPins
        objectWillChange.send()
        persistCurrentWorkspace()
    }

    func addContextLink(from source: RibbitTab, to target: RibbitTab) {
        guard source.id != target.id,
              source.projectID == selectedProjectID,
              target.projectID == selectedProjectID,
              !contextEdges.contains(where: {
                  $0.sourceTabID == source.id && $0.targetTabID == target.id
              }) else { return }
        let edge = ContextEdge(sourceTabID: source.id, targetTabID: target.id)
        contextEdges.append(edge)
        contextEdgesByWorkspace[workspaceKey] = contextEdges
        selectedContextEdgeID = edge.id
        persistCurrentWorkspace()
    }

    func selectContextEdge(_ edge: ContextEdge) {
        selectedContextEdgeID = edge.id
    }

    func removeContextEdge(_ edge: ContextEdge) {
        contextEdges.removeAll { $0.id == edge.id }
        contextEdgesByWorkspace[workspaceKey] = contextEdges
        if selectedContextEdgeID == edge.id { selectedContextEdgeID = nil }
        persistCurrentWorkspace()
    }

    func removeContextLinks(for tab: RibbitTab) {
        contextEdges.removeAll {
            $0.sourceTabID == tab.id || $0.targetTabID == tab.id
        }
        contextEdgesByWorkspace[workspaceKey] = contextEdges
        persistCurrentWorkspace()
    }

    func updateNoteText(_ text: String, for tab: RibbitTab) {
        guard tab.kind == .note, tab.projectID == selectedProjectID else { return }
        tab.text = text
        tab.isDirty = true
        persistCurrentWorkspace()
    }

    func updateCanvasFrame(_ frame: CanvasNodeFrame, for tab: RibbitTab) {
        guard tab.projectID == selectedProjectID else { return }
        tab.canvasFrame = frame
        persistCurrentWorkspace()
    }

    func setCanvasCamera(_ camera: CanvasCamera) {
        canvasCamera = CanvasCamera(
            x: camera.x,
            y: camera.y,
            zoom: min(
                CanvasInteractionMetrics.maximumZoom,
                max(CanvasInteractionMetrics.minimumZoom, camera.zoom)
            )
        )
        canvasCameras[workspaceKey] = canvasCamera
        persistCurrentWorkspace()
    }

    func promptToRenameTerminal(_ tab: RibbitTab) {
        guard tab.kind == .terminal else { return }
        let alert = NSAlert()
        alert.messageText = "rename terminal"
        alert.addButton(withTitle: "rename")
        alert.addButton(withTitle: "cancel")
        let nameField = NSTextField(string: tab.title)
        nameField.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = nameField
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        renameTerminal(tab, to: nameField.stringValue)
    }

    func renameTerminal(_ tab: RibbitTab, to proposedTitle: String) {
        guard tab.kind == .terminal else { return }
        let title = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        tab.title = title
        objectWillChange.send()
        persistCurrentWorkspace()
    }

    func setTerminalTint(_ tint: TerminalTint, for tab: RibbitTab) {
        guard tab.kind == .terminal else { return }
        tab.terminalTint = tint
        objectWillChange.send()
        persistCurrentWorkspace()
    }

    func closeTab(_ tab: RibbitTab) {
        if tab.kind == .note, tab.isDirty {
            let alert = NSAlert()
            alert.messageText = "save changes to \(tab.title)?"
            alert.informativeText = "closing this note without saving will discard your changes."
            alert.addButton(withTitle: "save")
            alert.addButton(withTitle: "don’t save")
            alert.addButton(withTitle: "cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                guard save(tab) else { return }
            case .alertSecondButtonReturn:
                break
            default:
                return
            }
        }
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        removeContextLinks(for: tab)
        tab.terminalSession?.terminate()
        tabs.remove(at: index)
        if selectedTabID == tab.id {
            selectedTabID = visibleTabs.last?.id
            selectedTabIDsByWorkspace[workspaceKey] = selectedTabID
        }
        persistCurrentWorkspace()
    }

    func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.title = "open a project in ribbit"
        panel.prompt = "open project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = projectURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ribbitHere(url)
    }

    func createProjectManually() {
        let panel = NSOpenPanel()
        panel.title = "choose where to create the project"
        panel.prompt = "choose location"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = projectURL
        guard panel.runModal() == .OK, let parentURL = panel.url else { return }

        let alert = NSAlert()
        alert.messageText = "new ribbit project"
        alert.informativeText = "name the project folder. ribbit will add ribbit-notes inside it."
        alert.addButton(withTitle: "create")
        alert.addButton(withTitle: "cancel")
        let nameField = NSTextField(string: "new-project")
        nameField.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = nameField
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else {
            presentMessage("use a project name without slashes.")
            return
        }

        let rootURL = parentURL.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
            ribbitHere(rootURL)
        } catch {
            presentError(error, message: "ribbit couldn’t create that project.")
        }
    }

    func ribbitHere(_ rootURL: URL) {
        let rootURL = rootURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            presentMessage("choose a folder for this ribbit project.")
            return
        }

        do {
            let project: RibbitProject
            if let index = projects.firstIndex(where: { $0.rootURL == rootURL }) {
                projects[index].lastOpenedAt = .now
                try ensureNotesDirectory(for: projects[index])
                project = projects[index]
            } else {
                project = RibbitProject(rootURL: rootURL)
                try ensureNotesDirectory(for: project)
                projects.insert(project, at: 0)
            }
            activateProject(project)
        } catch {
            presentError(error, message: "ribbit couldn’t dock in that folder.")
        }
    }

    func selectProject(_ project: RibbitProject) {
        guard FileManager.default.fileExists(atPath: project.rootPath) else {
            presentMessage("that project folder is no longer available.")
            return
        }
        activateProject(project)
    }

    func selectBaseWorkspace() {
        persistCurrentWorkspace()
        rememberSelectedTab()
        selectedProjectID = nil
        projectURL = FileManager.default.homeDirectoryForCurrentUser
        loadWorkspaceIfNeeded()
        restoreWorkspaceState()
        persistProjects()
        if visibleTabs.isEmpty { newTerminal() }
    }

    func openFile(_ url: URL) {
        if let existing = visibleTabs.first(where: { $0.fileURL == url }) {
            selectTab(existing)
            return
        }
        guard let data = try? Data(contentsOf: url),
              data.count < 10_000_000,
              let value = String(data: data, encoding: .utf8) else {
            NSWorkspace.shared.open(url)
            return
        }
        let tab = RibbitTab(
            kind: .note,
            projectID: selectedProjectID,
            title: url.lastPathComponent,
            text: value,
            canvasFrame: CanvasNodeFrame.initial(kind: .note, index: visibleTabs.count),
            fileURL: url
        )
        tabs.append(tab)
        selectTab(tab)
        persistCurrentWorkspace()
    }

    func saveSelectedNote() {
        guard let tab = selectedTab, tab.kind == .note else { return }
        _ = save(tab)
    }

    func findInSelectedTerminal() {
        guard let session = selectedTab?.terminalSession else { return }
        session.showFind()
    }

    func focusSelectedTerminal() {
        guard let session = selectedTab?.terminalSession else { return }
        DispatchQueue.main.async {
            session.focus()
        }
    }

    func closeSelectedTab() {
        guard let selectedTab else { return }
        closeTab(selectedTab)
    }

    func selectTab(at index: Int) {
        guard visibleTabs.indices.contains(index) else { return }
        selectTab(visibleTabs[index])
    }

    func selectNextTab() {
        cycleSelectedTab(by: 1)
    }

    func selectPreviousTab() {
        cycleSelectedTab(by: -1)
    }

    private func cycleSelectedTab(by offset: Int) {
        guard !visibleTabs.isEmpty else { return }
        let current = visibleTabs.firstIndex { $0.id == selectedTabID } ?? 0
        let next = (current + offset + visibleTabs.count) % visibleTabs.count
        selectTab(visibleTabs[next])
    }

    func adjustTerminalFontSize(by delta: Double) {
        settings.terminalTextSize = min(22, max(11, settings.terminalTextSize + delta))
        for tab in tabs where tab.kind == .terminal {
            tab.terminalSession?.applyAppearance(fontSize: settings.terminalTextSize)
        }
    }

    func resetTerminalFontSize() {
        settings.terminalTextSize = 14
        for tab in tabs where tab.kind == .terminal {
            tab.terminalSession?.applyAppearance(fontSize: settings.terminalTextSize)
        }
    }

    func clearSelectedTerminal() {
        selectedTab?.terminalSession?.clearScreen()
    }

    func saveSelectedTerminalAsNote() {
        guard let tab = selectedTab, tab.kind == .terminal else { return }
        saveTerminalJournal(tab, requestedName: nil)
    }

    @discardableResult
    func saveTerminalJournal(
        _ tab: RibbitTab,
        requestedName: String?,
        now: Date = .now
    ) -> URL? {
        guard tab.kind == .terminal, let session = tab.terminalSession else { return nil }
        guard let projectID = tab.projectID,
              let project = projects.first(where: { $0.id == projectID }) else {
            presentMessage("attach this terminal to a project before saving its transcript.")
            return nil
        }

        do {
            try ensureNotesDirectory(for: project)
            let transcript = session.transcript()
            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                presentMessage("this terminal doesn’t have any text to save yet.")
                return nil
            }

            let destination = availableTranscriptURL(
                in: project.notesURL,
                terminalTitle: requestedName ?? tab.title,
                date: now
            )
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let noteText = """
            ribbit terminal transcript
            terminal: \(tab.title)
            saved: \(formatter.string(from: now))

            \(transcript)
            """
            try noteText.write(to: destination, atomically: true, encoding: .utf8)

            let note = RibbitTab(
                kind: .note,
                projectID: projectID,
                title: destination.lastPathComponent,
                text: noteText,
                canvasFrame: CanvasNodeFrame.initial(kind: .note, index: visibleTabs.count),
                fileURL: destination
            )
            tabs.append(note)
            if selectedProjectID == projectID {
                selectTab(note)
            }
            persistWorkspace(projectID: projectID)
            return destination
        } catch {
            presentError(error, message: "ribbit couldn’t save that terminal transcript.")
            return nil
        }
    }

    @discardableResult
    private func save(_ tab: RibbitTab) -> Bool {
        let destination: URL
        if let fileURL = tab.fileURL {
            destination = fileURL
        } else {
            let panel = NSSavePanel()
            panel.title = "save note"
            panel.nameFieldStringValue = tab.title
            panel.directoryURL = selectedProject?.notesURL ?? projectURL
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            destination = url
        }
        do {
            try tab.text.write(to: destination, atomically: true, encoding: .utf8)
            tab.fileURL = destination
            tab.title = destination.lastPathComponent
            tab.isDirty = false
            persistCurrentWorkspace()
            return true
        } catch {
            presentError(error, message: "ribbit couldn’t save this note.")
            return false
        }
    }

    private func ensureNotesDirectory(for project: RibbitProject) throws {
        try FileManager.default.createDirectory(
            at: project.notesURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func availableNoteURL(in directory: URL) -> URL {
        let base = directory.appendingPathComponent("untitled.txt")
        guard FileManager.default.fileExists(atPath: base.path) else { return base }
        var number = 2
        while true {
            let candidate = directory.appendingPathComponent("untitled-\(number).txt")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    private func availableTranscriptURL(in directory: URL, terminalTitle: String, date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let requestedSlug = terminalTitle
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        let slug = requestedSlug.isEmpty ? "terminal" : requestedSlug
        let stem = "\(formatter.string(from: date))-\(slug)"
        var destination = directory.appendingPathComponent("\(stem).txt")
        var copy = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(stem)-\(copy).txt")
            copy += 1
        }
        return destination
    }

    private func sortAndPersistProjects() {
        projects.sort { $0.lastOpenedAt > $1.lastOpenedAt }
        persistProjects()
    }

    private var workspaceKey: String {
        workspaceKey(for: selectedProjectID)
    }

    private func workspaceKey(for projectID: UUID?) -> String {
        projectID?.uuidString.lowercased() ?? "base"
    }

    private func rememberSelectedTab() {
        if let selectedTabID {
            selectedTabIDsByWorkspace[workspaceKey] = selectedTabID
        }
    }

    private func restoreSelectedTab() {
        let savedID = selectedTabIDsByWorkspace[workspaceKey]
        selectedTabID = visibleTabs.first { $0.id == savedID }?.id ?? visibleTabs.first?.id
        selectedTabIDsByWorkspace[workspaceKey] = selectedTabID
    }

    private func restoreWorkspaceState() {
        workspaceMode = workspaceModes[workspaceKey] ?? .tabs
        canvasCamera = canvasCameras[workspaceKey] ?? .initial
        contextEdges = contextEdgesByWorkspace[workspaceKey] ?? []
        externalAgentPins = externalAgentPinsByWorkspace[workspaceKey] ?? []
        selectedContextEdgeID = nil
        restoreSelectedTab()
    }

    private func activateProject(_ project: RibbitProject) {
        persistCurrentWorkspace()
        rememberSelectedTab()
        selectedProjectID = project.id
        projectURL = project.rootURL
        loadWorkspaceIfNeeded()
        restoreWorkspaceState()
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index].lastOpenedAt = .now
        }
        sortAndPersistProjects()
        if visibleTabs.isEmpty { newTerminal() }
    }

    private func makeTerminalSession(
        id: UUID,
        title: String,
        directory: URL,
        restoring: Bool = false
    ) -> TerminalSession {
        TerminalSession(
            id: id,
            title: title,
            directory: directory,
            projectID: selectedProjectID,
            projectRootURL: selectedProject?.rootURL
                ?? FileManager.default.homeDirectoryForCurrentUser,
            projectNotesURL: selectedProject?.notesURL,
            supportURL: journalSupportURL,
            fontSize: settings.terminalTextSize,
            backendPreference: terminalBackendPreference,
            restoring: restoring
        )
    }

    private func connect(_ session: TerminalSession, to tab: RibbitTab) {
        session.view.onActivated = { [weak self, weak tab] in
            guard let self, let tab, tab.projectID == self.selectedProjectID else { return }
            if self.selectedTabID != tab.id {
                self.selectTab(tab)
            }
        }
        session.onSaveRequested = { [weak self, weak tab] requestedName in
            guard let self, let tab else { return }
            self.saveTerminalJournal(tab, requestedName: requestedName)
        }
        session.onMetadataChanged = { [weak self] in
            self?.persistCurrentWorkspace()
        }
    }

    private func loadWorkspaceIfNeeded() {
        let key = workspaceKey
        guard loadedWorkspaceKeys.insert(key).inserted else { return }
        guard let document = loadWorkspaceDocument(for: selectedProjectID) else {
            workspaceModes[key] = .tabs
            canvasCameras[key] = .initial
            contextEdgesByWorkspace[key] = []
            externalAgentPinsByWorkspace[key] = []
            return
        }

        workspaceModes[key] = document.mode
        canvasCameras[key] = document.camera
        contextEdgesByWorkspace[key] = document.contextEdges
        externalAgentPinsByWorkspace[key] = document.externalAgentPins
        selectedTabIDsByWorkspace[key] = document.selectedTabID

        for record in document.tabs {
            let tab: RibbitTab
            switch record.kind {
            case .terminal:
                let requestedDirectory = record.terminalDirectoryPath.map {
                    URL(fileURLWithPath: $0, isDirectory: true)
                }
                let directory = requestedDirectory.flatMap {
                    FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
                } ?? projectURL
                let session = makeTerminalSession(
                    id: record.id,
                    title: record.title,
                    directory: directory,
                    restoring: true
                )
                tab = RibbitTab(
                    id: record.id,
                    kind: .terminal,
                    projectID: selectedProjectID,
                    title: record.title,
                    terminalTint: record.terminalTint,
                    canvasFrame: record.canvasFrame,
                    terminalSession: session,
                    lastKnownAgent: record.lastKnownAgent,
                    providerSessionID: record.providerSessionID
                )
                connect(session, to: tab)

            case .note:
                let fileURL = record.filePath.map {
                    URL(fileURLWithPath: $0, isDirectory: false)
                }
                tab = RibbitTab(
                    id: record.id,
                    kind: .note,
                    projectID: selectedProjectID,
                    title: record.title,
                    text: record.text,
                    terminalTint: record.terminalTint,
                    canvasFrame: record.canvasFrame,
                    fileURL: fileURL
                )
                tab.isDirty = record.isDirty
            }
            tabs.append(tab)
        }
    }

    private func persistCurrentWorkspace() {
        persistWorkspace(projectID: selectedProjectID)
    }

    private func persistWorkspace(projectID: UUID?) {
        let key = workspaceKey(for: projectID)
        guard loadedWorkspaceKeys.contains(key) else { return }
        let workspaceTabs = tabs.filter { $0.projectID == projectID }
        let records = workspaceTabs.map { tab in
            WorkspaceTabRecord(
                id: tab.id,
                kind: tab.kind,
                title: tab.title,
                text: tab.kind == .note ? tab.text : "",
                isDirty: tab.kind == .note && tab.isDirty,
                terminalTint: tab.terminalTint,
                canvasFrame: tab.canvasFrame,
                filePath: tab.fileURL?.path,
                terminalDirectoryPath: tab.terminalSession?.currentDirectory,
                lastKnownAgent: tab.lastKnownAgent,
                providerSessionID: tab.providerSessionID
            )
        }
        let document = WorkspaceDocument(
            selectedTabID: selectedTabIDsByWorkspace[key],
            mode: workspaceModes[key] ?? .tabs,
            camera: canvasCameras[key] ?? .initial,
            tabs: records,
            contextEdges: contextEdgesByWorkspace[key] ?? [],
            externalAgentPins: externalAgentPinsByWorkspace[key] ?? []
        )

        do {
            try FileManager.default.createDirectory(
                at: workspaceDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try JSONEncoder().encode(document)
            try data.write(to: workspaceDocumentURL(for: projectID), options: .atomic)
            try persistContextIndexes(projectID: projectID, tabs: workspaceTabs)
        } catch {
            presentError(error, message: "ribbit couldn’t save this workspace.")
        }
    }

    private func persistContextIndexes(
        projectID: UUID?,
        tabs workspaceTabs: [RibbitTab]
    ) throws {
        let key = workspaceKey(for: projectID)
        let edges = contextEdgesByWorkspace[key] ?? []
        let tabsByID = Dictionary(uniqueKeysWithValues: workspaceTabs.map { ($0.id, $0) })
        let terminals = workspaceTabs.filter { $0.kind == .terminal }

        for note in workspaceTabs where note.kind == .note {
            let snapshotURL = RibbitContextIndexWriter.noteSnapshotURL(
                supportURL: journalSupportURL,
                projectID: projectID,
                noteID: note.id
            )
            try FileManager.default.createDirectory(
                at: snapshotURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try note.text.write(to: snapshotURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: snapshotURL.path
            )
        }

        for terminal in terminals {
            let entries = edges
                .filter { $0.targetTabID == terminal.id }
                .compactMap { edge -> RibbitContextEntry? in
                    guard let source = tabsByID[edge.sourceTabID] else { return nil }
                    let contentURL: URL?
                    switch source.kind {
                    case .terminal:
                        contentURL = source.terminalSession?.journal?.directoryURL
                    case .note:
                        contentURL = RibbitContextIndexWriter.noteSnapshotURL(
                            supportURL: journalSupportURL,
                            projectID: projectID,
                            noteID: source.id
                        )
                    }
                    guard let contentURL else { return nil }
                    return RibbitContextEntry(
                        id: source.id,
                        title: source.title,
                        kind: source.kind,
                        contentPath: contentURL.path
                    )
                }
            let index = RibbitContextIndex(
                targetTerminalID: terminal.id,
                links: entries
            )
            let indexURL = RibbitContextIndexWriter.indexURL(
                supportURL: journalSupportURL,
                projectID: projectID,
                terminalID: terminal.id
            )
            try FileManager.default.createDirectory(
                at: indexURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try JSONEncoder().encode(index).write(to: indexURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: indexURL.path
            )
        }
    }

    private func loadWorkspaceDocument(for projectID: UUID?) -> WorkspaceDocument? {
        let url = workspaceDocumentURL(for: projectID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let document = try JSONDecoder().decode(WorkspaceDocument.self, from: data)
            guard (1...WorkspaceDocument.currentVersion).contains(document.version) else {
                return nil
            }
            return document
        } catch {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let recoveryURL = url
                .deletingPathExtension()
                .appendingPathExtension("corrupt-\(formatter.string(from: .now)).json")
            try? FileManager.default.moveItem(at: url, to: recoveryURL)
            return nil
        }
    }

    private func workspaceDocumentURL(for projectID: UUID?) -> URL {
        workspaceDirectoryURL
            .appendingPathComponent(workspaceKey(for: projectID), isDirectory: false)
            .appendingPathExtension("json")
    }

    private func persistProjects() {
        do {
            try FileManager.default.createDirectory(
                at: registryURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder().encode(ProjectRegistry(
                projects: projects,
                selectedProjectID: selectedProjectID
            ))
            try data.write(to: registryURL, options: .atomic)
        } catch {
            presentError(error, message: "ribbit couldn’t save the project list.")
        }
    }

    private static func loadRegistry(from url: URL) -> ProjectRegistry? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProjectRegistry.self, from: data)
    }

    private func presentMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "ok")
        alert.runModal()
    }

    private func presentError(_ error: Error, message: String) {
        let alert = NSAlert(error: error)
        alert.messageText = message
        alert.runModal()
    }
}
