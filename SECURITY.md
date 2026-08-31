# 安全政策 / Security Policy

## 报告安全问题

请不要在公开 Issue、Discussion、日志或截图中披露尚未修复的漏洞、GitHub token、钥匙串内容或完整的 `gh auth status` 输出。

优先使用仓库 **Security** 页面中的 **Report a vulnerability** 私密入口。如果该入口不可见，请创建一个不包含漏洞细节的 Issue，仅说明需要与维护者建立私密联系渠道。

报告中请包含：

- 受影响的 GitSwitch 版本或提交
- macOS、GitHub CLI 和 Git 版本
- 最小复现步骤与预期/实际结果
- 潜在影响和已知缓解方式
- 已删除 token、账号、邮箱和个人路径的必要日志

GitSwitch 会调用 GitHub CLI、修改当前 macOS 用户的全局 Git 配置，并提供只绑定 `127.0.0.1:47831` 的本地状态服务。若问题属于 GitHub CLI、Git 或 macOS 本身，请同时确认能否在不运行 GitSwitch 的情况下复现；GitSwitch 集成导致的问题仍可在本仓库报告。

本项目目前不承诺固定的安全支持周期或响应时限。请在报告中明确受影响版本，不要假设旧 Release 与 `main` 具有相同实现。

---

## Reporting a vulnerability

Do not disclose an unpatched vulnerability, GitHub token, Keychain content, or complete `gh auth status` output in a public Issue, Discussion, log, or screenshot.

Prefer the private **Report a vulnerability** entry on the repository's **Security** page. If that entry is unavailable, open an Issue without vulnerability details and request a private contact channel from the maintainer.

Include the affected GitSwitch version or commit; macOS, GitHub CLI, and Git versions; minimal reproduction steps; expected and actual behavior; potential impact; known mitigations; and only the necessary logs after removing tokens, accounts, email addresses, and personal paths.

GitSwitch invokes GitHub CLI, changes the current macOS user's global Git configuration, and exposes a local status service bound only to `127.0.0.1:47831`. For behavior that may originate in GitHub CLI, Git, or macOS, check whether it reproduces without GitSwitch. Integration issues caused by GitSwitch can still be reported here.

The project does not currently promise a fixed security-support lifecycle or response time. Identify the affected version explicitly instead of assuming an older Release matches `main`.
