import XCTest

final class AccountSwitchingEngineTests: XCTestCase {
    private var aenvo: GitHubAccount {
        GitHubAccount(name: "Aenvo", email: "octocat@users.noreply.github.com")
    }

    private var ykSteven: GitHubAccount {
        GitHubAccount(name: "hubot", email: "hubot@users.noreply.github.com")
    }

    private func makeDefaults() -> UserDefaults {
        let name = "GitSwitchTests-\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name)!
    }

    /// 引擎与协调器共享同一个 defaults，模拟真实运行时账号列表与状态映射的一致性。
    private func makeEngine(_ mock: MockCommandRunner, defaults: UserDefaults) -> AccountSwitchingEngine {
        AccountSwitchingEngine(runner: mock, accountsProvider: { AccountStore.load(defaults: defaults) })
    }

    func testAccountProfiles() {
        XCTAssertEqual(aenvo.gitName, "Aenvo")
        XCTAssertEqual(aenvo.gitEmail, "octocat@users.noreply.github.com")
        XCTAssertEqual(ykSteven.gitEmail, "hubot@users.noreply.github.com")
        XCTAssertEqual(GitHubAccount.noreplyEmail(userID: "42", login: "octocat"), "42+octocat@users.noreply.github.com")
    }

    func testAccountStoreSeedsPersistsAndRemoves() {
        let defaults = makeDefaults()
        XCTAssertEqual(AccountStore.load(defaults: defaults), AccountStore.seeds)

        let third = GitHubAccount(name: "octocat", email: "583231+octocat@users.noreply.github.com")
        AccountStore.add(third, defaults: defaults)
        XCTAssertEqual(AccountStore.load(defaults: defaults).count, 3)
        XCTAssertTrue(AccountStore.load(defaults: defaults).contains(third))

        AccountStore.remove(ykSteven, defaults: defaults)
        XCTAssertFalse(AccountStore.load(defaults: defaults).contains { $0.name == ykSteven.name })
    }

