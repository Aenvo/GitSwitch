# GitSwitch

简体中文 | [English](README.en.md)

GitSwitch 是一款 macOS 桌面小组件，用来在多个 GitHub CLI 账号之间切换，并同步全局 Git 提交身份。它适合在同一台 Mac 上维护个人、工作或开源账号的开发者。

> GitSwitch 是第三方开源工具，不属于 GitHub 官方产品。应用会修改当前 Mac 的 GitHub CLI 活跃账号以及全局 `git config user.name` / `user.email`。

## 开始使用

### 系统要求

- macOS 15.0 或更高版本
- [GitHub CLI](https://cli.github.com/)（`gh`）

GitSwitch 会从 `/opt/homebrew/bin`、`/usr/local/bin`、`/usr/bin` 和 `/opt/local/bin` 中选择第一个可执行的 `gh`；Git 固定使用系统自带的 `/usr/bin/git`。

### 下载安装

1. 从 [Releases](https://github.com/Aenvo/GitSwitch/releases/latest) 下载 `GitSwitch-<版本>.app.zip` 和对应的 `.sha256` 文件。
2. 在下载目录校验文件：

   ```bash
   shasum -a 256 -c GitSwitch-*.app.zip.sha256
   ```

3. 解压后把 `GitSwitch.app` 拖入 `/Applications`。
4. 首次启动时如果 macOS 提示无法验证开发者，在「应用程序」中右键 GitSwitch，选择「打开」并再次确认。

Release 中的应用使用 ad-hoc 签名，没有经过 Apple 公证。请只使用本仓库 Release 页面提供且 SHA-256 校验通过的文件。

### 首次设置

1. 如果尚未安装 GitHub CLI，运行 `brew install gh`。
2. 在桌面空白处右键，选择「编辑小组件」，搜索 **GitSwitch** 并添加小组件。
3. 点击小组件上的「切换当前账号」，再点击右上角的「新增账号」。
4. GitSwitch 会显示一次性设备码并打开浏览器；在 GitHub 完成授权后，确认 Git 提交邮箱并保存。
5. 重复新增其他账号。以后选择目标账号并点击「确定」即可切换。

新安装不会附带示例账号。升级已有版本时，保存在 `UserDefaults` 中的账号列表会继续保留。

## 主要能力

- 在桌面小组件中显示当前 GitHub 账号和 Git 提交身份
- 通过 GitHub CLI 的设备码流程新增账号，不要求在应用中输入密码或令牌
- 切换 `gh` 活跃账号，同时更新全局 Git 用户名和邮箱
- 编辑每个账号对应的 Git 提交身份，并可还原初始配置
- 删除账号前二次确认；删除当前账号时先尝试切换到其他账号
- 切换失败时恢复原 GitHub 账号和全局 Git 身份
- GitHub 暂时不可达时显示本地缓存状态，仍可打开账号选择窗口

## 安全与隐私边界

- GitHub 凭据由 GitHub CLI 和 macOS 钥匙串管理；GitSwitch 不读取、记录或持久化 GitHub token。
- 主应用为非沙盒应用，以便调用 `gh` 并修改全局 Git 配置；钥匙串凭据仍由 `gh` 访问和管理。
- Widget Extension 保持沙盒化，只访问 `http://127.0.0.1:47831/v1/status` 并通过 `gitswitch://choose` 打开主应用。
- 本地状态服务只绑定 `127.0.0.1:47831`，响应不包含 token。
- 删除账号会执行 `gh auth logout --hostname github.com --user <账号>`，从本机 GitHub CLI 中注销该账号。

这意味着 GitSwitch 不是项目级身份切换器：一次切换会影响当前 macOS 用户的全局 Git 配置。切换或删除前，请确认目标账号和提交邮箱。

## 从源码构建

需要 Xcode 26 或更高版本、XcodeGen 和 GitHub CLI：

```bash
git clone https://github.com/Aenvo/GitSwitch.git
cd GitSwitch
brew install xcodegen gh
./scripts/build_and_install.sh
```

脚本会用 `project.yml` 生成 Xcode 工程，构建 Release 配置，把应用安装到 `/Applications/GitSwitch.app`，注册小组件并启动应用。`GitSwitch.xcodeproj` 是生成文件，不提交到仓库。

## 测试

普通单元测试：

```bash
./scripts/test.sh
```

实机双账号测试会真实切换 GitHub CLI 账号和全局 Git 身份，只应在两个账号均已通过 `gh` 授权、且已记录当前状态时运行：

```bash
export GITSWITCH_LIVE_ACCOUNT_1_LOGIN="<account-one>"
export GITSWITCH_LIVE_ACCOUNT_1_EMAIL="<account-one-commit-email>"
export GITSWITCH_LIVE_ACCOUNT_2_LOGIN="<account-two>"
export GITSWITCH_LIVE_ACCOUNT_2_EMAIL="<account-two-commit-email>"
./scripts/test.sh --live
```

测试会尝试恢复原账号与 Git 身份；无论测试是否成功，都应在结束后手动核对 `gh api user --jq .login`、`git config --global user.name` 和 `git config --global user.email`。

## 架构

- `App/`：非沙盒主应用、首次设置、账号管理、设备码授权和回环状态服务
- `Widget/`：沙盒化 WidgetKit 扩展，只读取本机状态并打开账号选择窗口
- `Shared/`：账号存储、工具链探测、切换与回滚事务、并发协调
- `Tests/`：存储、状态解析、离线行为、切换、回滚、删除和实机测试
- `project.yml`：XcodeGen 工程、版本、签名和 target 配置的来源

## 参与项目

- [贡献指南](CONTRIBUTING.md)：开发环境、验证要求和提交边界
- [安全政策](SECURITY.md)：私密报告安全问题的方法和信息要求
- [变更记录](CHANGELOG.md)：已发布与待发布版本的主要变化

## 许可证

[MIT](LICENSE) © 2026 Aenvo
