import Foundation

enum AccountStore {
    static let storageKey = "GitSwitchAccounts"

    static let seeds: [GitHubAccount] = [
        GitHubAccount(name: "Aenvo", email: "octocat@users.noreply.github.com"),
        GitHubAccount(name: "hubot", email: "hubot@users.noreply.github.com")
    ]

    static func load(defaults: UserDefaults = .standard) -> [GitHubAccount] {
        if let data = defaults.data(forKey: storageKey),
           let accounts = try? JSONDecoder().decode([GitHubAccount].self, from: data) {
            return accounts
        }
        return seeds
    }

    static func save(_ accounts: [GitHubAccount], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: storageKey)
        }
    }

    static func add(_ account: GitHubAccount, defaults: UserDefaults = .standard) {
        var accounts = load(defaults: defaults).filter { $0.name != account.name }
        accounts.append(account)
        save(accounts, defaults: defaults)
    }

    /// 按登录名替换账号配置；不存在时等同 add。
    static func update(_ account: GitHubAccount, defaults: UserDefaults = .standard) {
        var accounts = load(defaults: defaults)
        if let index = accounts.firstIndex(where: { $0.name == account.name }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        save(accounts, defaults: defaults)
    }

    static func remove(_ account: GitHubAccount, defaults: UserDefaults = .standard) {
        save(load(defaults: defaults).filter { $0.name != account.name }, defaults: defaults)
    }

    static func email(for name: String, defaults: UserDefaults = .standard) -> String? {
        load(defaults: defaults).first { $0.name == name }?.email
    }
}

/// 首次启动对账：若账号列表仍是默认播种（新用户机器上没有任何一个播种账号在 gh 中授权），
/// 返回空列表以清空示例账号，引导用户添加自己的账号；其余情况返回 nil 表示无需调整。
enum SeededAccountReconciler {
    static func reconciledList(stored: [GitHubAccount], ghAuthStatusText: String) -> [GitHubAccount]? {
        guard stored == AccountStore.seeds else { return nil }
        let anyAuthorized = stored.contains { ghAuthStatusText.contains("account \($0.name)") }
        return anyAuthorized ? nil : []
    }
}