    func testToolchainResolvesPaths() {
        XCTAssertFalse(Toolchain.ghPath.isEmpty)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: Toolchain.gitPath))
    }

    func testSeededAccountReconciler() {
        // 播种账号中至少一个已在 gh 授权（老用户机器）→ 保持不变
        XCTAssertNil(SeededAccountReconciler.reconciledList(
            stored: AccountStore.seeds,
            ghAuthStatusText: "✓ Logged in to github.com account Aenvo"
        ))
        // 播种账号均未授权（新用户机器）→ 清空引导新增
        XCTAssertEqual(
            SeededAccountReconciler.reconciledList(stored: AccountStore.seeds, ghAuthStatusText: "You are not logged into any GitHub account."),
            []
        )
        // 用户已自行管理过列表 → 不做调整
        XCTAssertNil(SeededAccountReconciler.reconciledList(
            stored: [GitHubAccount(name: "octocat", email: "583231+octocat@users.noreply.github.com")],
            ghAuthStatusText: ""
        ))
    }

    func testSuccessfulSwitchVerifiesAccountAndIdentity() async {
        let runner = MockCommandRunner(active: aenvo)
        let engine = makeEngine(runner, defaults: makeDefaults())

        let status = await engine.switchAccount(to: ykSteven)

        XCTAssertEqual(status.state, .ready)
        XCTAssertEqual(status.activeAccount?.name, "hubot")
        XCTAssertEqual(status.gitName, "hubot")
        XCTAssertEqual(status.gitEmail, ykSteven.gitEmail)
    }

    func testFailureRollsBackAccountAndIdentity() async {
        let runner = MockCommandRunner(active: aenvo)
        runner.failEmailWrite = true
        let engine = makeEngine(runner, defaults: makeDefaults())

        let status = await engine.switchAccount(to: ykSteven)

        XCTAssertEqual(status.state, .error)
        XCTAssertEqual(status.activeAccount?.name, "Aenvo")
        XCTAssertEqual(status.gitName, "Aenvo")
        XCTAssertEqual(status.gitEmail, aenvo.gitEmail)
    }

    func testConcurrentSwitchIsCoalesced() async {
        let runner = MockCommandRunner(active: aenvo)
        runner.commandDelayNanoseconds = 20_000_000
        let coordinator = SwitchCoordinator(engine: makeEngine(runner, defaults: makeDefaults()), defaults: makeDefaults())

        async let first = coordinator.switchAccount(to: ykSteven)
        async let second = coordinator.switchAccount(to: ykSteven)
        _ = await (first, second)

        XCTAssertEqual(runner.switchCommandCount, 1)
    }

    func testToggleChoosesFirstAlternate() async {
        let runner = MockCommandRunner(active: aenvo)
        let defaults = makeDefaults()
        let coordinator = SwitchCoordinator(engine: makeEngine(runner, defaults: defaults), defaults: defaults)

        let status = await coordinator.toggleAccount()

        XCTAssertEqual(status.state, .ready)
        XCTAssertEqual(status.activeAccount?.name, "hubot")
        XCTAssertEqual(status.gitName, ykSteven.gitName)
        XCTAssertEqual(status.gitEmail, ykSteven.gitEmail)
    }

    func testToggleWithoutAlternateReportsError() async {
        let runner = MockCommandRunner(active: aenvo)
        let defaults = makeDefaults()
        AccountStore.save([aenvo], defaults: defaults)
        let coordinator = SwitchCoordinator(engine: makeEngine(runner, defaults: defaults), defaults: defaults)

        let status = await coordinator.toggleAccount()

        XCTAssertEqual(status.state, .error)
        XCTAssertEqual(status.activeAccount?.name, "Aenvo")
        XCTAssertEqual(status.message, "没有其他可切换的账号")
    }

    func testLogoutRunsGhAuthLogoutWithUserFlag() async {
        let runner = MockCommandRunner(active: aenvo)
        let engine = makeEngine(runner, defaults: makeDefaults())

        let result = await engine.logout(ykSteven)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(runner.logoutCommandCount, 1)
        XCTAssertEqual(runner.lastLogoutUser, "hubot")
    }

    func testRemoveNonActiveAccountSkipsSwitch() async {
        let runner = MockCommandRunner(active: aenvo)
        let defaults = makeDefaults()
        let coordinator = SwitchCoordinator(engine: makeEngine(runner, defaults: defaults), defaults: defaults)

        let status = await coordinator.removeAccount(ykSteven)
        let accounts = await coordinator.accounts

        XCTAssertEqual(runner.switchCommandCount, 0)
        XCTAssertEqual(runner.logoutCommandCount, 1)
        XCTAssertEqual(status.activeAccount?.name, "Aenvo")
        XCTAssertFalse(accounts.contains { $0.name == ykSteven.name })
    }

    func testRemoveActiveAccountSwitchesFirstThenLogsOut() async {
        let runner = MockCommandRunner(active: aenvo)
        let defaults = makeDefaults()
        let coordinator = SwitchCoordinator(engine: makeEngine(runner, defaults: defaults), defaults: defaults)

        let status = await coordinator.removeAccount(aenvo)
        let accounts = await coordinator.accounts

        XCTAssertEqual(runner.switchCommandCount, 1)
        XCTAssertEqual(runner.switchTargets, ["hubot"])
        XCTAssertEqual(runner.logoutCommandCount, 1)
        XCTAssertEqual(runner.lastLogoutUser, "Aenvo")
        XCTAssertEqual(status.activeAccount?.name, "hubot")
        XCTAssertFalse(accounts.contains { $0.name == aenvo.name })
    }

    func testAdoptNewAccountSwitchesIdentityAndStores() async {
        let octocat = GitHubAccount(name: "octocat", email: "583231+octocat@users.noreply.github.com")
        let runner = MockCommandRunner(active: aenvo)
        runner.authorized.append(octocat)
        let defaults = makeDefaults()
        let coordinator = SwitchCoordinator(engine: makeEngine(runner, defaults: defaults), defaults: defaults)

        let status = await coordinator.adoptNewAccount(octocat)
        let accounts = await coordinator.accounts

        XCTAssertEqual(status.state, .ready)
        XCTAssertEqual(status.activeAccount?.name, "octocat")
        XCTAssertEqual(status.gitEmail, octocat.email)
        XCTAssertTrue(accounts.contains { $0.name == "octocat" })
    }

    func testLiveBidirectionalSwitchAndRestore() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_SWITCH_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_LIVE_SWITCH_TESTS=1 to exercise the real gh and git configuration.")
        }
        let engine = AccountSwitchingEngine()
        let original = await engine.readStatus()
        let originalAccount = try XCTUnwrap(original.activeAccount)
        let alternate = try XCTUnwrap(AccountStore.load().first { $0.name != originalAccount.name })

        let switched = await engine.switchAccount(to: alternate)
        XCTAssertEqual(switched.state, .ready)
        XCTAssertEqual(switched.activeAccount?.name, alternate.name)
        XCTAssertEqual(switched.gitName, alternate.gitName)
        XCTAssertEqual(switched.gitEmail, alternate.gitEmail)

        let restored = await engine.switchAccount(to: originalAccount)
        XCTAssertEqual(restored.state, .ready)
        XCTAssertEqual(restored.activeAccount?.name, originalAccount.name)
        XCTAssertEqual(restored.gitName, originalAccount.gitName)
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
    var commandDelayNanoseconds: UInt64 = 0
    private(set) var switchCommandCount = 0
    private(set) var logoutCommandCount = 0
    private(set) var lastLogoutUser: String?
    private(set) var switchTargets: [String] = []

    init(active: GitHubAccount, authorized: [GitHubAccount]? = nil) {
        self.authorized = authorized ?? AccountStore.seeds
        self.activeName = active.name
        self.gitUserName = active.gitName
        self.gitUserEmail = active.email
    }

    func run(executable: String, arguments: [String]) async -> CommandResult {
        if commandDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: commandDelayNanoseconds)
        }
        lock.lock()
        defer { lock.unlock() }

        if executable == Toolchain.ghPath {
            if arguments.prefix(2) == ["api", "--hostname"] {
                guard authorized.contains(where: { $0.name == activeName }) else { return fail() }
                return ok(activeName + "\n")
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
