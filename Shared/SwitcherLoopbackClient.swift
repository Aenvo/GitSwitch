import Foundation

struct SwitcherLoopbackClient {
    private let baseURL = "http://127.0.0.1:47831"

    func fetchStatus() async -> SwitcherStatus {
        guard let url = URL(string: "\(baseURL)/v1/status") else { return .offline }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        return await perform(request)
    }

    func toggleAccount() async -> SwitcherStatus {
        guard let url = URL(string: "\(baseURL)/v1/toggle") else { return .offline }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("widget-v1", forHTTPHeaderField: "X-GitSwitch-Client")
        return await perform(request)
    }

    private func perform(_ request: URLRequest) async -> SwitcherStatus {
        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession(configuration: configuration).data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return .offline }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SwitcherStatus.self, from: data)
        } catch {
            return .offline
        }
    }
}
