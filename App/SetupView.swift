import ServiceManagement
import SwiftUI

struct SetupView: View {
    @State private var status = SwitcherStatus.offline
    @State private var ghInstalled = false
    @State private var gitInstalled = false
    @State private var accountsReady = false
    @State private var accountSummary = ""
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var actionMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("GitSwitch")
                        .font(.title2.bold())
                    Text("桌面小组件的后台助手")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(spacing: 10) {
                    checkRow("GitHub CLI", ok: ghInstalled, detail: ghInstalled ? Toolchain.ghPath : "未找到，请 brew install gh")
                    checkRow("Git", ok: gitInstalled, detail: Toolchain.gitPath)
                    checkRow("已配置账号", ok: accountsReady, detail: accountSummary)
                    checkRow("登录后后台运行", ok: loginStatus == .enabled, detail: loginStatusText)
                }
                .padding(4)
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前账号")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(status.activeAccount?.name ?? "无法读取")
                        .font(.headline)
                }
                Spacer()
                Button("重新检查") { Task { await refresh() } }
                if loginStatus != .enabled {
                    Button("启用后台运行") { registerLoginItem() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("完成后，在桌面点右键 → 编辑小组件，搜索“GitSwitch”。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .task { await refresh() }
    }

    private func checkRow(_ title: String, ok: Bool, detail: String) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(title)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var loginStatusText: String {
        switch loginStatus {
        case .enabled: return "已启用"
        case .requiresApproval: return "需要在系统设置中批准"
        case .notRegistered: return "未注册"
        case .notFound: return "应用需安装到 /Applications"
        @unknown default: return "未知状态"
        }
    }

    @MainActor
    private func refresh() async {
        ghInstalled = FileManager.default.isExecutableFile(atPath: Toolchain.ghPath)
        gitInstalled = FileManager.default.isExecutableFile(atPath: Toolchain.gitPath)
        status = await SwitchCoordinator.shared.currentStatus(refresh: true)
        loginStatus = SMAppService.mainApp.status

        let auth = await ProcessCommandRunner().run(
            executable: Toolchain.ghPath,
            arguments: ["auth", "status", "--hostname", "github.com"]
        )
        let authText = auth.stdout + auth.stderr
        let storedAccounts = AccountStore.load()
        accountsReady = auth.succeeded && !storedAccounts.isEmpty
        accountSummary = storedAccounts.isEmpty ? "未配置，请点击小组件后新增账号" : storedAccounts.map(\.name).joined(separator: " · ")
    }

    @MainActor
    private func registerLoginItem() {
        do {
            try SMAppService.mainApp.register()
            loginStatus = SMAppService.mainApp.status
            actionMessage = loginStatus == .enabled ? "后台运行已启用。" : "请在系统设置 → 通用 → 登录项中批准。"
        } catch {
            actionMessage = "无法启用：\(error.localizedDescription)"
        }
    }
}
