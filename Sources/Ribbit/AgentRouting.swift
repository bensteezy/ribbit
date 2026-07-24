import AppKit
import Foundation
import UserNotifications

enum RibbitProviderResume {
    static func command(agent: RibbitAgentKind, sessionID: String?) -> String? {
        guard let sessionID = RibbitAgentSession.canonicalProviderSessionID(
            sessionID,
            agent: agent
        ) else { return nil }
        let quoted = shellQuote(sessionID)
        switch agent {
        case .codex:
            return "codex resume \(quoted)"
        case .claude:
            return "claude --resume \(quoted)"
        case .cursor:
            return nil
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

@MainActor
enum RibbitAgentFocusRouter {
    static func focusExternal(_ session: RibbitAgentSession) {
        guard let target = session.focusTarget else {
            if let sourceURL = session.sourceURL {
                NSWorkspace.shared.open(sourceURL.deletingLastPathComponent())
            }
            return
        }

        if target.surface == .codex,
           let url = codexURL(for: session),
           NSWorkspace.shared.open(url) {
            return
        }
        if target.surface == .iTerm,
           let sessionID = target.iTermSessionID,
           let escaped = sessionID.addingPercentEncoding(
               withAllowedCharacters: .urlQueryAllowed
           ),
           let url = URL(string: "iterm2:///reveal?sessionid=\(escaped)") {
            NSWorkspace.shared.open(url)
            return
        }
        if target.surface == .iTerm {
            _ = selectTmuxPane(target)
            activate(applicationNamed: target.applicationName ?? "iTerm2")
            return
        }
        if target.surface == .terminal {
            _ = selectTmuxPane(target)
            if let tty = target.tty, focusTerminalTab(tty: tty) {
                return
            }
            activate(applicationNamed: target.applicationName ?? "Terminal")
            return
        }
        if target.surface == .cursor {
            if let url = URL(string: "cursor://") {
                NSWorkspace.shared.open(url)
            }
            activate(applicationNamed: target.applicationName ?? "Cursor")
            return
        }
        activate(applicationNamed: target.applicationName)
    }

    nonisolated static func codexURL(for session: RibbitAgentSession) -> URL? {
        guard session.agent == .codex,
              let sessionID = session.routableProviderSessionID,
              let escaped = sessionID.addingPercentEncoding(
                  withAllowedCharacters: .urlPathAllowed
              )
        else { return nil }
        return URL(string: "codex://threads/\(escaped)")
    }

    @discardableResult
    private static func activate(applicationNamed name: String?) -> Bool {
        guard let name, !name.isEmpty,
              let application = NSWorkspace.shared.runningApplications.first(where: {
                  $0.localizedName == name
              })
        else { return false }
        application.activate(options: [.activateAllWindows])
        return true
    }

    @discardableResult
    private static func selectTmuxPane(_ target: RibbitSessionFocusTarget) -> Bool {
        guard let tmuxTarget = target.tmuxTarget,
              let executable = tmuxExecutable() else { return false }
        let socketArguments = target.tmuxSocketPath.map { ["-S", $0] } ?? []
        let windowTarget = tmuxTarget.split(separator: ".", maxSplits: 1)
            .first.map(String.init) ?? tmuxTarget
        let commands = [
            socketArguments + ["select-window", "-t", windowTarget],
            socketArguments + ["select-pane", "-t", tmuxTarget],
        ]
        for arguments in commands {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return false }
            } catch {
                return false
            }
        }
        return true
    }

    private static func tmuxExecutable() -> URL? {
        [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ].first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }).map { URL(fileURLWithPath: $0) }
    }

    private static func focusTerminalTab(tty: String) -> Bool {
        let target = appleScriptLiteral(tty)
        let source = """
        tell application "Terminal"
            activate
            repeat with targetWindow in windows
                repeat with targetTab in tabs of targetWindow
                    if tty of targetTab is \(target) then
                        set selected tab of targetWindow to targetTab
                        set index of targetWindow to 1
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil && result?.booleanValue == true
    }

    private static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

struct RibbitAgentTransition: Equatable {
    var ready: [RibbitAgentSession]
    var needsAttention: [RibbitAgentSession]

    var isEmpty: Bool { ready.isEmpty && needsAttention.isEmpty }

    static func detect(
        previous: [RibbitAgentSession],
        current: [RibbitAgentSession]
    ) -> RibbitAgentTransition {
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let ready = current.filter {
            $0.state == .paused && previousByID[$0.id]?.isLive == true
        }
        let attention = current.filter {
            $0.needsAttention && previousByID[$0.id]?.needsAttention != true
        }
        return RibbitAgentTransition(ready: ready, needsAttention: attention)
    }
}

final class RibbitAgentNotifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private static let sessionIDKey = "sessionID"
    private var center: UNUserNotificationCenter?
    var onActivate: ((String) -> Void)?

    init(center: UNUserNotificationCenter? = nil) {
        self.center = center
        super.init()
        center?.delegate = self
    }

    func notify(_ transition: RibbitAgentTransition) {
        guard !transition.isEmpty else { return }
        let center = center ?? UNUserNotificationCenter.current()
        self.center = center
        center.delegate = self
        center.requestAuthorization(options: [.alert]) { [weak self] granted, _ in
            guard granted else { return }
            for session in transition.needsAttention {
                self?.deliver(
                    title: "\(session.agent.displayName) needs you",
                    body: "\(session.project) · \(session.activity)",
                    session: session,
                    kind: "attention"
                )
            }
            for session in transition.ready {
                self?.deliver(
                    title: "\(session.agent.displayName) is ready",
                    body: "\(session.project) · click to return",
                    session: session,
                    kind: "ready"
                )
            }
        }
    }

    private func deliver(
        title: String,
        body: String,
        session: RibbitAgentSession,
        kind: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "ribbit.agent-\(kind)"
        content.userInfo = [Self.sessionIDKey: session.id]
        center?.add(UNNotificationRequest(
            identifier: "ribbit.\(kind).\(UUID().uuidString)",
            content: content,
            trigger: nil
        ))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let sessionID = response.notification.request.content
            .userInfo[Self.sessionIDKey] as? String {
            onActivate?(sessionID)
        }
        completionHandler()
    }
}
