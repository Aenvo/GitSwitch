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

    /// 读取当前状态：账号来自本地 `gh auth status` 解析（离线可用、不含 token），
    /// 不依赖 GitHub API 可达性；git 身份来自本地 git config。
    func readStatus(state: SwitcherState = .ready, message: String? = nil) async -> SwitcherStatus {
        await readStatusDetailed(state: state, message: message).status
    }

    /// 同 readStatus，额外返回 authStatusUnavailable：`gh auth status` 输出完全为空
    /// （超时或进程异常）。协调器据此决定是否用缓存兜底；输出非空但没有账号
    /// （例如用户注销了全部账号）是真实状态，不得被缓存遮蔽。
    func readStatusDetailed(state: SwitcherState = .ready, message: String? = nil) async -> (status: SwitcherStatus, authStatusUnavailable: Bool) {
        let authResult = await runner.run(
            executable: Toolchain.ghPath,
            arguments: ["auth", "status", "--hostname", "github.com"],
            timeout: 8,
            environment: Self.localOnlyProxyEnvironment
        )
        // gh auth status 在网络不可达时也可能以非零码退出，但文本仍会列出账号，因此只按文本解析。
        let authText = authResult.stdout + "\n" + authResult.stderr
        let login = Self.activeLogin(fromAuthStatusText: authText)
        let name = await readGitValue("user.name")
        let email = await readGitValue("user.email")
        let account: GitHubAccount?
        if let login {
            account = self.account(fromLogin: login)
        } else {
            account = nil
        }
        let effectiveState: SwitcherState = account == nil && state == .ready ? .error : state
        let effectiveMessage = account == nil && message == nil ? "无法读取当前 GitHub 账号" : message

        let status = SwitcherStatus(
            state: effectiveState,
            activeAccount: account,
            gitName: name.exists ? name.value : nil,
            gitEmail: email.exists ? email.value : nil,
            message: effectiveMessage,
            updatedAt: Date()
        )
        let unavailable = authText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (status, unavailable)
    }

    /// 探测 GitHub API 可达性并返回远端登录名；失败（含超时）返回 nil。仅用于后台验证与切换事务。
    func remoteLogin(timeout: TimeInterval = 20) async -> String? {
        let result = await runner.run(
            executable: Toolchain.ghPath,
            arguments: ["api", "--hostname", "github.com", "user", "--jq", ".login"],
            timeout: timeout
        )
        let login = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.succeeded && !login.isEmpty ? login : nil
    }

    /// 读取本地账号时用死代理故意让 gh 的联网校验瞬间失败：gh auth status 仍会列出
    /// 账号与激活标记（"Failed to log in …" 文案），但不再被网络状态拖住（实测秒回），
    /// 账号读取彻底与网络无关。可达性判断由 remoteLogin 单独负责。
    static let localOnlyProxyEnvironment = [
        "HTTPS_PROXY": "http://127.0.0.1:9",
        "HTTP_PROXY": "http://127.0.0.1:9"
    ]

    /// 从 `gh auth status` 输出解析当前激活账号。gh 把该输出写到 stderr，多账号时以
    /// “Active account: true” 标记激活项；断网时输出变为 “Failed to log in … account X”
    /// 但本地配置仍知道账号与激活态，同样解析。仅识别唯一无标记账号的旧格式。
    static func activeLogin(fromAuthStatusText text: String) -> String? {
        var candidates: [(name: String, active: Bool?)] = []
        for line in text.components(separatedBy: .newlines) {
            if let name = capturedGroup(#"(?:Failed to )?[Ll]og(?:ged)? in to \S+ account (\S+)"#, in: line) {
                candidates.append((name, nil))
            } else if let marker = capturedGroup(#"Active account: (true|false)"#, in: line), !candidates.isEmpty {
                candidates[candidates.count - 1].active = marker == "true"
            }
        }
        if let explicit = candidates.first(where: { $0.active == true }) {
            return explicit.name
        }
        let names = candidates.map(\.name)
        return names.count == 1 ? names[0] : nil
    }

    private static func capturedGroup(_ pattern: String, in line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range])
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
