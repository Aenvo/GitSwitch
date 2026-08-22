import Foundation

struct GitConfigValue: Sendable {
    let exists: Bool
    let value: String
}

struct AccountSwitchingEngine: Sendable {
    let runner: any CommandRunning
    let accountsProvider: @Sendable () -> [GitHubAccount]

    init(
        runner: any CommandRunning = ProcessCommandRunner(),
        accountsProvider: @escaping @Sendable () -> [GitHubAccount] = { AccountStore.load() }
    ) {
        self.runner = runner
        self.accountsProvider = accountsProvider
    }

    func readStatus(state: SwitcherState = .ready, message: String? = nil) async -> SwitcherStatus {
        let loginResult = await runner.run(
            executable: Toolchain.ghPath,
            arguments: ["api", "--hostname", "github.com", "user", "--jq", ".login"]
        )
        let login = loginResult.succeeded ? account(fromLogin: loginResult.stdout) : nil
        let name = await readGitValue("user.name")
        let email = await readGitValue("user.email")
        let effectiveState: SwitcherState = login == nil && state == .ready ? .error : state
        let effectiveMessage = login == nil && message == nil ? "无法读取当前 GitHub 账号" : message

        return SwitcherStatus(
            state: effectiveState,
            activeAccount: login,
            gitName: name.exists ? name.value : nil,
            gitEmail: email.exists ? email.value : nil,
            message: effectiveMessage,
            updatedAt: Date()
        )
    }

    func switchAccount(to target: GitHubAccount) async -> SwitcherStatus {
        let original = await readStatus()
        guard let originalLogin = original.activeAccount else {
            return await readStatus(state: .error, message: "切换前无法读取 GitHub 账号")
        }
        let originalName = await readGitValue("user.name")
        let originalEmail = await readGitValue("user.email")
        var accountWasSwitched = false

        let switchResult = await runner.run(
            executable: Toolchain.ghPath,
            arguments: ["auth", "switch", "--hostname", "github.com", "--user", target.name]
        )
        guard switchResult.succeeded else {
            return await readStatus(state: .error, message: cleanError(switchResult, fallback: "目标账号尚未授权"))
        }
        accountWasSwitched = true

        let setupResult = await runner.run(
            executable: Toolchain.ghPath,
            arguments: ["auth", "setup-git", "--hostname", "github.com"]
        )
        let nameResult = setupResult.succeeded
            ? await runner.run(executable: Toolchain.gitPath, arguments: ["config", "--global", "user.name", target.gitName])
            : setupResult
        let emailResult = nameResult.succeeded
            ? await runner.run(executable: Toolchain.gitPath, arguments: ["config", "--global", "user.email", target.email])
            : nameResult

        if setupResult.succeeded && nameResult.succeeded && emailResult.succeeded {
            let verified = await readStatus()
            if verified.activeAccount?.name == target.name,
               verified.gitName == target.gitName,
               verified.gitEmail == target.email {
                return verified
            }
        }

        await restoreGitValue("user.name", original: originalName)
        await restoreGitValue("user.email", original: originalEmail)
        if accountWasSwitched && originalLogin.name != target.name {
            _ = await runner.run(
                executable: Toolchain.ghPath,
                arguments: ["auth", "switch", "--hostname", "github.com", "--user", originalLogin.name]
            )
        }
        return await readStatus(state: .error, message: "切换失败，已恢复原配置")
    }

    /// 注销一个 GitHub 账号的 gh 凭据。调用方负责先处理“删除的是当前账号”的场景。
    @discardableResult
    func logout(_ account: GitHubAccount) async -> CommandResult {
        await runner.run(
            executable: Toolchain.ghPath,
            arguments: ["auth", "logout", "--hostname", "github.com", "--user", account.name]
        )
    }

    func firstAlternate(to account: GitHubAccount?) -> GitHubAccount? {
        accountsProvider().first { $0 != account }
    }

    private func account(fromLogin output: String) -> GitHubAccount? {
        let login = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !login.isEmpty else { return nil }
        if let known = accountsProvider().first(where: { $0.name == login }) {
            return known
        }
        return GitHubAccount(name: login, email: "")
    }

    private func readGitValue(_ key: String) async -> GitConfigValue {
        let result = await runner.run(executable: Toolchain.gitPath, arguments: ["config", "--global", "--get", key])
        return GitConfigValue(
            exists: result.succeeded,
            value: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func restoreGitValue(_ key: String, original: GitConfigValue) async {
        if original.exists {
            _ = await runner.run(executable: Toolchain.gitPath, arguments: ["config", "--global", key, original.value])
        } else {
            _ = await runner.run(executable: Toolchain.gitPath, arguments: ["config", "--global", "--unset-all", key])
        }
    }

    private func cleanError(_ result: CommandResult, fallback: String) -> String {
        let text = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return fallback }
        return String(text.prefix(180))
    }
}
