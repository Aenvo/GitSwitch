import Foundation

enum AccountStore {
    static let storageKey = "GitSwitchAccounts"

    static func load(defaults: UserDefaults = .standard) -> [GitHubAccount] {
        if let data = defaults.data(forKey: storageKey),
           let accounts = try? JSONDecoder().decode([GitHubAccount].self, from: data) {
            return accounts
        }
        return []
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
