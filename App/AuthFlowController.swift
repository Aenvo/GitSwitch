import AppKit
import Foundation

@MainActor
final class AuthFlowController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case waitingForBrowser(code: String, url: String)
        case authenticated(login: String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isRunning = false

    private var process: Process?
    private let runner = ProcessCommandRunner()

    /// 启动 GitHub 设备码授权。gh 在无终端环境下会把一次性码和授权 URL 打印到 stderr 并等待浏览器完成授权。
    func start() {
        guard !isRunning else { return }
        phase = .idle
        isRunning = true

        let ghProcess = Process()
        let stderrPipe = Pipe()
        ghProcess.executableURL = URL(fileURLWithPath: AccountSwitchingEngine.ghPath)
        ghProcess.arguments = [
            "auth", "login",
            "--hostname", "github.com",
            "--git-protocol", "https",
            "--skip-ssh-key",
            "--web"
        ]
        ghProcess.standardInput = FileHandle.nullDevice
        ghProcess.standardOutput = stderrPipe
        ghProcess.standardError = stderrPipe
        ghProcess.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "LANG": "zh_CN.UTF-8",
            "NO_COLOR": "1"
        ]
        process = ghProcess

        let lineHandler = LineBuffer { [weak self] line in
            Task { @MainActor in self?.handle(line: line) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            lineBufferAppend(lineHandler, data)
        }

        do {
            try ghProcess.run()
        } catch {
            isRunning = false
            phase = .failed("无法启动 gh 授权进程：\(error.localizedDescription)")
            return
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            ghProcess.waitUntilExit()
            let code = ghProcess.terminationStatus
            await MainActor.run { [weak self] in
                self?.handleProcessExit(code: code)
            }
        }
    }

    func cancel() {
        guard isRunning else { return }
        process?.terminate()
    }

    private func handleProcessExit(code: Int32) {
        isRunning = false
        process = nil
        if code == 0 {
            Task { @MainActor in await resolveAuthenticatedLogin() }
        } else if case .failed = phase {
            return
        } else {
            phase = .failed("授权未完成或已取消")
        }
    }

    private func handle(line: String) {
        guard isRunning else { return }
        if case .idle = phase,
           let code = Self.oneTimeCode(from: line) {
            let url = Self.deviceURL(from: line) ?? "https://github.com/login/device"
            phase = .waitingForBrowser(code: code, url: url)
            if let target = URL(string: url) {
                NSWorkspace.shared.open(target)
            }
        }
    }

    /// gh 退出码为 0 后，读取实际授权的登录名。结果在 phase 中以 authenticated 发布。
    private func resolveAuthenticatedLogin() async {
        let loginResult = await runner.run(
            executable: AccountSwitchingEngine.ghPath,
            arguments: ["api", "--hostname", "github.com", "user", "--jq", ".login"]
        )
        let login = loginResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard loginResult.succeeded, !login.isEmpty else {
            phase = .failed("授权已完成，但无法读取账号名")
            return
        }
        phase = .authenticated(login: login)
    }

    /// 授权成功后由调用方读取，用于生成 noreply 邮箱默认值。
    func userID(for login: String) async -> String? {
        let result = await runner.run(
            executable: AccountSwitchingEngine.ghPath,
            arguments: ["api", "--hostname", "github.com", "user", "--jq", ".id"]
        )
        let id = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.succeeded && !id.isEmpty ? id : nil
    }

    private static func oneTimeCode(from line: String) -> String? {
        guard line.contains("one-time code") || line.contains("一次性代码") else { return nil }
        guard let range = line.range(of: #"[A-Z0-9]{4}-[A-Z0-9]{4}"#, options: .regularExpression) else {
            return nil
        }
        return String(line[range])
    }

    private static func deviceURL(from line: String) -> String? {
        guard let range = line.range(of: #"https://\S+"#, options: .regularExpression) else { return nil }
        return String(line[range])
    }
}

/// 按行切分管道数据的简易缓冲。
private final class LineBuffer {
    private var buffer = Data()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        buffer.append(data)
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            var lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer = Data(buffer[buffer.index(after: newlineIndex)...])
            if lineData.last == UInt8(ascii: "\r") {
                lineData = lineData.dropLast()
            }
            if let line = String(data: Data(lineData), encoding: .utf8), !line.isEmpty {
                onLine(line)
            }
        }
    }
}

private func lineBufferAppend(_ buffer: LineBuffer, _ data: Data) {
    buffer.append(data)
}
