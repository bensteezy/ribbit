import Foundation

struct RibbitProject: Identifiable, Codable, Hashable {
    let id: UUID
    var rootPath: String
    var lastOpenedAt: Date

    init(id: UUID = UUID(), rootURL: URL, lastOpenedAt: Date = .now) {
        self.id = id
        self.rootPath = rootURL.standardizedFileURL.path
        self.lastOpenedAt = lastOpenedAt
    }

    var rootURL: URL { URL(fileURLWithPath: rootPath, isDirectory: true) }
    var notesURL: URL { rootURL.appendingPathComponent("ribbit-notes", isDirectory: true) }
    var name: String { rootURL.lastPathComponent.isEmpty ? rootPath : rootURL.lastPathComponent }
}

struct ProjectRegistry: Codable {
    var projects: [RibbitProject]
    var selectedProjectID: UUID?
}

enum TabKind: String, Codable {
    case terminal
    case note

    var systemImage: String {
        switch self {
        case .terminal: "terminal"
        case .note: "doc.plaintext"
        }
    }
}

enum TerminalTint: String, CaseIterable, Codable, Identifiable {
    case green
    case blue
    case purple
    case orange
    case red
    case pink

    var id: String { rawValue }
}

enum WorkspaceMode: String, CaseIterable, Identifiable, Codable {
    case tabs
    case canvas

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .tabs: "rectangle.on.rectangle"
        case .canvas: "square.grid.2x2"
        }
    }
}

struct CanvasNodeFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static func initial(kind: TabKind, index: Int) -> CanvasNodeFrame {
        let column = index % 2
        let row = index / 2
        return CanvasNodeFrame(
            x: 32 + Double(column * 660),
            y: 32 + Double(row * 430),
            width: kind == .terminal ? 620 : 440,
            height: kind == .terminal ? 390 : 320
        )
    }

    static func initialExternalAgent(index: Int) -> CanvasNodeFrame {
        let column = index % 2
        let row = index / 2
        return CanvasNodeFrame(
            x: 32 + Double(column * 380),
            y: 32 + Double(row * 210),
            width: 350,
            height: 170
        )
    }

    func movedBy(width deltaX: Double, height deltaY: Double) -> CanvasNodeFrame {
        var copy = self
        copy.x += deltaX
        copy.y += deltaY
        return copy
    }

    func resizedBy(width deltaWidth: Double, height deltaHeight: Double) -> CanvasNodeFrame {
        var copy = self
        copy.width = max(300, width + deltaWidth)
        copy.height = max(220, height + deltaHeight)
        return copy
    }
}

struct CanvasCamera: Codable, Equatable {
    var x: Double
    var y: Double
    var zoom: Double

    static let initial = CanvasCamera(x: 0, y: 0, zoom: 1)
}

struct WorkspaceDocument: Codable, Equatable {
    static let currentVersion = 6

    var version: Int = currentVersion
    var selectedTabID: UUID?
    var mode: WorkspaceMode
    var camera: CanvasCamera
    var tabs: [WorkspaceTabRecord]
    var contextEdges: [ContextEdge]
    var externalAgentPins: [ExternalAgentPin]

    init(
        version: Int = currentVersion,
        selectedTabID: UUID?,
        mode: WorkspaceMode,
        camera: CanvasCamera,
        tabs: [WorkspaceTabRecord],
        contextEdges: [ContextEdge] = [],
        externalAgentPins: [ExternalAgentPin] = []
    ) {
        self.version = version
        self.selectedTabID = selectedTabID
        self.mode = mode
        self.camera = camera
        self.tabs = tabs
        self.contextEdges = contextEdges
        self.externalAgentPins = externalAgentPins
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case selectedTabID
        case mode
        case camera
        case tabs
        case contextEdges
        case externalAgentPins
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        selectedTabID = try container.decodeIfPresent(UUID.self, forKey: .selectedTabID)
        mode = try container.decode(WorkspaceMode.self, forKey: .mode)
        camera = try container.decode(CanvasCamera.self, forKey: .camera)
        tabs = try container.decode([WorkspaceTabRecord].self, forKey: .tabs)
        contextEdges = try container.decodeIfPresent(
            [ContextEdge].self,
            forKey: .contextEdges
        ) ?? []
        externalAgentPins = try container.decodeIfPresent(
            [ExternalAgentPin].self,
            forKey: .externalAgentPins
        ) ?? []
    }
}

struct ExternalAgentPin: Codable, Equatable, Identifiable {
    let id: UUID
    var session: RibbitAgentSession
    var canvasFrame: CanvasNodeFrame

    init(
        id: UUID = UUID(),
        session: RibbitAgentSession,
        canvasFrame: CanvasNodeFrame
    ) {
        self.id = id
        self.session = session
        self.canvasFrame = canvasFrame
    }
}

struct ContextEdge: Codable, Equatable, Identifiable {
    let id: UUID
    let sourceTabID: UUID
    let targetTabID: UUID
    let createdAt: Date

    init(
        id: UUID = UUID(),
        sourceTabID: UUID,
        targetTabID: UUID,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sourceTabID = sourceTabID
        self.targetTabID = targetTabID
        self.createdAt = createdAt
    }
}

struct WorkspaceTabRecord: Codable, Equatable {
    var id: UUID
    var kind: TabKind
    var title: String
    var text: String
    var isDirty: Bool
    var terminalTint: TerminalTint
    var canvasFrame: CanvasNodeFrame?
    var filePath: String?
    var terminalDirectoryPath: String?
    var lastKnownAgent: RibbitAgentKind?
    var providerSessionID: String?
}

@MainActor
final class RibbitTab: ObservableObject, Identifiable {
    let id: UUID
    let kind: TabKind
    let projectID: UUID?
    @Published var title: String
    @Published var text: String
    @Published var isDirty = false
    @Published var terminalTint: TerminalTint
    @Published var canvasFrame: CanvasNodeFrame?
    @Published var agentSession: RibbitAgentSession?
    var lastKnownAgent: RibbitAgentKind?
    var providerSessionID: String?
    var fileURL: URL?
    var terminalSession: TerminalSession?

    init(
        id: UUID = UUID(),
        kind: TabKind,
        projectID: UUID? = nil,
        title: String,
        text: String = "",
        terminalTint: TerminalTint = .green,
        canvasFrame: CanvasNodeFrame? = nil,
        fileURL: URL? = nil,
        terminalSession: TerminalSession? = nil,
        lastKnownAgent: RibbitAgentKind? = nil,
        providerSessionID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.projectID = projectID
        self.title = title
        self.text = text
        self.terminalTint = terminalTint
        self.canvasFrame = canvasFrame
        self.agentSession = nil
        self.lastKnownAgent = lastKnownAgent
        self.providerSessionID = providerSessionID
        self.fileURL = fileURL
        self.terminalSession = terminalSession
    }
}

struct FileNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var id: URL { url }

    var displayName: String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }
}
