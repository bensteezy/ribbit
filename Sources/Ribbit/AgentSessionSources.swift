import Foundation

struct RibbitLocalSessionFileSource {
    let agent: RibbitAgentKind
    let root: URL

    func scan(now: Date = .now) -> [RibbitAgentSession] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }

        return recentSessionFiles(now: now).compactMap { url in
            guard let modificationDate = modificationDate(for: url) else { return nil }
            let summary = RibbitSessionEventSummary.parse(
                ribbitHead(of: url) + "\n" + ribbitTail(of: url)
            )
            let providerSessionID = agent == .codex
                ? codexNavigationSessionID(from: url)
                    ?? inferredCodexSessionID(from: url)
                : summary.sessionID
            let cursorWorkspace = agent == .cursor
                ? RibbitCursorWorkspaceIndex.workspace(for: url)
                : nil
            let project = summary.project
                ?? cursorWorkspace?.lastPathComponent
                ?? projectName(from: url)
            let focusTarget: RibbitSessionFocusTarget
            switch agent {
            case .cursor:
                focusTarget = RibbitSessionFocusTarget(
                    surface: .cursor,
                    applicationName: "Cursor",
                    workingDirectory: cursorWorkspace?.path
                )
            case .codex:
                focusTarget = RibbitSessionFocusTarget(
                    surface: .codex,
                    applicationName: "Codex"
                )
            case .claude:
                focusTarget = RibbitSessionFocusTarget(
                    surface: .application,
                    applicationName: "Terminal"
                )
            }

            return RibbitAgentSession(
                id: "\(agent.rawValue):\(providerSessionID ?? url.path)",
                providerSessionID: providerSessionID,
                agent: agent,
                title: "\(agent.displayName) session",
                project: project,
                activity: summary.activity,
                state: summary.state(modifiedAt: modificationDate, now: now),
                lastUpdated: modificationDate,
                sourceURL: url,
                isBridgeSession: false,
                attentionKind: summary.attentionKind,
                attentionDetail: summary.attentionDetail,
                focusTarget: focusTarget
            )
        }
    }

    private func inferredCodexSessionID(from url: URL) -> String? {
        guard agent == .codex else { return nil }
        let candidate = String(url.deletingPathExtension().lastPathComponent.suffix(36))
        return UUID(uuidString: candidate) == nil ? nil : candidate.lowercased()
    }

    private func codexNavigationSessionID(from url: URL) -> String? {
        for line in ribbitHead(of: url).split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  object["type"] as? String == "session_meta",
                  let payload = object["payload"] as? [String: Any]
            else { continue }

            let isSubagent = payload["thread_source"] as? String == "subagent"
                || payload["forked_from_id"] != nil
            let candidate: String?
            if isSubagent {
                candidate = payload["parent_thread_id"] as? String
                    ?? payload["forked_from_id"] as? String
                    ?? payload["session_id"] as? String
            } else {
                candidate = payload["id"] as? String
                    ?? payload["session_id"] as? String
            }
            return candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func recentSessionFiles(now: Date) -> [URL] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let cutoff = now.addingTimeInterval(-86_400 * 3)
        var candidates: [(URL, Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "jsonl",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= cutoff else { continue }
            candidates.append((url, modifiedAt))
        }
        return candidates
            .sorted { $0.1 > $1.1 }
            .prefix(12)
            .map(\.0)
    }

    private func modificationDate(for url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
    }

    private func projectName(from url: URL) -> String {
        let components = url.pathComponents
        if let index = components.firstIndex(of: "projects"),
           components.indices.contains(index + 1) {
            return components[index + 1].replacingOccurrences(of: "-", with: " ")
        }
        return url.deletingLastPathComponent().lastPathComponent
    }
}

struct RibbitSessionEventSummary {
    let markers: [String]
    let project: String?
    let sessionID: String?

