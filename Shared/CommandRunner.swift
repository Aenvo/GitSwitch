import Foundation

struct CommandResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

protocol CommandRunning: Sendable {
    func run(executable: String, arguments: [String], timeout: TimeInterval?, environment: [String: String]?) async -> CommandResult
}

extension CommandRunning {
    func run(executable: String, arguments: [String]) async -> CommandResult {
        await run(executable: executable, arguments: arguments, timeout: nil, environment: nil)
    }

    func run(executable: String, arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        await run(executable: executable, arguments: arguments, timeout: timeout, environment: nil)
    }
}

struct ProcessCommandRunner: CommandRunning {
    func run(executable: String, arguments: [String], timeout: TimeInterval? = nil, environment: [String: String]? = nil) async -> CommandResult {
        await Task.detached(priority: .userInitiated) { () -> CommandResult in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            var baseEnvironment = [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "LANG": "zh_CN.UTF-8"
            ]
            if let environment {
                baseEnvironment.merge(environment) { _, new in new }
            }
            process.environment = baseEnvironment

            do {
                try process.run()
                if let timeout {
                    let deadline = Date().addingTimeInterval(timeout)
                    while process.isRunning && Date() < deadline {
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                    if process.isRunning {
                        process.terminate()
                        process.waitUntilExit()
                        return CommandResult(exitCode: -1, stdout: "", stderr: "命令超时（\(Int(timeout))秒）")
                    }
                } else {
                    process.waitUntilExit()
                }
                let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
            } catch {
                return CommandResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
            }
        }.value
    }
}
