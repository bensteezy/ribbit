import Foundation
import Testing

struct RibbitEventIntegrationTests {
    @Test func codexDesktopGetsCodexDeepLinkDestination() throws {
        let target = try focusTarget(
            provider: "codex",
            environment: [
                "TERM_PROGRAM": "",
                "TTY": "",
                "RIBBIT_TERMINAL_ID": "",
                "TMUX": "",
            ]
        )

        #expect(target["surface"] as? String == "codex")
        #expect(target["applicationName"] as? String == "ChatGPT")
    }

    @Test func ribbitTerminalIdentityTakesPriority() throws {
        let terminalID = "22222222-2222-2222-2222-222222222222"
        let target = try focusTarget(
            provider: "codex",
            environment: [
                "RIBBIT_TERMINAL_ID": terminalID,
                "TERM_PROGRAM": "",
                "TTY": "",
            ]
        )

        #expect(target["surface"] as? String == "ribbit")
        #expect(target["terminalSessionID"] as? String == terminalID)
    }

    @Test func appleTerminalGetsExactTTYDestination() throws {
        let target = try focusTarget(
            provider: "codex",
            environment: [
                "TERM_PROGRAM": "Apple_Terminal",
                "TTY": "/dev/ttys999",
                "TERM_SESSION_ID": "terminal-session-1",
                "RIBBIT_TERMINAL_ID": "",
                "TMUX": "",
            ]
        )

        #expect(target["surface"] as? String == "terminal")
        #expect(target["tty"] as? String == "/dev/ttys999")
        #expect((target["processID"] as? Int).map { $0 > 0 } == true)
    }

    @Test func claudeStopFailureBecomesReadyWithTheErrorVisible() throws {
        let event = try normalizedEvent(
            provider: "claude",
            raw: [
                "session_id": "claude-session-1",
                "hook_event_name": "StopFailure",
                "cwd": "/tmp/ribbit",
                "message": "rate limit reached",
            ]
        )

        #expect(event["id"] as? String == "claude:claude-session-1")
        #expect(event["state"] as? String == "paused")
        #expect(event["activity"] as? String == "rate limit reached")
    }

    private func focusTarget(
        provider: String,
        environment overrides: [String: String]
    ) throws -> [String: Any] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let integration = repositoryRoot
            .appendingPathComponent("integrations/ribbit_event.py")
        let command = """
        import importlib.util, json
        spec = importlib.util.spec_from_file_location("ribbit_event", \(String(reflecting: integration.path)))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        print(json.dumps(module.focus_target(\(String(reflecting: provider)), "/tmp/ribbit")))
        """
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", command]
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in overrides {
            if value.isEmpty {
                environment.removeValue(forKey: key)
            } else {
                environment[key] = value
            }
        }
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            throw IntegrationError.failed(String(decoding: data, as: UTF8.self))
        }
        return object
    }

    private func normalizedEvent(
        provider: String,
        raw: [String: String]
    ) throws -> [String: Any] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let integration = repositoryRoot
            .appendingPathComponent("integrations/ribbit_event.py")
        let rawData = try JSONSerialization.data(withJSONObject: raw)
        let rawJSON = String(decoding: rawData, as: UTF8.self)
        let command = """
        import importlib.util, json
        spec = importlib.util.spec_from_file_location("ribbit_event", \(String(reflecting: integration.path)))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        print(json.dumps(module.normalized_event(json.loads(\(String(reflecting: rawJSON))), \(String(reflecting: provider)))))
        """
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", command]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            throw IntegrationError.failed(String(decoding: data, as: UTF8.self))
        }
        return object
    }

    private enum IntegrationError: Error {
        case failed(String)
    }
}
