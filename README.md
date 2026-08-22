# GitSwitch

原生 macOS 桌面小组件 + 后台助手：在多个 GitHub CLI（`gh`）账号之间一键切换，并自动同步全局 Git 提交身份。支持在应用内新增（GitHub 设备码授权）和删除（二次确认）账号。

## 功能

- **桌面小组件**展示当前 GitHub 账号，点击“切换当前账号”打开选择窗口。
- **账号切换**：勾选目标账号并“确定”，执行 `gh auth switch` → `gh auth setup-git` → 写入全局 `user.name` / `user.email` → 完整验证，任一步失败自动回滚到原状态。
- **新增账号**：填写用户名和邮箱（邮箱留空自动派生 GitHub noreply 邮箱），在窗口内完成 GitHub 设备码授权后保存；账号名以 `gh api user` 的实际结果为准。
- **删除账号**：二次确认后注销该账号在本机的 GitHub CLI 授权并从列表移除；删除当前账号时会先自动切换到其他账号。
- 账号列表持久化在本地（UserDefaults），首次使用自动播种已授权账号，可自由增删。

## 环境要求

- macOS 15.0+
- Xcode 26.x
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（生成 Xcode 工程）
- [GitHub CLI](https://cli.github.com/)（`/opt/homebrew/bin/gh`，账号已通过 `gh auth login` 授权）

## 构建与安装

```bash
xcodegen generate        # 由 project.yml 生成 GitSwitch.xcodeproj（工程不入库）
./scripts/build_and_install.sh
```

脚本会构建 Release、验证签名、安装到 `/Applications/GitSwitch.app` 并注册桌面小组件扩展。本机使用 “Sign to Run Locally”，无需付费开发者账号。

安装后在桌面右键 → 编辑小组件 → 搜索 “GitSwitch” 添加。

## 测试

```bash
./scripts/test.sh          # 单元测试（mock 命令，不改动真实账号）
./scripts/test.sh --live   # 真实双向切换测试（会修改 gh 账号与全局 Git 身份，完成后恢复）
```

## 架构概览

- `App/`：主应用（非沙盒）。状态服务仅监听 `127.0.0.1:47831`；`gitswitch://choose` 深链接打开选择窗口；`AuthFlowController` 以无终端方式驱动 `gh auth login --web` 设备码授权。
- `Widget/`：WidgetKit 扩展（沙盒，仅本机网络客户端权限）。只读状态接口并用 `Link` 打开选择窗口，不执行任何切换。
- `Shared/`：账号模型与存储（`AccountStore`）、切换/注销事务（`AccountSwitchingEngine`）、并发串行化协调器（`SwitchCoordinator`）。
- `Tests/`：账号存储、切换/回滚/并发、注销与删除编排、新账号接入及实机双向测试。

安全边界：真实切换只发生在主应用进程；外部命令一律使用固定可执行路径 + 参数数组（`Foundation.Process`），不拼接 shell；只有账号列表内的账号可进入命令参数。

## 安全与隐私

- 应用不读取、不记录、不存储任何 GitHub token；认证凭据始终由 GitHub CLI 与 macOS 钥匙串管理。
- 状态服务只绑定回环地址，返回内容不含凭据。
- 项目开发约定见 `AGENTS.md`。

## 许可证

[MIT](LICENSE) © 2026 Aenvo