    static func parse(_ text: String) -> RibbitSessionEventSummary {
        let structured = structuredMarkers(in: text)
        let markers = structured.isEmpty
            ? captureAll(
                pattern: #"\"(?:type|role)\"\s*:\s*\"([^\"]+)\""#,
                in: text
            )
            : structured
        let workingDirectory = captureFirst(
            patterns: [
                #"\"cwd\"\s*:\s*\"([^\"]+)\""#,
                #"\"working_directory\"\s*:\s*\"([^\"]+)\""#
            ],
            in: text
        )
        let sessionID = captureFirst(
            patterns: [
                #"\"session_id\"\s*:\s*\"([^\"]+)\""#,
                #"\"conversation_id\"\s*:\s*\"([^\"]+)\""#
            ],
            in: text
        )
        return RibbitSessionEventSummary(
            markers: markers,
            project: workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent },
            sessionID: sessionID
        )
    }

    func state(modifiedAt: Date, now: Date) -> RibbitAgentState {
        let age = now.timeIntervalSince(modifiedAt)
        if attentionKind != nil { return .attention }
        if let marker = latestStateMarker {
            if Self.pausedMarkers.contains(marker) {
                return age < 7_200 ? .paused : .completed
            }
            if Self.runningMarkers.contains(marker) {
                return age < 900 ? .running : .idle
            }
        }
        if age < 18 { return .running }
        if age < 3_600 { return .idle }
        return .completed
    }

    var activity: String {
        switch latestStateMarker {
        case "permission_request", "approval_request": "permission requested"
        case "ask_user", "question": "waiting for an answer"
        case "plan_ready": "plan ready for review"
        case "awaiting_prompt", "turn_ended", "task_complete", "stop",
             "session_end", "sessionend": "ready for another prompt"
        case "compacted", "context_compacted": "context compacted"
        case "function_call", "custom_tool_call", "custom_tool_call_output": "using tools"
        case "reasoning", "agent_reasoning": "thinking"
        case "agent_message": "writing response"
        case "user", "user_message": "working from your prompt"
        case "task_started": "starting task"
        default: "session activity"
        }
    }

    var attentionKind: RibbitAttentionKind? {
        switch latestStateMarker {
        case "permission_request", "approval_request": .permission
        case "ask_user", "question": .question
        case "plan_ready": .plan
        default: nil
        }
    }

    var attentionDetail: String? {
        switch attentionKind {
        case .permission: "a tool action is waiting for approval."
        case .question: "the agent is waiting for your answer."
        case .plan: "review the plan before work continues."
        case .followUp: "the session is ready for another prompt."
        case nil: nil
        }
    }

    private var latestStateMarker: String? {
        markers.reversed().first { Self.stateMarkers.contains($0) }
    }

    private static let attentionMarkers: Set<String> = [
        "permission_request", "approval_request", "ask_user", "question", "plan_ready"
    ]
    private static let runningMarkers: Set<String> = [
        "user", "user_message", "task_started", "function_call", "custom_tool_call",
        "custom_tool_call_output", "reasoning", "agent_reasoning", "agent_message",
        "compacted", "context_compacted"
    ]
    private static let pausedMarkers: Set<String> = [
        "turn_ended", "task_complete", "stop", "session_end", "sessionend",
        "awaiting_prompt"
    ]
    private static let stateMarkers = attentionMarkers
        .union(runningMarkers)
        .union(pausedMarkers)

    private static func structuredMarkers(in text: String) -> [String] {
        var markers: [String] = []
        func appendMetadata(_ object: [String: Any]) {
            if let type = object["type"] as? String { markers.append(type) }
            if let role = object["role"] as? String { markers.append(role) }
        }
        for line in text.split(whereSeparator: \.isNewline) {
            guard let value = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                  let object = value as? [String: Any] else { continue }
            appendMetadata(object)
            for key in ["payload", "message", "item"] {
                if let nested = object[key] as? [String: Any] {
                    appendMetadata(nested)
                }
            }
        }
        return markers
    }

    private static func captureFirst(patterns: [String], in text: String) -> String? {
        for pattern in patterns {
            if let value = captureAll(pattern: pattern, in: text).last { return value }
        }
        return nil
    }

    private static func captureAll(pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}

private enum RibbitCursorWorkspaceIndex {
    private static let workspacesByEncodedPath: [String: URL] = {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Cursor/User/workspaceStorage",
                isDirectory: true
            )
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [:] }

        var result: [String: URL] = [:]
        for case let fileURL as URL in enumerator
        where fileURL.lastPathComponent == "workspace.json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let folder = object["folder"] as? String,
                  let workspaceURL = URL(string: folder),
                  workspaceURL.isFileURL else { continue }
            let decodedPath = workspaceURL.path.removingPercentEncoding ?? workspaceURL.path
            let encodedPath = decodedPath
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .replacingOccurrences(of: "/", with: "-")
            result[encodedPath] = URL(fileURLWithPath: decodedPath)
        }
        return result
    }()

    static func workspace(for transcriptURL: URL) -> URL? {
        let components = transcriptURL.pathComponents
        guard let index = components.firstIndex(of: "projects"),
              components.indices.contains(index + 1) else { return nil }
        return workspacesByEncodedPath[components[index + 1]]
    }
}

func ribbitHead(of url: URL, maxBytes: Int = 32_768) -> String {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
    defer { try? handle.close() }
    return (try? handle.read(upToCount: maxBytes))
        .flatMap { String(data: $0, encoding: .utf8) } ?? ""
}

func ribbitTail(of url: URL, maxBytes: UInt64 = 65_536) -> String {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
    defer { try? handle.close() }
    let size = (try? handle.seekToEnd()) ?? 0
    try? handle.seek(toOffset: size > maxBytes ? size - maxBytes : 0)
    return (try? handle.readToEnd())
        .flatMap { String(data: $0, encoding: .utf8) } ?? ""
}
