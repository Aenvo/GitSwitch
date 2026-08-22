import Foundation

actor SwitchCoordinator {
    static let shared = SwitchCoordinator()

    private let engine: AccountSwitchingEngine
    private let defaults: UserDefaults
    private var status: SwitcherStatus = .offline
    private var isSwitching = false
    private var lastBackgroundValidation: Date?
    private var publishedSignature: String = ""

    init(engine: AccountSwitchingEngine = AccountSwitchingEngine(), defaults: UserDefaults = .standard) {
        self.engine = engine
        self.defaults = defaults
    }

    func currentStatus(refresh: Bool = false) async -> SwitcherStatus {
        if refresh || status.state == .offline {
            let (fresh, authUnavailable) = await engine.readStatusDetailed()
            if fresh.activeAccount == nil, fresh.state == .error, authUnavailable, status.activeAccount != nil {
                // 仅当 auth status 输出为空（半死网络超时）时保留缓存账号并标记离线缓存；
                // 输出非空但没有账号（全部注销）是真实状态，不遮蔽。
                status.state = .offlineCached
                status.message = fresh.message
                status.updatedAt = Date()
            } else {
                status = fresh
            }
            publishedSignature = Self.visibleSignature(of: status)
        }
        return status
    }

    var accounts: [GitHubAccount] {
        AccountStore.load(defaults: defaults)
    }

    /// 后台验证：账号来自本地读取，`gh api user` 仅用于探测 GitHub 可达性；
    /// 不可达时降级为 offlineCached（账号照常显示）。返回 true 表示可见状态发生变化、
    /// 需要刷新小组件时间线。至少间隔 30 秒，切换事务期间跳过。
    @discardableResult
    func refreshInBackground() async -> Bool {
        guard !isSwitching else { return false }
        if let last = lastBackgroundValidation, Date().timeIntervalSince(last) < 30 { return false }
        lastBackgroundValidation = Date()

        let remote = await engine.remoteLogin()
        guard !isSwitching else { return false }
        let (localRead, authUnavailable) = await engine.readStatusDetailed()
        var local = localRead
        if local.activeAccount == nil, remote == nil, authUnavailable, status.activeAccount != nil {
            // 本地读取与远端探测都失败（半死网络）：保留缓存账号，标记离线缓存
            local = status
            local.state = .offlineCached
            local.message = "GitHub 暂时不可达，显示本地状态"
            local.updatedAt = Date()
        } else if remote == nil, local.activeAccount != nil {
            local.state = .offlineCached
            local.message = "GitHub 暂时不可达，显示本地状态"
        }
        status = local

        let signature = Self.visibleSignature(of: local)
        guard signature != publishedSignature else { return false }
        publishedSignature = signature
        return true
    }

    /// 只比较用户可见字段（不含 updatedAt），用于判断是否需要刷新小组件时间线。
    private static func visibleSignature(of status: SwitcherStatus) -> String {
        [
            status.state.rawValue,
            status.activeAccount?.name ?? "-",
            status.gitName ?? "-",
            status.gitEmail ?? "-",
            status.message ?? "-"
        ].joined(separator: "|")
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
