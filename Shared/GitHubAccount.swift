import Foundation

struct GitHubAccount: Codable, Hashable, Identifiable, Sendable {
    /// GitHub 登录名，同时也是 gh 账号标识（不可编辑）
    var name: String
    /// 当前使用的 Git 提交邮箱
    var email: String
    /// 自定义 Git 用户名；nil 表示使用登录名
    var gitName: String?
    /// 创建账号时的默认邮箱（“还原默认配置”使用）；nil 表示以当前 email 为默认。
    /// 旧版存储没有该字段，依靠 Codable 的 decodeIfPresent 兼容。
    var defaultEmail: String?

    var id: String { name }

    /// 切换或同步时写入全局 git config 的用户名
    var gitUserName: String { gitName ?? name }
    /// “还原默认配置”时恢复的邮箱
    var resetEmail: String { defaultEmail ?? email }
    var gitEmail: String { email }

    init(name: String, email: String, gitName: String? = nil, defaultEmail: String? = nil) {
        self.name = name
        self.email = email
        self.gitName = gitName
        self.defaultEmail = defaultEmail
    }

    static func noreplyEmail(userID: String, login: String) -> String {
        "\(userID)+\(login)@users.noreply.github.com"
    }
}
