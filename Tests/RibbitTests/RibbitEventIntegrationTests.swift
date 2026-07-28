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

    @Test func claudePermissionCarriesAnActionableExactItem() throws {
        let event = try normalizedEvent(
            provider: "claude",
            raw: [
                "session_id": "claude-session-1",
                "hook_event_name": "PermissionRequest",
                "tool_name": "Bash",
                "cwd": "/tmp/ribbit",
                "tool_input": ["command": "git status --short"],
            ]
        )

        #expect(event["approvalID"] as? String != nil)
        #expect(event["approvalToolName"] as? String == "Bash")
        #expect(event["approvalSummary"] as? String == "git status --short")
        #expect(event["conversationRole"] as? String == "status")
        #expect(
            (event["conversationText"] as? String)?
                .contains("git status --short") == true
        )
    }

    @Test func userPromptBecomesACompactConversationItem() throws {
        let event = try normalizedEvent(
            provider: "claude",
            raw: [
                "session_id": "claude-session-1",
                "hook_event_name": "UserPromptSubmit",
                "cwd": "/tmp/ribbit",
                "prompt": "Please inspect the failing hook.",
            ]
        )

        #expect(event["conversationRole"] as? String == "user")
        #expect(event["conversationText"] as? String == "Please inspect the failing hook.")
    }

    @Test func claudePermissionResponseEmitsTheOfficialHookDecision() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let integration = repositoryRoot
            .appendingPathComponent("integrations/ribbit_event.py")
        let command = """
        import contextlib, http.server, importlib.util, io, json, sys, threading
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                self.rfile.read(length)
                body = json.dumps({"decision": "allow"}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            def log_message(self, format, *args):
                pass
        server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.handle_request, daemon=True).start()
        spec = importlib.util.spec_from_file_location("ribbit_event", \(String(reflecting: integration.path)))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.BRIDGE_URL = f"http://127.0.0.1:{server.server_port}/v1/events"
        sys.argv = ["ribbit_event.py", "claude"]
        sys.stdin = io.StringIO(json.dumps({
            "session_id": "session-1",
            "hook_event_name": "PermissionRequest",
            "tool_name": "Bash",
            "tool_input": {"command": "pwd"},
            "cwd": "/tmp/ribbit"
        }))
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = module.main()
        print(json.dumps({"status": status, "output": json.loads(output.getvalue())}))
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
        let result = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let hookOutput = try #require(result["output"] as? [String: Any])
        let specific = try #require(
            hookOutput["hookSpecificOutput"] as? [String: Any]
        )
        let decision = try #require(specific["decision"] as? [String: Any])

        #expect(process.terminationStatus == 0)
        #expect(result["status"] as? Int == 0)
        #expect(specific["hookEventName"] as? String == "PermissionRequest")
        #expect(decision["behavior"] as? String == "allow")
    }

    @Test func claudeSubagentToolBecomesACanvasActivity() throws {
        let event = try normalizedEvent(
            provider: "claude",
            raw: [
                "session_id": "claude-session-1",
                "hook_event_name": "PreToolUse",
                "tool_name": "Agent",
                "tool_use_id": "tool-42",
                "cwd": "/tmp/ribbit",
                "tool_input": [
                    "subagent_type": "general-purpose",
                    "description": "scan running processes",
                ],
            ]
        )

        #expect(event["canvasAction"] as? String == "start")
        #expect(event["canvasActivityID"] as? String == "tool-42")
        #expect(event["canvasActivityKind"] as? String == "subagent")
        #expect(event["canvasActivityType"] as? String == "general-purpose")
        #expect(event["canvasTask"] as? String == "scan running processes")
    }

    @Test func claudeCronToolBecomesAPersistentCanvasActivity() throws {
        let event = try normalizedEvent(
            provider: "claude",
            raw: [
                "session_id": "claude-session-1",
                "hook_event_name": "PreToolUse",
                "tool_name": "CronCreate",
                "cwd": "/tmp/ribbit",
                "tool_input": [
                    "cron": "*/5 * * * *",
                    "prompt": "scan the system",
                ],
            ]
        )

        #expect(event["canvasAction"] as? String == "start")
        #expect(event["canvasActivityKind"] as? String == "cron")
        #expect(event["canvasSchedule"] as? String == "*/5 * * * *")
        #expect(event["canvasTask"] as? String == "scan the system")
    }

    @Test func codexShellCrontabBecomesAPersistentCanvasActivity() throws {
        let event = try normalizedEvent(
            provider: "codex",
            raw: [
                "session_id": "codex-session-1",
                "hook_event_name": "PreToolUse",
                "tool_name": "Bash",
                "cwd": "/tmp/ribbit",
                "tool_input": [
                    "command": """
                    printf '%s\\n' '21 11 * * 5 /usr/bin/touch "/tmp/cron complete"' | /usr/bin/crontab -
                    """,
                ],
            ]
        )

        #expect(event["canvasAction"] as? String == "start")
        #expect(event["canvasActivityKind"] as? String == "cron")
        #expect(event["canvasSchedule"] as? String == "21 11 * * 5")
        #expect(event["canvasTask"] as? String == #"/usr/bin/touch "/tmp/cron complete""#)
    }

    @Test func readingCrontabDoesNotCreateACanvasActivity() throws {
        let event = try normalizedEvent(
            provider: "codex",
            raw: [
                "session_id": "codex-session-1",
                "hook_event_name": "PreToolUse",
                "tool_name": "Bash",
                "cwd": "/tmp/ribbit",
                "tool_input": ["command": "/usr/bin/crontab -l"],
            ]
        )

        #expect(event["canvasAction"] == nil)
    }

    @Test func hookInstallerRunsWithTheRestrictedGUIAppPath() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = repositoryRoot
            .appendingPathComponent("scripts/install-ribbit-hooks.sh")
        let temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbit-hook-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryHome) }
        try FileManager.default.createDirectory(
            at: temporaryHome,
            withIntermediateDirectories: true
        )

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path, "--dry-run"]
        process.environment = [
            "HOME": temporaryHome.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )

        #expect(process.terminationStatus == 0)
        #expect(text.contains("claude:"))
        #expect(text.contains("codex:"))
        #expect(text.contains("cursor:"))

        let install = Process()
        let installOutput = Pipe()
        install.executableURL = URL(fileURLWithPath: "/bin/zsh")
        install.arguments = [script.path, "--install"]
        install.environment = [
            "HOME": temporaryHome.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        install.standardOutput = installOutput
        install.standardError = installOutput
        try install.run()
        install.waitUntilExit()
        let settingsURL = temporaryHome.appendingPathComponent(".claude/settings.json")
        let settings = try JSONSerialization.jsonObject(
            with: Data(contentsOf: settingsURL)
        ) as? [String: Any]
        let hooks = settings?["hooks"] as? [String: Any]
        let permissionGroups = hooks?["PermissionRequest"] as? [[String: Any]]
        let permissionHooks = permissionGroups?.first?["hooks"] as? [[String: Any]]
        #expect(permissionHooks?.first?["timeout"] as? Int == 305)
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
        raw: [String: Any]
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
