import XCTest

private enum TestFixtures {
    static let primary = GitHubAccount(name: "octocat", email: "583231+octocat@users.noreply.github.com")
    static let secondary = GitHubAccount(name: "hubot", email: "123456+hubot@users.noreply.github.com")
}

final class AccountSwitchingEngineTests: XCTestCase {
    private var primaryAccount: GitHubAccount { TestFixtures.primary }
    private var secondaryAccount: GitHubAccount { TestFixtures.secondary }

    private func makeDefaults() -> UserDefaults {
        let name = "GitSwitchTests-\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name)!
    }

    private func makeConfiguredDefaults() -> UserDefaults {
        let defaults = makeDefaults()
        AccountStore.save([primaryAccount, secondaryAccount], defaults: defaults)
        return defaults
    }

    /// 引擎与协调器共享同一个 defaults，模拟真实运行时账号列表与状态映射的一致性。
    private func makeEngine(_ mock: MockCommandRunner, defaults: UserDefaults) -> AccountSwitchingEngine {
        AccountSwitchingEngine(runner: mock, accountsProvider: { AccountStore.load(defaults: defaults) })
    }

    func testAccountProfiles() {
        XCTAssertEqual(primaryAccount.gitUserName, "octocat")
        XCTAssertEqual(primaryAccount.gitEmail, "583231+octocat@users.noreply.github.com")
        XCTAssertEqual(secondaryAccount.gitEmail, "123456+hubot@users.noreply.github.com")
        XCTAssertEqual(GitHubAccount.noreplyEmail(userID: "42", login: "octocat"), "42+octocat@users.noreply.github.com")

        let customized = GitHubAccount(
            name: "octocat",
            email: "custom@example.com",
            gitName: "Display Name",
            defaultEmail: primaryAccount.email
        )
        XCTAssertEqual(customized.gitUserName, "Display Name")
        XCTAssertEqual(customized.resetEmail, primaryAccount.email)
    }

