import Foundation
import Network

final class RibbitAgentBridgeServer: @unchecked Sendable {
    static let port: UInt16 = 9848

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.ribbit.agent-bridge")
    private let receiveEvent: @Sendable (RibbitAgentBridgeEvent) -> Void

    init(receiveEvent: @escaping @Sendable (RibbitAgentBridgeEvent) -> Void) {
        self.receiveEvent = receiveEvent
    }

    func start() {
        guard listener == nil,
              let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        do {
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.receive(on: connection)
            }
            listener.stateUpdateHandler = { state in
                if case let .failed(error) = state {
                    NSLog("ribbit agent bridge failed: \(error.localizedDescription)")
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            NSLog("ribbit could not start its agent bridge: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receive(on connection: NWConnection) {
        connection.start(queue: queue)
        receiveMore(on: connection, buffer: Data())
    }

    private func receiveMore(on connection: NWConnection, buffer: Data) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 32_768
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var nextBuffer = buffer
            if let data { nextBuffer.append(data) }
            guard nextBuffer.count <= 131_072 else {
                respond(to: connection, status: "413 Content Too Large")
                return
            }
            if let request = completeRequest(in: nextBuffer) {
                handle(request, on: connection)
            } else if isComplete || error != nil {
                respond(to: connection, status: "400 Bad Request")
            } else {
                receiveMore(on: connection, buffer: nextBuffer)
            }
        }
    }

    private func completeRequest(in data: Data) -> Data? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator),
              let header = String(
                data: data[..<headerRange.lowerBound],
                encoding: .utf8
              ) else { return nil }
        let totalLength = headerRange.upperBound + Self.contentLength(in: header)
        return data.count >= totalLength ? Data(data.prefix(totalLength)) : nil
    }

    static func contentLength(in header: String) -> Int {
        header.components(separatedBy: "\r\n").first {
            $0.lowercased().hasPrefix("content-length:")
        }.flatMap {
            Int(
                $0.split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        } ?? 0
    }

    private func handle(_ data: Data, on connection: NWConnection) {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator),
              let header = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else {
            respond(to: connection, status: "400 Bad Request")
            return
        }
        let lines = header.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""
        let origin = lines.dropFirst().first { $0.lowercased().hasPrefix("origin:") }
        if origin != nil {
            respond(to: connection, status: "403 Forbidden")
            return
        }
        if requestLine.hasPrefix("GET /v1/health") {
            respond(to: connection, status: "200 OK")
            return
        }
        guard requestLine.hasPrefix("POST /v1/events") else {
            respond(to: connection, status: "404 Not Found")
            return
        }
        let body = Data(data[headerRange.upperBound...])
        guard let event = try? JSONDecoder().decode(
            RibbitAgentBridgeEvent.self,
            from: body
        ) else {
            respond(to: connection, status: "422 Unprocessable Content")
            return
        }
        receiveEvent(event)
        respond(to: connection, status: "202 Accepted")
    }

    private func respond(
        to connection: NWConnection,
        status: String
    ) {
        let body = Data("{\"ok\":true}".utf8)
        let header = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n\r\n"
        connection.send(
            content: Data(header.utf8) + body,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }
}
