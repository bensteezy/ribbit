import Foundation

enum RibbitAgentHookState: Equatable {
    case checking
    case ready
    case needsSetup
    case unavailable(String)
}

private struct RibbitHookCommandResult: Sendable {
    let exitCode: Int32
    let output: String
}

@MainActor
final class RibbitAgentHookStatusModel: ObservableObject {
    @Published private(set) var states: [RibbitAgentKind: RibbitAgentHookState] =
        Dictionary(uniqueKeysWithValues: RibbitAgentKind.allCases.map { ($0, .checking) })
    @Published private(set) var isWorking = false
    @Published private(set) var message: String?

    init() {
        refresh()
    }

    func refresh() {
        run(mode: "--dry-run")
    }

    func installOrRepair() {
        run(mode: "--install")
    }

    private func run(mode: String) {
        guard !isWorking else { return }
        guard let scriptURL = Self.installerURL else {
            states = Dictionary(uniqueKeysWithValues: RibbitAgentKind.allCases.map {
                ($0, .unavailable("installer missing"))
            })
            return
        }
        isWorking = true
        message = nil
        states = Dictionary(uniqueKeysWithValues: RibbitAgentKind.allCases.map {
            ($0, .checking)
        })

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = [scriptURL.path, mode]
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    return RibbitHookCommandResult(
                        exitCode: process.terminationStatus,
                        output: String(
                            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
                            as: UTF8.self
                        )
                    )
                } catch {
                    return RibbitHookCommandResult(
                        exitCode: 1,
                        output: error.localizedDescription
                    )
                }
            }.value
            apply(result, installed: mode == "--install")
        }
    }

    private func apply(_ result: RibbitHookCommandResult, installed: Bool) {
        isWorking = false
        guard result.exitCode == 0 else {
            states = Dictionary(uniqueKeysWithValues: RibbitAgentKind.allCases.map {
                ($0, .unavailable("check failed"))
            })
            message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        let lines = result.output.split(separator: "\n").map(String.init)
        states = Dictionary(uniqueKeysWithValues: RibbitAgentKind.allCases.map { agent in
            let line = lines.first {
                $0.lowercased().hasPrefix("\(agent.rawValue):")
            } ?? ""
            return (
                agent,
                installed || line.hasSuffix(": ready") ? .ready : .needsSetup
            )
        })
        message = installed
            ? "observer hooks installed. restart active agent sessions once."
            : nil
    }

    static var installerURL: URL? {
        let bundled = Bundle.main.resourceURL?
            .appendingPathComponent(
                "RibbitIntegration/install-ribbit-hooks.sh",
                isDirectory: false
            )
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let development = root.appendingPathComponent(
            "scripts/install-ribbit-hooks.sh",
            isDirectory: false
        )
        return FileManager.default.fileExists(atPath: development.path)
            ? development
            : nil
    }
}