    func testAccountDecodesLegacyStoredJSON() throws {
        // 旧版存储没有 gitName/defaultEmail 字段，解码后应回落到默认语义
        let legacy = #" [{"name":"octocat","email":"583231+octocat@users.noreply.github.com"}] "#
        let accounts = try JSONDecoder().decode([GitHubAccount].self, from: Data(legacy.utf8))
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].gitUserName, "octocat")
        XCTAssertEqual(accounts[0].resetEmail, "583231+octocat@users.noreply.github.com")
    }

    func testAccountStoreUpdatesByIdentity() {
        let defaults = makeDefaults()
        let customized = GitHubAccount(name: "octocat", email: "new@example.com", gitName: "Octocat Dev")
        AccountStore.update(customized, defaults: defaults)

        let stored = AccountStore.load(defaults: defaults)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first { $0.name == "octocat" }, customized)
    }

    func testAccountStoreStartsEmptyPersistsAndRemoves() {
        let defaults = makeDefaults()
        XCTAssertTrue(AccountStore.load(defaults: defaults).isEmpty)

        AccountStore.add(primaryAccount, defaults: defaults)
        AccountStore.add(secondaryAccount, defaults: defaults)
        XCTAssertEqual(AccountStore.load(defaults: defaults).count, 2)
        XCTAssertTrue(AccountStore.load(defaults: defaults).contains(primaryAccount))

        AccountStore.remove(secondaryAccount, defaults: defaults)
        XCTAssertEqual(AccountStore.load(defaults: defaults), [primaryAccount])

        AccountStore.remove(primaryAccount, defaults: defaults)
        XCTAssertTrue(AccountStore.load(defaults: defaults).isEmpty)
    }

    func testToolchainResolvesPaths() {
        XCTAssertFalse(Toolchain.ghPath.isEmpty)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: Toolchain.gitPath))
    }

    func testActiveLoginParsesAuthStatusText() {
        let multiAccount = """
        github.com
          ✓ Logged in to github.com account octocat (keyring)
          - Active account: true
          ✓ Logged in to github.com account hubot (keyring)
          - Active account: false
        """
        XCTAssertEqual(AccountSwitchingEngine.activeLogin(fromAuthStatusText: multiAccount), "octocat")

        let singleLegacy = "✓ Logged in to github.com account monalisa (keyring)"
        XCTAssertEqual(AccountSwitchingEngine.activeLogin(fromAuthStatusText: singleLegacy), "monalisa")

        XCTAssertNil(AccountSwitchingEngine.activeLogin(fromAuthStatusText: "Not logged in to any GitHub account."))
    }

    func testReadStatusUsesLocalAuthStatusWithoutNetwork() async {
        let runner = MockCommandRunner(active: primaryAccount)
        runner.failApiUser = true
        let engine = makeEngine(runner, defaults: makeConfiguredDefaults())

        let status = await engine.readStatus()

        XCTAssertEqual(status.state, .ready)
        XCTAssertEqual(status.activeAccount?.name, "octocat")
        XCTAssertEqual(status.gitName, "octocat")
        // 账号读取必须走死代理环境，确保不被网络校验拖住
        XCTAssertEqual(runner.lastAuthStatusEnvironment?["HTTPS_PROXY"], AccountSwitchingEngine.localOnlyProxyEnvironment["HTTPS_PROXY"])
    }

    func testRefreshInBackgroundMarksOfflineCachedWhenGitHubUnreachable() async {
        let runner = MockCommandRunner(active: primaryAccount)
        let defaults = makeConfiguredDefaults()
        let coordinator = SwitchCoordinator(engine: makeEngine(runner, defaults: defaults), defaults: defaults)
        _ = await coordinator.currentStatus(refresh: true)
        runner.failApiUser = true

        let changed = await coordinator.refreshInBackground()
        let status = await coordinator.currentStatus()

        XCTAssertTrue(changed)
        XCTAssertEqual(status.state, .offlineCached)
        XCTAssertEqual(status.activeAccount?.name, "octocat")
        XCTAssertEqual(status.message, "GitHub 暂时不可达，显示本地状态")
    }

    func testRefreshInBackgroundKeepsReadyWhenReachableAndThrottles() async {
        let runner = MockCommandRunner(active: primaryAccount)
        let defaults = makeConfiguredDefaults()
        let coordinator = SwitchCoordinator(engine: makeEngine(runner, defaults: defaults), defaults: defaults)
        _ = await coordinator.currentStatus(refresh: true)

        // 可达：保持 ready，签名未变化无需刷新时间线
        var changed = await coordinator.refreshInBackground()
        var status = await coordinator.currentStatus()
        XCTAssertFalse(changed)
        XCTAssertEqual(status.state, .ready)

        // 30 秒节流：紧随其后的第二次验证被跳过
        runner.failApiUser = true
        changed = await coordinator.refreshInBackground()
        status = await coordinator.currentStatus()
        XCTAssertFalse(changed)
        XCTAssertEqual(status.state, .ready)
    }

    func testActiveLoginParsesOfflineFailureText() {
        // 断网时 gh auth status 秒回，文案为 "Failed to log in"，本地仍标记激活账号
        let offlineText = """
        github.com
          X Failed to log in to github.com account octocat (keyring)
          - Active account: true
          - The token in keyring is invalid.
        """
        XCTAssertEqual(AccountSwitchingEngine.activeLogin(fromAuthStatusText: offlineText), "octocat")
    }

    func testCurrentStatusKeepsCacheWhenAuthStatusTimesOut() async {
        let runner = MockCommandRunner(active: primaryAccount)
        let defaults = makeConfiguredDefaults()
        let coordinator = SwitchCoordinator(engine: makeEngine(runner, defaults: defaults), defaults: defaults)
        _ = await coordinator.currentStatus(refresh: true)
        runner.failAuthStatus = true

        let status = await coordinator.currentStatus(refresh: true)

        XCTAssertEqual(status.state, .offlineCached)
        XCTAssertEqual(status.activeAccount?.name, "octocat")
    }

    func testCurrentStatusDoesNotMaskGenuinelyNoAccounts() async {
        let runner = MockCommandRunner(active: primaryAccount, authorized: [])
        let defaults = makeConfiguredDefaults()
        let coordinator = SwitchCoordinator(engine: makeEngine(runner, defaults: defaults), defaults: defaults)
        _ = await coordinator.currentStatus(refresh: true)

        let status = await coordinator.currentStatus(refresh: true)

        XCTAssertEqual(status.state, .error)
        XCTAssertNil(status.activeAccount)
    }

    func testSuccessfulSwitchVerifiesAccountAndIdentity() async {
        let runner = MockCommandRunner(active: primaryAccount)
        let engine = makeEngine(runner, defaults: makeConfiguredDefaults())

        let status = await engine.switchAccount(to: secondaryAccount)

        XCTAssertEqual(status.state, .ready)
        XCTAssertEqual(status.activeAccount?.name, "hubot")
        XCTAssertEqual(status.gitName, "hubot")
        XCTAssertEqual(status.gitEmail, secondaryAccount.gitEmail)
    }

    func testFailureRollsBackAccountAndIdentity() async {
        let runner = MockCommandRunner(active: primaryAccount)
        runner.failEmailWrite = true
        let engine = makeEngine(runner, defaults: makeConfiguredDefaults())

        let status = await engine.switchAccount(to: secondaryAccount)

        XCTAssertEqual(status.state, .error)
        XCTAssertEqual(status.activeAccount?.name, "octocat")
        XCTAssertEqual(status.gitName, "octocat")
        XCTAssertEqual(status.gitEmail, primaryAccount.gitEmail)
    }

    func testConcurrentSwitchIsCoalesced() async {
        let runner = MockCommandRunner(active: primaryAccount)
        runner.commandDelayNanoseconds = 20_000_000
        let defaults = makeConfiguredDefaults()
        let coordinator = SwitchCoordinator(engine: makeEngine(runner, defaults: defaults), defaults: defaults)

        async let first = coordinator.switchAccount(to: secondaryAccount)
        async let second = coordinator.switchAccount(to: secondaryAccount)
        _ = await (first, second)

        XCTAssertEqual(runner.switchCommandCount, 1)
    }

    func testStatusRequestRouteAllowsOnlyReadOnlyStatusEndpoint() {
        XCTAssertEqual(
            StatusRequestRoute(request: "GET /v1/status HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"),
            .status
        )
        XCTAssertEqual(
            StatusRequestRoute(
                request: "POST /v1/toggle HTTP/1.1\r\nX-GitSwitch-Client: widget-v1\r\n\r\n"
            ),
            .notFound
        )
        XCTAssertEqual(
            StatusRequestRoute(request: "GET /v1/status?refresh=1 HTTP/1.1\r\n\r\n"),
            .notFound
        )
    }

    func testLogoutRunsGhAuthLogoutWithUserFlag() async {
        let runner = MockCommandRunner(active: primaryAccount)
        let engine = makeEngine(runner, defaults: makeConfiguredDefaults())

        let result = await engine.logout(secondaryAccount)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(runner.logoutCommandCount, 1)
        XCTAssertEqual(runner.lastLogoutUser, "hubot")
    }

    func testRemoveNonActiveAccountSkipsSwitch() async {
        let runner = MockCommandRunner(active: primaryAccount)
        let defaults = makeConfiguredDefaults()
        let coordinator = SwitchCoordinator(engine: makeEngine(runner, defaults: defaults), defaults: defaults)

        let status = await coordinator.removeAccount(secondaryAccount)
        let accounts = await coordinator.accounts

        XCTAssertEqual(runner.switchCommandCount, 0)
        XCTAssertEqual(runner.logoutCommandCount, 1)
        XCTAssertEqual(status.activeAccount?.name, "octocat")
        XCTAssertFalse(accounts.contains { $0.name == secondaryAccount.name })
    }

    func testRemoveActiveAccountSwitchesFirstThenLogsOut() async {
        let runner = MockCommandRunner(active: primaryAccount)
        let defaults = makeConfiguredDefaults()
        let coordinator = SwitchCoordinator(engine: makeEngine(runner, defaults: defaults), defaults: defaults)

        let status = await coordinator.removeAccount(primaryAccount)
        let accounts = await coordinator.accounts

        XCTAssertEqual(runner.switchCommandCount, 1)
        XCTAssertEqual(runner.switchTargets, ["hubot"])
        XCTAssertEqual(runner.logoutCommandCount, 1)
        XCTAssertEqual(runner.lastLogoutUser, "octocat")
        XCTAssertEqual(status.activeAccount?.name, "hubot")
        XCTAssertFalse(accounts.contains { $0.name == primaryAccount.name })
    }

    func testAdoptNewAccountSwitchesIdentityAndStores() async {
        let monalisa = GitHubAccount(name: "monalisa", email: "654321+monalisa@users.noreply.github.com")
        let runner = MockCommandRunner(active: primaryAccount)
        runner.authorized.append(monalisa)
        let defaults = makeConfiguredDefaults()
        let coordinator = SwitchCoordinator(engine: makeEngine(runner, defaults: defaults), defaults: defaults)

        let status = await coordinator.adoptNewAccount(monalisa)
        let accounts = await coordinator.accounts

        XCTAssertEqual(status.state, .ready)
        XCTAssertEqual(status.activeAccount?.name, "monalisa")
        XCTAssertEqual(status.gitEmail, monalisa.email)
        XCTAssertTrue(accounts.contains { $0.name == "monalisa" })
    }

    func testUpdateActiveAccountAppliesGitIdentityImmediately() async {
        let runner = MockCommandRunner(active: primaryAccount)
        let defaults = makeConfiguredDefaults()
        let coordinator = SwitchCoordinator(engine: makeEngine(runner, defaults: defaults), defaults: defaults)
        let customized = GitHubAccount(name: "octocat", email: "dev@example.com", gitName: "Octocat Dev", defaultEmail: primaryAccount.email)

        let status = await coordinator.updateAccount(customized)
        let accounts = await coordinator.accounts

        XCTAssertEqual(status.state, .ready)
        XCTAssertEqual(status.gitName, "Octocat Dev")
        XCTAssertEqual(status.gitEmail, "dev@example.com")
        XCTAssertEqual(accounts.first { $0.name == "octocat" }, customized)
    }

    func testUpdateInactiveAccountOnlyStores() async {
        let runner = MockCommandRunner(active: primaryAccount)
        let defaults = makeConfiguredDefaults()
        let coordinator = SwitchCoordinator(engine: makeEngine(runner, defaults: defaults), defaults: defaults)
        let customized = GitHubAccount(name: "hubot", email: "hubot@example.com", gitName: "Hubot")

        let status = await coordinator.updateAccount(customized)
        let accounts = await coordinator.accounts

        // 非当前账号：仅更新列表，不改动全局 git 配置
        XCTAssertEqual(status.gitName, "octocat")
        XCTAssertEqual(status.gitEmail, primaryAccount.gitEmail)
        XCTAssertEqual(accounts.first { $0.name == "hubot" }, customized)
    }

    func testLiveBidirectionalSwitchAndRestore() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_SWITCH_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_LIVE_SWITCH_TESTS=1 to exercise the real gh and git configuration.")
        }
        let environment = ProcessInfo.processInfo.environment
        let account1Login = try XCTUnwrap(environment["GITSWITCH_LIVE_ACCOUNT_1_LOGIN"])
        let account1Email = try XCTUnwrap(environment["GITSWITCH_LIVE_ACCOUNT_1_EMAIL"])
        let account2Login = try XCTUnwrap(environment["GITSWITCH_LIVE_ACCOUNT_2_LOGIN"])
        let account2Email = try XCTUnwrap(environment["GITSWITCH_LIVE_ACCOUNT_2_EMAIL"])
        let accounts = [
            GitHubAccount(name: account1Login, email: account1Email),
            GitHubAccount(name: account2Login, email: account2Email)
        ]
        let engine = AccountSwitchingEngine(accountsProvider: { accounts })
        let original = await engine.readStatus()
        let originalAccount = try XCTUnwrap(accounts.first { $0.name == original.activeAccount?.name })
        let alternate = try XCTUnwrap(accounts.first { $0.name != originalAccount.name })

        let switched = await engine.switchAccount(to: alternate)
        XCTAssertEqual(switched.state, .ready)
        XCTAssertEqual(switched.activeAccount?.name, alternate.name)
        XCTAssertEqual(switched.gitName, alternate.gitUserName)
        XCTAssertEqual(switched.gitEmail, alternate.gitEmail)

        let restored = await engine.switchAccount(to: originalAccount)
        XCTAssertEqual(restored.state, .ready)
        XCTAssertEqual(restored.activeAccount?.name, originalAccount.name)
        XCTAssertEqual(restored.gitName, originalAccount.gitUserName)
        XCTAssertEqual(restored.gitEmail, originalAccount.gitEmail)
    }
}

