import SwiftUI

/// 编辑账号的本地 Git 提交身份（user.name / user.email），提供“还原默认配置”。
struct AccountEditView: View {
    let account: GitHubAccount
    /// 返回 true 表示保存成功，视图自行关闭。
    let onCommit: (GitHubAccount) async -> Bool
    let onDismiss: () -> Void

    @State private var gitUserName: String
    @State private var email: String
    @State private var isSaving = false
    @State private var message: String?
    @State private var didReset = false

    init(account: GitHubAccount, onCommit: @escaping (GitHubAccount) async -> Bool, onDismiss: @escaping () -> Void) {
        self.account = account
        self.onCommit = onCommit
        self.onDismiss = onDismiss
        _gitUserName = State(initialValue: account.gitUserName)
        _email = State(initialValue: account.email)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("编辑 Git 提交身份")
                    .font(.title2.bold())
                Text("账号 \(account.name) 的本地 Git 用户名和邮箱，切换到该账号时写入全局配置。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Git 用户名（user.name）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("默认与 GitHub 用户名一致", text: $gitUserName)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Git 邮箱（user.email）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("提交邮箱", text: $email)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Button {
                gitUserName = account.name
                email = account.resetEmail
                didReset = true
                message = nil
            } label: {
                Label("还原默认配置", systemImage: "arrow.counterclockwise")
            }
            .help("用户名还原为 \(account.name)，邮箱还原为 \(account.resetEmail)")

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(didReset ? Color.secondary : Color.red)
                    .lineLimit(2)
            }

            if didReset {
                Text("已还原为默认值，点击“保存”生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("取消", action: onDismiss)
                    .disabled(isSaving)
                Button("保存") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || normalizedGitUserName.isEmpty || normalizedEmail.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420, height: 340)
    }

    private var normalizedGitUserName: String {
        gitUserName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        message = nil

        // 与登录名相同时不保存自定义值，保持“默认”语义；首次编辑时固化默认邮箱，供以后还原。
        let updated = GitHubAccount(
            name: account.name,
            email: normalizedEmail,
            gitName: normalizedGitUserName == account.name ? nil : normalizedGitUserName,
            defaultEmail: account.defaultEmail ?? account.email
        )
        let success = await onCommit(updated)
        isSaving = false
        if success {
            onDismiss()
        } else {
            didReset = false
            message = "保存失败，请重试"
        }
    }
}
