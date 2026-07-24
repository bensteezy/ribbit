import AppKit
import Foundation

enum TerminalBackendPreference: Equatable {
    case automatic
    case directShell
}

enum TerminalBackend: Equatable {
    case directShell
    case tmux(TmuxTerminalBackend)

    static func resolve(
        preference: TerminalBackendPreference,
        projectID: UUID?,
        terminalID: UUID,
        workingDirectory: URL,
        sessionEnvironment: [String: String] = [:]
    ) -> TerminalBackend {
        guard preference == .automatic,
              let installation = TmuxInstallation.discover()
        else { return .directShell }

        return .tmux(TmuxTerminalBackend(
            installation: installation,
            socketName: "ribbit",
            sessionName: TmuxTerminalBackend.sessionName(
                projectID: projectID,
                terminalID: terminalID
            ),
            workingDirectory: workingDirectory,
            sessionEnvironment: sessionEnvironment
        ))
    }

    var launchCommand: String? {
        switch self {
        case .directShell: nil
        case .tmux(let backend): backend.launchCommand
        }
    }

    var displayName: String {
        switch self {
        case .directShell: "direct"
        case .tmux: "tmux"
        }
    }

    var tmuxSessionName: String? {
        guard case .tmux(let backend) = self else { return nil }
        return backend.sessionName
    }

    func terminate() {
        guard case .tmux(let backend) = self else { return }
        _ = backend.terminate()
    }

    func recoveryState(restoring: Bool) -> TerminalRecoveryState {
        guard restoring else { return .none }
        switch self {
        case .directShell:
            return .persistenceUnavailable
        case .tmux(let backend):
            return backend.hasSession() ? .none : .tmuxSessionRecreated
        }
    }
}

enum TerminalRecoveryState: Equatable {
    case none
    case tmuxSessionRecreated
    case persistenceUnavailable

    var message: String? {
        switch self {
        case .none:
            nil
        case .tmuxSessionRecreated:
            "the previous tmux session ended. ribbit restored this terminal as a new shell."
        case .persistenceUnavailable:
            "tmux is unavailable. ribbit restored the terminal layout, but the previous process ended."
        }
    }
}

struct TmuxInstallation: Equatable {
    let executableURL: URL

    static func discover(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        standardCandidates: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/tmux"),
            URL(fileURLWithPath: "/usr/local/bin/tmux"),
            URL(fileURLWithPath: "/usr/bin/tmux")
        ]
    ) -> TmuxInstallation? {
        let pathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map {
                URL(fileURLWithPath: String($0), isDirectory: true)
                    .appendingPathComponent("tmux", isDirectory: false)
            }

        var visited = Set<String>()
        for candidate in pathCandidates + standardCandidates {
            let path = candidate.standardizedFileURL.path
            guard visited.insert(path).inserted,
                  FileManager.default.isExecutableFile(atPath: path)
            else { continue }
            return TmuxInstallation(executableURL: URL(fileURLWithPath: path))
        }
        return nil
    }

    func version() -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["-V"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

@MainActor
final class TmuxStatusModel: ObservableObject {
    enum Availability: Equatable {
        case available(path: String, version: String?)
        case unavailable
    }

    static let installationCommand = "brew install tmux"

    @Published private(set) var availability: Availability = .unavailable
    private let discover: () -> TmuxInstallation?

    init(discover: @escaping () -> TmuxInstallation? = { TmuxInstallation.discover() }) {
        self.discover = discover
        recheck()
    }

    func recheck() {
        guard let installation = discover() else {
            availability = .unavailable
            return
        }
        availability = .available(
            path: installation.executableURL.path,
            version: installation.version()
        )
    }

    func copyInstallationCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.installationCommand, forType: .string)
    }
}

struct TmuxTerminalBackend: Equatable {
    let installation: TmuxInstallation
    let socketName: String
    let sessionName: String
    let workingDirectory: URL
    let sessionEnvironment: [String: String]

    init(
        installation: TmuxInstallation,
        socketName: String,
        sessionName: String,
        workingDirectory: URL,
        sessionEnvironment: [String: String] = [:]
    ) {
        self.installation = installation
        self.socketName = socketName
        self.sessionName = sessionName
        self.workingDirectory = workingDirectory
        self.sessionEnvironment = sessionEnvironment
    }

    static func sessionName(projectID: UUID?, terminalID: UUID) -> String {
        let projectKey = projectID?.uuidString.lowercased() ?? "base"
        return "ribbit-\(projectKey)-\(terminalID.uuidString.lowercased())"
    }

    var launchArguments: [String] {
        let terminalID = String(sessionName.suffix(36))
        var arguments = [
            "-L", socketName,
            "start-server",
            ";",
            "set-option", "-g", "mouse", "on",
            ";",
            "new-session", "-A",
            "-e", "RIBBIT=1",
            "-e", "RIBBIT_TERMINAL_ID=\(terminalID)"
        ]
        for (key, value) in sessionEnvironment.sorted(by: { $0.key < $1.key }) {
            arguments.append(contentsOf: ["-e", "\(key)=\(value)"])
        }
        arguments.append(contentsOf: [
            "-s", sessionName,
            "-c", workingDirectory.standardizedFileURL.path
        ])
        return arguments
    }

    var launchCommand: String {
        ([installation.executableURL.path] + launchArguments)
            .map(AgentTerminalInput.shellEscaped)
            .joined(separator: " ")
    }

    func hasSession() -> Bool {
        run(["has-session", "-t", "=\(sessionName)"]) == 0
    }

    @discardableResult
    func createDetached() -> Bool {
        run([
            "start-server",
            ";",
            "set-option", "-g", "mouse", "on",
            ";",
            "new-session", "-d",
            "-s", sessionName,
            "-c", workingDirectory.standardizedFileURL.path
        ]) == 0
    }

    func isMouseModeEnabled() -> Bool {
        output(["show-options", "-gv", "mouse"]) == "on"
    }

    @discardableResult
    func terminate() -> Bool {
        let status = run(["kill-session", "-t", "=\(sessionName)"])
        return status == 0 || status == 1
    }

    private func run(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = installation.executableURL
        process.arguments = ["-L", socketName] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    private func output(_ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = installation.executableURL
        process.arguments = ["-L", socketName] + arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(
                decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