final class MockCommandRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    var authorized: [GitHubAccount]
    private var activeName: String
    private var gitUserName: String
    private var gitUserEmail: String
    var failEmailWrite = false
    var failApiUser = false
    var failAuthStatus = false
    var commandDelayNanoseconds: UInt64 = 0
    private(set) var switchCommandCount = 0
    private(set) var logoutCommandCount = 0
    private(set) var lastLogoutUser: String?
    private(set) var switchTargets: [String] = []
    private(set) var lastAuthStatusEnvironment: [String: String]?

    init(active: GitHubAccount, authorized: [GitHubAccount]? = nil) {
        self.authorized = authorized ?? [TestFixtures.primary, TestFixtures.secondary]
        self.activeName = active.name
        self.gitUserName = active.gitUserName
        self.gitUserEmail = active.email
    }

    func run(executable: String, arguments: [String], timeout: TimeInterval?, environment: [String: String]?) async -> CommandResult {
        if commandDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: commandDelayNanoseconds)
        }
        lock.lock()
        defer { lock.unlock() }

        if executable == Toolchain.ghPath {
            if arguments.prefix(2) == ["api", "--hostname"] {
                guard !failApiUser, authorized.contains(where: { $0.name == activeName }) else { return fail() }
                return ok(activeName + "\n")
            }
            if arguments.prefix(2) == ["auth", "status"] {
                lastAuthStatusEnvironment = environment
                if failAuthStatus {
                    // 模拟超时被终止：无任何输出
                    return CommandResult(exitCode: -1, stdout: "", stderr: "")
                }
                guard !authorized.isEmpty else {
                    return CommandResult(exitCode: 1, stdout: "", stderr: "Not logged in to any GitHub account.")
                }
                let text = authorized.map { account in
                    let marker = account.name == activeName ? "true" : "false"
                    return "  ✓ Logged in to github.com account \(account.name) (keyring)\n  - Active account: \(marker)"
                }.joined(separator: "\n")
                return CommandResult(exitCode: 0, stdout: "", stderr: text)
            }
            if arguments.prefix(2) == ["auth", "switch"], let userIndex = arguments.firstIndex(of: "--user") {
                guard userIndex + 1 < arguments.count,
                      let account = authorized.first(where: { $0.name == arguments[userIndex + 1] }) else { return fail() }
                activeName = account.name
                switchCommandCount += 1
                switchTargets.append(account.name)
                return ok()
            }
            if arguments.prefix(2) == ["auth", "setup-git"] { return ok() }
            if arguments.prefix(2) == ["auth", "logout"], let userIndex = arguments.firstIndex(of: "--user") {
                guard userIndex + 1 < arguments.count else { return fail() }
                let target = arguments[userIndex + 1]
                guard authorized.contains(where: { $0.name == target }) else {
                    return CommandResult(exitCode: 1, stdout: "", stderr: "not logged in to github.com account \(target)")
                }
                authorized.removeAll { $0.name == target }
                logoutCommandCount += 1
                lastLogoutUser = target
                if activeName == target {
                    activeName = authorized.first?.name ?? ""
                }
                return ok()
            }
        }

        if executable == Toolchain.gitPath,
           arguments.prefix(2) == ["config", "--global"] {
            if arguments.count == 4, arguments[2] == "--get" {
                if arguments[3] == "user.name" { return ok(gitUserName + "\n") }
                if arguments[3] == "user.email" { return ok(gitUserEmail + "\n") }
            }
            if arguments.count == 4, arguments[2] == "user.name" {
                gitUserName = arguments[3]
                return ok()
            }
            if arguments.count == 4, arguments[2] == "user.email" {
                if failEmailWrite {
                    failEmailWrite = false
                    return fail()
                }
                gitUserEmail = arguments[3]
                return ok()
            }
        }
        return fail()
    }

    private func ok(_ stdout: String = "") -> CommandResult {
        CommandResult(exitCode: 0, stdout: stdout, stderr: "")
    }

    private func fail() -> CommandResult {
        CommandResult(exitCode: 1, stdout: "", stderr: "mock failure")
    }
}
