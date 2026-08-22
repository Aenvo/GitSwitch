import SwiftUI
import WidgetKit

struct AccountChooserView: View {
    let onDismiss: () -> Void

    @State private var status = SwitcherStatus.offline
    @State private var accounts: [GitHubAccount] = []
    @State private var selectedAccount: GitHubAccount?
    @State private var isSwitching = false
    @State private var message: String?
    @State private var isAddingAccount = false
    @State private var pendingDeletion: GitHubAccount?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择 GitHub 账号")
                        .font(.title2.bold())
                    Text("勾选账号后，点击右下角的“确定”。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isAddingAccount = true
                } label: {
                    Label("新增账号", systemImage: "plus")
                }
                .disabled(isSwitching)
            }

            if accounts.isEmpty {
                Text("暂无账号，点击“新增账号”添加。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(accounts) { account in
                            accountRow(account)
                        }
                    }
                }
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            HStack {
                if isSwitching {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在处理…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消", action: onDismiss)
                    .disabled(isSwitching)
                Button("确定") {
                    Task { await confirmSelection() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedAccount == nil || isSwitching)
            }
        }
        .padding(22)
        .task { await loadStatus() }
        .sheet(isPresented: $isAddingAccount) {
            AddAccountView(
                onCommit: adoptAccount,
                onDismiss: { isAddingAccount = false }
            )
        }
        .alert(
            "确定要删除该账号吗？",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { account in
            Button("删除", role: .destructive) {
                Task { await deleteAccount(account) }
            }
            Button("取消", role: .cancel) {}
        } message: { account in
            Text("删除后将注销账号 \(account.name) 在本机的 GitHub CLI 授权，并从列表中移除。")
        }
    }

    private func accountRow(_ account: GitHubAccount) -> some View {
        HStack(spacing: 0) {
            Button {
                selectedAccount = account
                message = nil
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selectedAccount == account ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedAccount == account ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name)
                            .font(.headline)
                        Text(account.email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if status.activeAccount?.name == account.name {
                        Text("当前")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
                .padding(.leading, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSwitching)

            Button {
                pendingDeletion = account
            } label: {
                Image(systemName: "trash")
                    .font(.callout)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(isSwitching)
            .help("删除账号")
            .padding(.trailing, 6)
        }
        .background(
            selectedAccount == account ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    @MainActor
    private func loadStatus() async {
        status = await SwitchCoordinator.shared.currentStatus(refresh: true)
        accounts = await SwitchCoordinator.shared.accounts
        selectedAccount = status.activeAccount.flatMap { current in
            accounts.first { $0 == current }
        }
        if status.activeAccount == nil {
            message = status.message ?? "无法读取当前 GitHub 账号"
        }
    }

    @MainActor
    private func confirmSelection() async {
        guard let selectedAccount else { return }
        guard selectedAccount != status.activeAccount else {
            onDismiss()
            return
        }

        isSwitching = true
        message = nil
        let result = await SwitchCoordinator.shared.switchAccount(to: selectedAccount)
        status = result
        isSwitching = false
        WidgetCenter.shared.reloadAllTimelines()

        if result.state == .ready, result.activeAccount?.name == selectedAccount.name {
            onDismiss()
        } else {
            message = result.message ?? "切换失败，请重试"
        }
    }

    @MainActor
    private func adoptAccount(_ account: GitHubAccount) async -> Bool {
        isSwitching = true
        message = nil
        let result = await SwitchCoordinator.shared.adoptNewAccount(account)
        status = result
        accounts = await SwitchCoordinator.shared.accounts
        isSwitching = false
        WidgetCenter.shared.reloadAllTimelines()

        guard result.activeAccount?.name == account.name else {
            message = result.message ?? "账号保存失败"
            return false
        }
        selectedAccount = account
        return true
    }

    @MainActor
    private func deleteAccount(_ target: GitHubAccount) async {
        isSwitching = true
        message = nil
        let result = await SwitchCoordinator.shared.removeAccount(target)
        fputs("GitSwitch: deleted \(target.name), state=\(result.state.rawValue), message=\(result.message ?? "-")\n", stderr)
        status = result
        accounts = await SwitchCoordinator.shared.accounts
        if selectedAccount == target {
            selectedAccount = result.activeAccount.flatMap { current in accounts.first { $0 == current } }
        }
        isSwitching = false
        WidgetCenter.shared.reloadAllTimelines()

        if result.state == .error {
            message = result.message ?? "删除失败，请重试"
        } else if result.activeAccount == nil {
            message = "已删除 \(target.name)。当前没有可用的 GitHub 账号。"
        }
    }
}
