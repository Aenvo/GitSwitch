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
    @State private var editingAccount: GitHubAccount?
    @State private var hoveredAccount: String?
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?

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

            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(2)
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
        .sheet(isPresented: $isAddingAccount, onDismiss: reloadAfterSheet) {
            AddAccountView(
                onCommit: adoptAccount,
                onDismiss: { isAddingAccount = false }
            )
        }
        .sheet(item: $editingAccount, onDismiss: reloadAfterSheet) { account in
            AccountEditView(
                account: account,
                onCommit: updateAccount,
                onDismiss: { editingAccount = nil }
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
                        Text(account.gitUserName)
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
                .padding(.trailing, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSwitching)

            // 悬浮到条目时才插入编辑/删除入口：默认不占位，“当前”标记贴住行尾；
            // 悬浮出现按钮时将其向左挤压（带动画）。
            if isHovering(account) && !isSwitching {
                HStack(spacing: 2) {
                    rowAction(icon: "pencil", help: "编辑 Git 提交身份") {
                        editingAccount = account
                    }
                    rowAction(icon: "trash", help: "删除账号") {
                        pendingDeletion = account
                    }
                }
                .padding(.trailing, 6)
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredAccount = hovering ? account.name : nil
            }
        }
        .background(
            selectedAccount == account ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private func isHovering(_ account: GitHubAccount) -> Bool {
        hoveredAccount == account.name
    }

    private func rowAction(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.callout)
                .frame(width: 30, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .disabled(isSwitching)
        .help(help)
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
    private func updateAccount(_ updated: GitHubAccount) async -> Bool {
        isSwitching = true
        message = nil
        let result = await SwitchCoordinator.shared.updateAccount(updated)
        status = result
        accounts = await SwitchCoordinator.shared.accounts
        if selectedAccount?.name == updated.name {
            selectedAccount = updated
        }
        isSwitching = false
        WidgetCenter.shared.reloadAllTimelines()

        guard result.state != .error else {
            message = result.message ?? "保存失败，请重试"
            return false
        }
        if status.activeAccount?.name == updated.name {
            showNotice("已更新 \(updated.name) 的 Git 身份，并写入全局配置")
        } else {
            showNotice("已更新 \(updated.name) 的 Git 身份，切换到该账号时生效")
        }
        return true
    }

    /// 表单关闭后兜底刷新列表与状态，保证界面与存储一致（不改动已选中的账号）。
    @MainActor
    private func reloadAfterSheet() {
        Task {
            accounts = await SwitchCoordinator.shared.accounts
            status = await SwitchCoordinator.shared.currentStatus()
        }
    }

    private func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { notice = nil }
            }
        }
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
