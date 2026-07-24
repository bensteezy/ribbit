import AppKit
import Foundation

@MainActor
final class TerminalSession: NSObject, ObservableObject {
    let id: UUID
    let view: RibbitGhosttyView
    let journal: TerminalJournal?
    let backend: TerminalBackend
    @Published private(set) var title: String
    @Published private(set) var currentDirectory: String
    @Published private(set) var isRunning = true
    @Published private(set) var recoveryState: TerminalRecoveryState
    var onSaveRequested: ((String?) -> Void)?
    var onMetadataChanged: (() -> Void)?

    private var requestTimer: Timer?
    private var journalTimer: Timer?
    private var previousSnapshot = ""

    init(
        id: UUID = UUID(),
        title: String,
        directory: URL,
        projectID: UUID? = nil,
        projectRootURL: URL? = nil,
        projectNotesURL: URL? = nil,
        supportURL: URL = TerminalSession.defaultSupportURL,
        fontSize: Double = 14,
        backendPreference: TerminalBackendPreference = .automatic,
        restoring: Bool = false
    ) {
        self.id = id
        self.title = title
        self.currentDirectory = directory.path
        let resolvedProjectRoot = (projectRootURL ?? directory).standardizedFileURL
        let contextIndexURL = RibbitContextIndexWriter.indexURL(
            supportURL: supportURL,
            projectID: projectID,
            terminalID: id
        )
        var persistentSessionEnvironment = [
            "RIBBIT_PROJECT_ROOT": resolvedProjectRoot.path,
            "RIBBIT_CONTEXT_INDEX": contextIndexURL.path
        ]
        if let terminfoURL = GhosttyResources.terminfoURL() {
            persistentSessionEnvironment["TERMINFO"] = terminfoURL.path
        }
        let resolvedBackend = TerminalBackend.resolve(
            preference: backendPreference,
            projectID: projectID,
            terminalID: id,
            workingDirectory: directory,
            sessionEnvironment: persistentSessionEnvironment
        )
        self.backend = resolvedBackend
        self.recoveryState = resolvedBackend.recoveryState(restoring: restoring)
        let workspaceName = projectID?.uuidString.lowercased() ?? "base"
        self.journal = try? TerminalJournal(
            directoryURL: supportURL
                .appendingPathComponent("sessions", isDirectory: true)
                .appendingPathComponent(workspaceName, isDirectory: true)
                .appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        )

        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "TERM")
        environment.removeValue(forKey: "COLORTERM")
        environment["RIBBIT"] = "1"
        if let terminfoURL = GhosttyResources.terminfoURL() {
            environment["TERMINFO"] = terminfoURL.path
        }
        environment["RIBBIT_TERMINAL_ID"] = id.uuidString.lowercased()
        environment["RIBBIT_PROJECT"] = projectID == nil ? "0" : "1"
        environment["RIBBIT_PROJECT_ID"] = projectID?.uuidString.lowercased() ?? "base"
        environment["RIBBIT_PROJECT_ROOT"] = resolvedProjectRoot.path
        environment["RIBBIT_TERMINAL_BACKEND"] = backend.displayName
        environment["RIBBIT_CONTEXT_INDEX"] = contextIndexURL.path
        if let tmuxSessionName = backend.tmuxSessionName {
            environment["RIBBIT_TMUX_SESSION"] = tmuxSessionName
        }
        if let journal {
            environment["RIBBIT_SAVE_REQUEST"] = journal.requestURL.path
        }
        if let commandBinURL = try? RibbitCommandInstaller.install(in: supportURL) {
            let inheritedPath = environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = "\(commandBinURL.path):\(inheritedPath)"
        }

        self.view = RibbitGhosttyView(
            directory: directory,
            fontSize: fontSize,
            environment: environment,
            command: backend.launchCommand
        )
        super.init()

        view.attachmentDirectoryURL = projectNotesURL?
            .appendingPathComponent("attachments", isDirectory: true)
            ?? supportURL
                .appendingPathComponent("attachments", isDirectory: true)
                .appendingPathComponent("base", isDirectory: true)
        view.autoresizingMask = [.width, .height]
        view.onTitleChanged = { [weak self] value in
            self?.title = value.isEmpty ? "terminal" : value
        }
        view.onDirectoryChanged = { [weak self] value in
            self?.currentDirectory = value.removingPercentEncoding ?? value
            self?.onMetadataChanged?()
        }
        view.onProcessExit = { [weak self] in
            self?.processTerminated()
        }

        journalTimer = Timer.scheduledTimer(
            timeInterval: 0.75,
            target: self,
            selector: #selector(captureJournalSnapshot),
            userInfo: nil,
            repeats: true
        )
        if projectID != nil, journal != nil {
            requestTimer = Timer.scheduledTimer(
                timeInterval: 0.35,
                target: self,
                selector: #selector(checkForSaveRequest),
                userInfo: nil,
                repeats: true
            )
        }
    }

    static var defaultSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ribbit", isDirectory: true)
    }

    func focus() {
        view.window?.makeFirstResponder(view)
    }

    func applyAppearance(fontSize: Double) {
        view.updateAppearance(fontSize: fontSize)
    }

    func showFind() {
        view.showFind()
    }

    func sendInput(_ text: String) {
        view.sendText(text)
    }

    func clearScreen() {
        view.clearScreen()
    }

    func dismissRecoveryNotice() {
        recoveryState = .none
    }

    func terminate() {
        captureJournalSnapshot()
        requestTimer?.invalidate()
        journalTimer?.invalidate()
        view.terminate()
        backend.terminate()
    }

    func transcript() -> String {
        captureJournalSnapshot()
        return journal?.transcript() ?? ""
    }

    @objc private func checkForSaveRequest() {
        guard case let .save(name)? = journal?.consumeSaveRequest() else { return }
        captureJournalSnapshot()
        onSaveRequested?(name)
    }

    @objc private func captureJournalSnapshot() {
        let current = view.readJournalText()
        guard !current.isEmpty else { return }
        let delta = TerminalSnapshotDelta.delta(previous: previousSnapshot, current: current)
        previousSnapshot = current
        if !delta.isEmpty {
            journal?.append(Data(delta.utf8))
        }
    }

    private func processTerminated() {
        captureJournalSnapshot()
        requestTimer?.invalidate()
        journalTimer?.invalidate()
        isRunning = false
    }
}

enum TerminalSnapshotDelta {
    static func delta(previous: String, current: String) -> String {
        guard !current.isEmpty, current != previous else { return "" }
        guard !previous.isEmpty else { return current.hasSuffix("\n") ? current : current + "\n" }
        if current.hasPrefix(previous) {
            return String(current.dropFirst(previous.count))
        }

        let old = Array(previous.utf8)
        let new = Array(current.utf8)
        let maximum = min(old.count, new.count)
        if maximum > 0 {
            for length in stride(from: maximum, through: 1, by: -1)
            where old.suffix(length).elementsEqual(new.prefix(length)) {
                return String(decoding: new.dropFirst(length), as: UTF8.self)
            }
        }
        return "\n" + current
    }
}
