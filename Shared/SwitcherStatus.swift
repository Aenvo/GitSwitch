import Foundation

enum SwitcherState: String, Codable, Sendable {
    case ready
    case switching
    case error
    case offline
    /// 本地账号信息可用，但 GitHub 暂时不可达（显示离线缓存，不整卡不可用）
    case offlineCached
}

struct SwitcherStatus: Codable, Equatable, Sendable {
    var state: SwitcherState
    var activeAccount: GitHubAccount?
    var gitName: String?
    var gitEmail: String?
    var message: String?
    var updatedAt: Date

    static var offline: SwitcherStatus {
        SwitcherStatus(
            state: .offline,
            activeAccount: nil,
            gitName: nil,
            gitEmail: nil,
            message: "助手暂时不可用",
            updatedAt: Date()
        )
    }
}
