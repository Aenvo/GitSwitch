import AppKit
import SwiftUI

struct AddAccountView: View {
    /// 返回 true 表示保存成功，视图自行关闭。
    let onCommit: (GitHubAccount) async -> Bool
    let onDismiss: () -> Void

    @StateObject private var auth = AuthFlowController()
    @State private var username = ""
    @State private var email = ""
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var copiedValue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("新增 GitHub 账号")
                    .font(.title2.bold())
                Text("填写账号信息后，将在浏览器中完成 GitHub 授权。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            switch auth.phase {
            case .idle, .failed:
                inputForm
            case .waitingForBrowser:
                waitingView
            case .authenticated(let login):
                authenticatedView(login: login)
            }

            Spacer(minLength: 0)

            HStack {
                if saveMessage != nil {
                    Text(saveMessage ?? "")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                Button("取消", action: handleCancel)
                    .disabled(isSaving)
            }
        }
        .padding(22)
        .frame(width: 420, height: 380)
    }

    private var inputForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            if case let .failed(message) = auth.phase {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("用户名")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("GitHub 用户名", text: $username)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("邮箱")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("提交用邮箱（留空自动使用 GitHub noreply 邮箱）", text: $email)
                    .textFieldStyle(.roundedBorder)
            }
            Button {
                auth.start()
            } label: {
                Label("开始授权", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var waitingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if case let .waitingForBrowser(code, url) = auth.phase {
                VStack(alignment: .leading, spacing: 10) {
                    Text("在浏览器中输入以下一次性代码：")
                        .font(.callout)
                    HStack(spacing: 8) {
                        Text(code)
                            .font(.system(.title2, design: .monospaced, weight: .bold))
                            .textSelection(.enabled)
                        Button {
                            copyToPasteboard(code)
                        } label: {
                            Image(systemName: copiedValue == code ? "checkmark" : "doc.on.doc")
                                .font(.callout)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(copiedValue == code ? Color.green : Color.secondary)
                        .help(copiedValue == code ? "已复制" : "复制代码")
                    }
                    HStack(spacing: 8) {
                        Button("重新打开浏览器") {
                            if let target = URL(string: url) {
                                NSWorkspace.shared.open(target)
                            }
                        }
                        Text(url)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("等待授权完成…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("取消授权") { auth.cancel() }
                }
            }
        }
    }

    private func authenticatedView(login: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("授权成功：\(login)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if !normalizedEnteredUsername.isEmpty && normalizedEnteredUsername != login {
                Text("输入的用户名（\(normalizedEnteredUsername)）与授权账号不一致，将按授权账号 \(login) 保存。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Git 提交邮箱")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("noreply 邮箱", text: $email)
                    .textFieldStyle(.roundedBorder)
            }
            Button {
                Task { await save(login: login) }
            } label: {
                Label("保存账号", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || normalizedEmail.isEmpty)
        }
        .task {
            if email.isEmpty {
                email = await defaultEmail(for: login)
            }
        }
    }

    private var normalizedEnteredUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedValue = value
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if copiedValue == value {
                copiedValue = nil
            }
        }
    }

    private func defaultEmail(for login: String) async -> String {
        if let id = await auth.userID(for: login) {
            return GitHubAccount.noreplyEmail(userID: id, login: login)
        }
        return "\(login)@users.noreply.github.com"
    }

    private func save(login: String) async {
        guard !isSaving else { return }
        isSaving = true
        saveMessage = nil
        let account = GitHubAccount(name: login, email: normalizedEmail)
        let success = await onCommit(account)
        isSaving = false
        if success {
            onDismiss()
        } else {
            saveMessage = "保存失败，请重试"
        }
    }

    private func handleCancel() {
        auth.cancel()
        onDismiss()
    }
}
