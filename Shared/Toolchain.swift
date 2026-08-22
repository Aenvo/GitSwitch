import Foundation

/// 外部命令路径解析。gh 位置随安装方式变化（Apple Silicon/Intel Homebrew、系统、MacPorts），
/// 进程启动时探测一次并缓存；git 在所有 macOS 上固定为系统路径。
enum Toolchain {
    static let gitPath = "/usr/bin/git"

    static let ghPath: String = {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
            "/opt/local/bin/gh"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
    }()
}
