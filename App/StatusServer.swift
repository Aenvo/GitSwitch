import Foundation
import Network
import WidgetKit

final class StatusServer: @unchecked Sendable {
    static let port: NWEndpoint.Port = 47831
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.aenvo.GitSwitch.status")

    func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: Self.port)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { state in
                if case let .failed(error) = state {
                    fputs("Status server failed: \(error.localizedDescription)\n", stderr)
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            fputs("Unable to start local status server.\n", stderr)
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection, buffer: Data())
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
            var requestData = buffer
            if let data {
                requestData.append(data)
            }

            guard requestData.count <= 8192 else {
                self.send(connection, statusCode: 400, body: Data("{}".utf8))
                return
            }

            let headersComplete = requestData.range(of: Data("\r\n\r\n".utf8)) != nil
            if !headersComplete && !isComplete && error == nil {
                self.receiveRequest(connection, buffer: requestData)
                return
            }

            guard headersComplete,
                  let request = String(data: requestData, encoding: .utf8) else {
                self.send(connection, statusCode: 400, body: Data("{}".utf8))
                return
            }
            self.processRequest(request, connection: connection)
        }
    }

    private func processRequest(_ request: String, connection: NWConnection) {
        if request.hasPrefix("GET /v1/status ") {
            Task {
                let status = await SwitchCoordinator.shared.currentStatus(refresh: true)
                self.sendStatus(connection, status: status)
            }
            return
        }

        let headerLines = request.components(separatedBy: "\r\n")
        let authorizedClient = headerLines.dropFirst().contains { line in
            line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == "x-gitswitch-client: widget-v1"
        }
        let requestLine = headerLines.first ?? ""
        guard authorizedClient,
              requestLine == "POST /v1/toggle HTTP/1.1" else {
            send(connection, statusCode: 404, body: Data("{}".utf8))
            return
        }

        Task {
            let status = await SwitchCoordinator.shared.toggleAccount()
            WidgetCenter.shared.reloadAllTimelines()
            self.sendStatus(connection, status: status)
        }
    }

    private func sendStatus(_ connection: NWConnection, status: SwitcherStatus) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = (try? encoder.encode(status)) ?? Data("{}".utf8)
        send(connection, statusCode: 200, body: body)
    }

    private func send(_ connection: NWConnection, statusCode: Int, body: Data) {
        let reason = statusCode == 200 ? "OK" : (statusCode == 404 ? "Not Found" : "Bad Request")
        let header = "HTTP/1.1 \(statusCode) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
