import Foundation

actor SwitchCoordinator {
    static let shared = SwitchCoordinator()

    private let engine: AccountSwitchingEngine
    private let defaults: UserDefaults
    private var status: SwitcherStatus = .offline
    private var isSwitching = false

    init(engine: AccountSwitchingEngine = AccountSwitchingEngine(), defaults: UserDefaults = .standard) {
        self.engine = engine
        self.defaults = defaults
    }

    func currentStatus(refresh: Bool = false) async -> SwitcherStatus {
        if refresh || status.state == .offline {
            status = await engine.readStatus()
        }
        return status
    }

    var accounts: [GitHubAccount] {
        AccountStore.load(defaults: defaults)
    }

    func switchAccount(to target: GitHubAccount) async -> SwitcherStatus {
        guard !isSwitching else { return status }
        isSwitching = true
        defer { isSwitching = false }
        status.state = .switching
        status.message = nil
        status.updatedAt = Date()
        let finalStatus = await engine.switchAccount(to: target)
        status = finalStatus
        return finalStatus
    }

    /// 新账号完成 gh 授权后接入：gh 已将其设为当前账号，这里同步全局 Git 身份并写入账号列表。
    func adoptNewAccount(_ account: GitHubAccount) async -> SwitcherStatus {
        let result = await switchAccount(to: account)
        if result.state == .ready, result.activeAccount?.name == account.name {
            AccountStore.add(account, defaults: defaults)
        }
        return result
    }

    /// 删除账号：若删除的是当前账号，先切换到列表中的其他账号，再注销 gh 凭据并从列表移除。
    func removeAccount(_ target: GitHubAccount) async -> SwitcherStatus {
        guard !isSwitching else { return status }
        isSwitching = true
        defer { isSwitching = false }

        let current = await engine.readStatus()
        if current.activeAccount == target {
            if let alternate = engine.firstAlternate(to: target) {
                status.state = .switching
                status.updatedAt = Date()
                let switched = await engine.switchAccount(to: alternate)
                guard switched.activeAccount?.name == alternate.name else {
                    status = switched
                    return switched
                }
            }
        }

        let logoutResult = await engine.logout(target)
        AccountStore.remove(target, defaults: defaults)
        let refreshed = await engine.readStatus()
        status = logoutResult.succeeded
            ? refreshed
            : SwitcherStatus(
                state: .error,
                activeAccount: refreshed.activeAccount,
                gitName: refreshed.gitName,
                gitEmail: refreshed.gitEmail,
                message: "注销失败：\(String(logoutResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)))",
                updatedAt: Date()
            )
        return status
    }

    func toggleAccount() async -> SwitcherStatus {
        let current = await currentStatus(refresh: true)
        guard let activeAccount = current.activeAccount else {
            status = SwitcherStatus(
                state: .error,
                activeAccount: nil,
                gitName: current.gitName,
                gitEmail: current.gitEmail,
                message: "无法读取当前 GitHub 账号",
                updatedAt: Date()
            )
            return status
        }
        guard let alternate = engine.firstAlternate(to: activeAccount) else {
            return SwitcherStatus(
                state: .error,
                activeAccount: activeAccount,
                gitName: current.gitName,
                gitEmail: current.gitEmail,
                message: "没有其他可切换的账号",
                updatedAt: Date()
            )
        }
        return await switchAccount(to: alternate)
    }
}
