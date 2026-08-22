import Foundation

struct CommandResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

protocol CommandRunning: Sendable {
    func run(executable: String, arguments: [String]) async -> CommandResult
}

struct ProcessCommandRunner: CommandRunning {
    func run(executable: String, arguments: [String]) async -> CommandResult {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.environment = [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "LANG": "zh_CN.UTF-8"
            ]

            do {
                try process.run()
                process.waitUntilExit()
                let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
            } catch {
                return CommandResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
            }
        }.value
    }
}
