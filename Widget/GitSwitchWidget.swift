import SwiftUI
import WidgetKit

struct AccountEntry: TimelineEntry {
    let date: Date
    let status: SwitcherStatus
}

struct AccountProvider: TimelineProvider {
    func placeholder(in context: Context) -> AccountEntry {
        AccountEntry(
            date: Date(),
            status: SwitcherStatus(
                state: .ready,
                activeAccount: GitHubAccount(name: "octocat", email: GitHubAccount.noreplyEmail(userID: "583231", login: "octocat")),
                gitName: "octocat",
                gitEmail: GitHubAccount.noreplyEmail(userID: "583231", login: "octocat"),
                message: nil,
                updatedAt: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AccountEntry) -> Void) {
        Task { completion(AccountEntry(date: Date(), status: await StatusClient().fetch())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AccountEntry>) -> Void) {
        Task {
            let entry = AccountEntry(date: Date(), status: await StatusClient().fetch())
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(120))))
        }
    }
}

struct GitSwitchWidgetView: View {
    let entry: AccountEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(statusHeading, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.bold())
                    .widgetAccentable()
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }

            Text(accountTitle)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .invalidatableContent(entry.status.state == .switching)
                .padding(.top, 12)

            if let detailText {
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 3)
            }

            Spacer(minLength: 14)
            actionButton
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch entry.status.state {
        case .offline:
            Link(destination: accountChooserURL) {
                Label("重试", systemImage: "arrow.clockwise")
                    .githubWidgetButtonLabel()
            }
            .buttonStyle(.plain)
        case .switching:
            Button(action: {}) {
                Text("切换中…")
                    .githubWidgetButtonLabel()
            }
                .buttonStyle(.plain)
                .disabled(true)
        case .ready, .error, .offlineCached:
            if entry.status.activeAccount != nil {
                Link(destination: accountChooserURL) {
                    Text("切换当前账号")
                        .lineLimit(1)
                        .githubWidgetButtonLabel()
                }
                .buttonStyle(.plain)
            } else {
                Link(destination: accountChooserURL) {
                    Text("重试")
                        .githubWidgetButtonLabel()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var accountTitle: String {
        entry.status.activeAccount?.name ?? "暂时不可用"
    }

    private var statusHeading: String {
        "GitHub"
    }

    private var detailText: String? {
        switch entry.status.state {
        case .ready: return nil
        case .switching: return "请稍候"
        case .error: return entry.status.message ?? "切换失败"
        case .offline: return "助手暂时不可用"
        case .offlineCached: return "GitHub 暂时不可达"
        }
    }

    private var statusColor: Color {
        switch entry.status.state {
        case .ready: return .green
        case .switching: return .yellow
        case .error: return .orange
        case .offline: return .secondary
        case .offlineCached: return .gray
        }
    }

    private var accountChooserURL: URL {
        URL(string: "gitswitch://choose")!
    }
}

private extension View {
    func githubWidgetButtonLabel() -> some View {
        self
            .font(.caption.bold())
            .foregroundStyle(Color.primary.opacity(0.82))
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(Color.white.opacity(0.16), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.7)
            }
            .contentShape(Capsule())
    }
}

@main
struct GitSwitchWidget: Widget {
    let kind = "GitSwitchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AccountProvider()) { entry in
            GitSwitchWidgetView(entry: entry)
        }
        .configurationDisplayName("GitSwitch")
        .description("查看并切换当前 GitHub CLI 账号。")
        .supportedFamilies([.systemSmall])
    }
}
