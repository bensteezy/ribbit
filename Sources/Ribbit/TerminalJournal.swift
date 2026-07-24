import Foundation

enum TerminalSaveRequest {
    case save(name: String?)
}

final class TerminalJournal: @unchecked Sendable {
    static let defaultMaximumBytes = 50 * 1_024 * 1_024
    static let defaultSegmentBytes = 5 * 1_024 * 1_024

    let directoryURL: URL
    let requestURL: URL

    private let maximumBytes: Int
    private let segmentBytes: Int
    private let queue = DispatchQueue(label: "com.ribbit.terminal-journal", qos: .utility)
    private let fileManager: FileManager
    private var segmentIndex = 0
    private var currentSize = 0
    private var handle: FileHandle?

    init(
        directoryURL: URL,
        maximumBytes: Int = TerminalJournal.defaultMaximumBytes,
        segmentBytes: Int = TerminalJournal.defaultSegmentBytes,
        fileManager: FileManager = .default
    ) throws {
        self.directoryURL = directoryURL
        self.requestURL = directoryURL.appendingPathComponent("save.request")
        self.maximumBytes = max(1, maximumBytes)
        self.segmentBytes = max(1, min(segmentBytes, maximumBytes))
        self.fileManager = fileManager

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try prepareCurrentSegment()
    }

    deinit {
        queue.sync {
            try? handle?.synchronize()
            try? handle?.close()
            handle = nil
        }
    }

    func append(_ bytes: ArraySlice<UInt8>) {
        guard !bytes.isEmpty else { return }
        let data = Data(bytes)
        queue.async { [weak self] in
            self?.appendSynchronously(data)
        }
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        queue.async { [weak self] in
            self?.appendSynchronously(data)
        }
    }

    func transcript() -> String {
        queue.sync {
            try? handle?.synchronize()
            let data = segmentURLs().reduce(into: Data()) { result, url in
                if let segment = try? Data(contentsOf: url) {
                    result.append(segment)
                }
            }
            return TerminalTranscriptRenderer.render(data)
        }
    }

    func consumeSaveRequest() -> TerminalSaveRequest? {
        guard fileManager.fileExists(atPath: requestURL.path) else { return nil }
        defer { try? fileManager.removeItem(at: requestURL) }
        guard let data = try? Data(contentsOf: requestURL), data.count <= 4_096 else {
            return .save(name: nil)
        }
        let value = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .save(name: value.isEmpty ? nil : value)
    }

    private func appendSynchronously(_ data: Data) {
        var offset = 0
        while offset < data.count {
            if currentSize >= segmentBytes {
                rotateSegment()
            }
            let available = segmentBytes - currentSize
            let count = min(available, data.count - offset)
            let chunk = data.subdata(in: offset..<(offset + count))
            do {
                try handle?.write(contentsOf: chunk)
                currentSize += count
            } catch {
                return
            }
            offset += count
        }
        trimOldSegments()
    }

    private func prepareCurrentSegment() throws {
        let existing = segmentURLs()
        if let last = existing.last {
            segmentIndex = Self.segmentNumber(from: last) ?? existing.count - 1
            currentSize = (try? last.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            handle = try FileHandle(forWritingTo: last)
            try handle?.seekToEnd()
            if currentSize >= segmentBytes {
                rotateSegment()
            }
        } else {
            try openNewSegment(index: 0)
        }
    }

    private func rotateSegment() {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
        segmentIndex += 1
        try? openNewSegment(index: segmentIndex)
        trimOldSegments()
    }

    private func openNewSegment(index: Int) throws {
        let url = segmentURL(index: index)
        if !fileManager.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ), !fileManager.fileExists(atPath: url.path) {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
        try handle?.seekToEnd()
        currentSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private func trimOldSegments() {
        var segments = segmentURLs()
        var total = segments.reduce(0) { partial, url in
            partial + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        while segments.count > 1, total > maximumBytes {
            let oldest = segments.removeFirst()
            let size = (try? oldest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try? fileManager.removeItem(at: oldest)
            total -= size
        }
    }

    private func segmentURLs() -> [URL] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.lastPathComponent.hasPrefix("segment-") && $0.pathExtension == "raw" }
            .sorted { (Self.segmentNumber(from: $0) ?? 0) < (Self.segmentNumber(from: $1) ?? 0) }
    }

    private func segmentURL(index: Int) -> URL {
        directoryURL.appendingPathComponent(String(format: "segment-%06d.raw", index))
    }

    private static func segmentNumber(from url: URL) -> Int? {
        let value = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "segment-", with: "")
        return Int(value)
    }
}

enum TerminalTranscriptRenderer {
    private enum State {
        case normal
        case escape
        case controlSequence
        case operatingSystemCommand
        case operatingSystemCommandEscape
    }

    static func render(_ data: Data) -> String {
        var state = State.normal
        var lines: [String] = []
        var line: [UInt8] = []
        var cursor = 0

        func write(_ byte: UInt8) {
            if cursor < line.count {
                line[cursor] = byte
            } else {
                line.append(byte)
            }
            cursor += 1
        }

        func finishLine() {
            while line.last == 0x20 { line.removeLast() }
            lines.append(String(decoding: line, as: UTF8.self))
            line.removeAll(keepingCapacity: true)
            cursor = 0
        }

        for byte in data {
            switch state {
            case .normal:
                switch byte {
                case 0x1B:
                    state = .escape
                case 0x0A:
                    finishLine()
                case 0x0D:
                    cursor = 0
                case 0x08:
                    if cursor > 0 {
                        cursor -= 1
                        if cursor < line.count { line.remove(at: cursor) }
                    }
                case 0x09:
                    write(byte)
                case 0x20...0xFF:
                    write(byte)
                default:
                    break
                }
            case .escape:
                switch byte {
                case 0x5B:
                    state = .controlSequence
                case 0x5D:
                    state = .operatingSystemCommand
                default:
                    state = .normal
                }
            case .controlSequence:
                if (0x40...0x7E).contains(byte) {
                    state = .normal
                }
            case .operatingSystemCommand:
                if byte == 0x07 {
                    state = .normal
                } else if byte == 0x1B {
                    state = .operatingSystemCommandEscape
                }
            case .operatingSystemCommandEscape:
                state = byte == 0x5C ? .normal : .operatingSystemCommand
            }
        }

        if !line.isEmpty { finishLine() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }
}
