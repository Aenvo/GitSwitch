import Foundation

enum StatusRequestRoute: Equatable, Sendable {
    case status
    case notFound

    init(request: String) {
        let requestLine = request.components(separatedBy: "\r\n").first ?? ""
        self = requestLine == "GET /v1/status HTTP/1.1" ? .status : .notFound
    }
}
