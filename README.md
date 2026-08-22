# GitSwitch

macOS 桌面小组件：在多个 GitHub 账号之间一键切换，自动同步 Git 提交身份。新增账号在应用内完成 GitHub 官方授权，删除账号有二次确认，全程不接触你的 GitHub 令牌。

## 它能做什么

- **桌面小组件**常驻显示当前 GitHub 账号，点“切换当前账号”弹出选择窗口
- **切换账号**：勾选目标账号 → 确定，自动完成 GitHub CLI 账号切换 + 全局 `user.name` / `user.email` 同步，失败自动回滚
- **新增账号**：填用户名和邮箱 → 应用内展示一次性代码 → 浏览器完成 GitHub 授权 → 保存
- **删除账号**：垃圾桶图标 → 二次确认 → 注销本机授权并移除

## 系统要求

- macOS 15.0 或更高
- [GitHub CLI](https://cli.github.com/)（`gh`），通过 Homebrew 安装：`brew install gh`

> 应用会自动探测 `gh` 的常见安装路径（`/opt/homebrew/bin`、`/usr/local/bin`、`/usr/bin`、`/opt/local/bin`），Intel 和 Apple Silicon 的 Mac 都支持。

## 安装

### 方式一：下载安装包（最简单）

1. 打开 [Releases 页面](../../releases)，下载最新的 `GitSwitch-x.x.app.zip`
2. 解压，把 `GitSwitch.app` 拖入「应用程序」文件夹（`/Applications`）
3. 首次打开遇到“无法验证开发者”提示？这是因为它没有付费开发者签名。两种解决办法任选其一：
   - 在「应用程序」里**右键** GitSwitch →「打开」→ 再点「打开」
   - 或打开「终端」执行：`xattr -cr /Applications/GitSwitch.app`，然后正常双击打开
4. 安装 GitHub CLI：`brew install gh`（还没装 [Homebrew](https://brew.sh) 的话先装它）

### 方式二：从源码构建（免 Gatekeeper 提示，推荐长期使用）

需要 Xcode 26+ 和 XcodeGen：

```bash
git clone https://github.com/Aenvo/GitSwitch.git   # 不会用 git？在仓库页点绿色 Code 按钮选 Download ZIP，解压后进入文件夹即可
cd GitSwitch
brew install xcodegen gh
./scripts/build_and_install.sh
```

脚本会自动构建、安装到「应用程序」、注册小组件并启动应用。本地构建在本机签名，不会有任何拦截提示。

## 安装后的三步设置

1. **添加小组件**：在桌面空白处右键 →「编辑小组件」→ 搜索 **GitSwitch** → 添加
2. **添加你的 GitHub 账号**：点小组件上的「切换当前账号」→ 右上角「新增账号」→ 填写用户名和邮箱（邮箱可留空，自动用 GitHub 隐私邮箱）→「开始授权」→ 在浏览器输入应用内显示的一次性代码（可一键复制）→ 授权完成自动保存
3. 多个账号重复第 2 步即可；以后在小组件里勾选 →「确定」就能切换

> 首次启动时，如果应用检测到示例账号在你的机器上都没有授权，会自动清空账号列表——直接「新增账号」添加你自己的就行。

## 常见问题

- **打开应用被拦**：见「方式一」第 3 步
- **设置检查显示“GitHub CLI 未找到”**：先 `brew install gh`，装好后点「重新检查」
- **小组件显示“暂时不可用”**：说明后台主应用没在运行，打开一次 `/Applications/GitSwitch.app` 即可（它无 Dock 图标，在后台常驻，可设为登录项）
- **想开机自启**：应用首次启动的检查窗口里点「启用后台运行」，或在 系统设置 → 通用 → 登录项 里确认
- **它会碰我的 GitHub 密码或令牌吗**：不会。授权由 GitHub 官方 CLI 和 macOS 钥匙串完成，本应用不读取、不存储、不上传任何凭据；状态服务只监听本机回环地址

## 从源码构建与测试（开发者）

```bash
xcodegen generate        # 由 project.yml 生成 GitSwitch.xcodeproj（工程不入库）
./scripts/test.sh        # 单元测试
./scripts/test.sh --live # 真实双向切换测试（会修改 gh 账号与全局 Git 身份，结束后恢复）
```

## 架构概览

- `App/`：主应用（非沙盒）。状态服务仅监听 `127.0.0.1:47831`；`gitswitch://choose` 深链接打开选择窗口；`AuthFlowController` 以无终端方式驱动 `gh auth login --web` 设备码授权
- `Widget/`：WidgetKit 扩展（沙盒，仅本机网络客户端权限）。只读状态并用 `Link` 打开选择窗口，不执行切换
- `Shared/`：账号模型与存储（`AccountStore`）、工具链路径探测（`Toolchain`）、切换/注销事务（`AccountSwitchingEngine`）、并发串行化（`SwitchCoordinator`）
- `Tests/`：账号存储、切换/回滚/并发、注销与删除编排、新账号接入、播种对账及实机双向测试

外部命令一律使用固定候选路径 + 参数数组（`Foundation.Process`），不拼接 shell；只有账号列表内的账号可进入命令参数。项目开发约定见 [AGENTS.md](AGENTS.md)。

## 安全与隐私

- 应用不读取、不记录、不存储任何 GitHub token；认证凭据始终由 GitHub CLI 与 macOS 钥匙串管理
- 状态服务只绑定回环地址，返回内容不含凭据

## 许可证

[MIT](LICENSE) © 2026 Aenvo
