# AGENTS.md

本文件适用于当前目录及其所有子目录。后续 agent 在修改、测试、安装或交付本项目时必须遵守以下约定。

## 开始工作前

1. 先阅读 `README.md`、`project.yml` 以及本次任务涉及的 Swift 文件。
2. 使用只读命令核对当前运行状态、已安装应用和 GitHub/Git 身份；不要假设旧交接信息始终有效。
3. 检查当前目录是否已经初始化为 Git 仓库，并保护任何已有用户改动。当前交接时该目录尚无 `.git`。
4. `project.yml` 是 Xcode 工程配置的主要源。`GitSwitch.xcodeproj` 由 XcodeGen 生成，不要只修改生成后的工程文件而遗漏 `project.yml`。App/Widget 的 `CFBundleShortVersionString`/`CFBundleVersion` 以 `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)` 变量形式定义在 `project.yml` 的 info properties 中：改版本只改 settings 里的这两个值，不要手改 Info.plist（会被 xcodegen 每次生成时重写）。

## 架构边界

- Widget Extension 只读取 `http://127.0.0.1:47831/v1/status` 并通过 `gitswitch://choose` 打开账号选择窗口。
- Widget 不直接运行 `gh`、不修改 Git 配置，也不负责执行真实账号切换。
- 账号切换必须在主应用进程中通过 `SwitchCoordinator` 和 `AccountSwitchingEngine` 执行。
- 主应用保持非沙盒，以访问 GitHub CLI、钥匙串凭据和全局 Git 配置；Widget 保持沙盒化，并仅保留本机网络客户端权限。
- 状态服务必须只绑定 `127.0.0.1:47831`，不得监听局域网或公网地址，接口不得返回 token。
- 状态读取与网络解耦（v1.2 起）：`GET /v1/status` 缓存优先、立即返回；账号来自 `gh auth status` 本地解析，调用时故意注入死代理环境（`AccountSwitchingEngine.localOnlyProxyEnvironment`）让 gh 的联网校验瞬间失败，账号读取不受网络影响（实测 8 秒超时 → 0.1 秒）；GitHub 可达性由 `remoteLogin` 在后台单独探测（30 秒节流），不可达时降级为 `offlineCached`（账号照常显示、灰点提示），绝不整卡不可用。删除或绕过死代理环境会使弱网下账号读取重新被网络拖住。
- `SwitcherState` 包含 `ready`/`switching`/`error`/`offline`/`offlineCached`；`offline` 仅表示主应用未运行。auth status 输出为空（超时）时可用缓存兜底，但输出非空且无账号（全部注销）是真实状态，不得被缓存遮蔽。
- 外部命令执行支持超时与环境变量覆盖（`CommandRunning.run(timeout:environment:)`），防止 gh 卡死拖住串行队列。
- 保持 `SwitchCoordinator` 的串行化语义，不能让两个切换事务并发执行。
- 切换必须保存原状态、执行 `gh auth switch` 与 `gh auth setup-git`、同步全局 Git 身份、完整验证，并在失败时回滚到实际原状态。
- 账号列表是动态配置：`AccountStore`（UserDefaults 键 `GitSwitchAccounts`）持久化用户管理的账号，首次使用播种 `Aenvo` 与 `hubot` 两个默认账号；播种只在键不存在时发生，删除账号后不得自动恢复。首次启动时若列表仍是播种且没有任何账号在 gh 中授权（`SeededAccountReconciler`），自动清空列表引导用户新增自己的账号。
- 新增账号走 GitHub 设备码授权：`AuthFlowController` 以无终端方式运行 `gh auth login --web`，解析 stderr 中的一次性码与授权 URL 展示给用户；授权成功后以 `gh api user` 的实际登录名为准（与表单输入不一致时按授权结果保存），并自动派生 noreply 邮箱。授权完成后经 `SwitchCoordinator.adoptNewAccount` 同步 Git 身份并写入账号列表。
- 删除账号必须先在 UI 二次确认，再经 `SwitchCoordinator.removeAccount` 执行；删除当前账号时会先切换到列表中的其他账号，切换失败则中止删除。

## 命令与安全

- gh 路径由 `Shared/Toolchain.swift` 在进程启动时按候选顺序探测（`/opt/homebrew/bin`、`/usr/local/bin`、`/usr/bin`、`/opt/local/bin`，取第一个可执行）；git 固定 `/usr/bin/git`。不要引入候选列表之外的查找方式。
- 使用 Foundation `Process` 和参数数组调用外部命令；不得拼接 shell 命令或把账号值插入 shell 字符串。
- 只允许 `AccountStore` 列表中的账号进入切换/注销命令；账号名以 `gh api user` 的实际登录名为准。表单输入的用户名和邮箱同样只通过参数数组传递。
- 不读取、输出、保存、提交或写入文档任何 GitHub token、OAuth 凭据或钥匙串秘密。
- 不在日志或测试快照中保留完整 `gh auth status` 认证信息。
- 未经用户明确要求，不更改：
  - `AccountStore` 的默认播种账号（`Aenvo`、`hubot`）及其 noreply 邮箱；
  - Bundle Identifier；
  - `gitswitch` URL Scheme；
  - `47831` 端口；
  - 登录项策略；
  - 主应用与 Widget 的沙盒边界；
  - `/Applications/GitSwitch.app` 安装位置。
- 不删除桌面的备用切号脚本或其他用户文件。

## UI 与交互基线

- Widget 仅支持 `systemSmall`。
- 顶部标题为“GitHub”，中部用户名维持当前 rounded `title2` semibold 样式，单行尾部省略。
- 底部按钮固定为“切换当前账号”，维持半透明胶囊样式。
- 点击 Widget 按钮必须打开账号选择窗口，不能直接切换，也不能回退到需要参数消歧的 App Intent。
- 选择窗口列出账号列表（可滚动），支持明确勾选，并在右下角提供“取消”和“确定”。
- 只有点击“确定”才执行切换；切换中禁用重复操作；失败时保留窗口并显示简短错误。
- 右上角“新增账号”直接进入设备码授权面板（无需填写用户名/邮箱；账号名以 `gh api user` 实际结果为准，邮箱自动派生 noreply 并可在保存前修改）。授权进度在窗口内展示（设备码旁提供“复制”按钮），授权结果确认后保存。
- 账号行悬浮显示“编辑”与“删除”图标（默认不占布局空间，“当前”标记贴行尾，按钮出现时向左挤压）。行标题显示该账号生效的 Git 用户名（未自定义时即登录名），副标题显示邮箱；桌面小组件与设置窗口同样显示生效的 Git 用户名。编辑面板可修改 Git 用户名（user.name）与邮箱（user.email），并提供“还原默认配置”（用户名还原为登录名、邮箱还原为创建时的默认邮箱）；编辑当前账号立即写入全局 git 配置，非当前账号仅保存待切换时生效。保存后条目立即更新并显示绿色提示（区分“已写入全局配置”与“切换时生效”）；新增/编辑表单关闭后兜底刷新列表与状态。
- 每行账号提供删除入口，必须经过二次确认弹窗；删除当前账号会先自动切换到其他账号。
- 切换完成后调用 `WidgetCenter.reloadAllTimelines()` 刷新状态；后台验证导致可见状态变化时也会刷新。
- GitHub 暂时不可达时小组件显示“离线缓存”：账号名照常、圆点变灰、副文案“GitHub 暂时不可达”，按钮仍可打开选择窗口；不得回退为整卡“暂时不可用”。

## 测试要求

普通源码改动至少运行：

```bash
./scripts/test.sh
```

涉及账号切换事务、命令参数、验证或回滚逻辑时，还应运行：

```bash
./scripts/test.sh --live
```

实时测试会修改真实 `gh` 账号和全局 Git 身份。运行前记录原账号、`user.name` 与 `user.email`，运行后必须验证三者均恢复。若测试失败，也要读取实际状态并安全恢复，不能只依据内存中的预期值。

测试至少覆盖：

- 账号模型与 noreply 邮箱生成、`AccountStore` 播种/新增/删除持久化（删除后不复活）；
- 成功切换及最终验证；
- 各步骤失败后的完整回滚；
- 并发请求只执行一个切换事务；
- 注销命令参数（`gh auth logout --user`）；
- 删除非当前账号不触发切换；删除当前账号先切换再注销；
- 新账号接入（身份同步 + 写入列表）；
- 状态接口的正常、切换中、错误、离线及非法请求；
- 状态服务仅绑定回环地址；
- UI 选择、取消、确定、切换中和失败反馈；
- `Aenvo ↔ hubot` 双向实机切换及恢复。

## 构建、安装与验收

涉及部署时运行：

```bash
./scripts/build_and_install.sh
```

随后核对：

```bash
/usr/bin/codesign --verify --deep --strict --verbose=2 '/Applications/GitSwitch.app'
/usr/bin/curl -fsS http://127.0.0.1:47831/v1/status
/opt/homebrew/bin/gh api user --jq .login
/usr/bin/git config --global user.name
/usr/bin/git config --global user.email
```

若修改 Widget 或选择窗口，必须在已安装的 `/Applications` 版本上做实机 UI 验收，而不只验证开发目录的构建产物。确认 Widget Extension 已注册、按钮能打开窗口、勾选状态正确、“确定”会真实切换并刷新 Widget。

## 仓库与交付

- `.gitignore` 已就绪（2026-08-22）：忽略 `build/`、DerivedData、`*.xcodeproj`（XcodeGen 生成物，克隆后运行 `xcodegen generate` 重建）、Xcode 用户态数据、`.app`/压缩包与证书文件；不要提交本机构建产物。
- 许可证为 MIT（`LICENSE`，© 2026 Aenvo）；更换许可证需用户确认。
- Git 仓库已建立：私有仓库 `Aenvo/GitSwitch`（https://github.com/Aenvo/GitSwitch，2026-08-22 创建并推送）。agent 发起的提交、推送、更改仓库设置仍需用户明确授权。
- CI（`.github/workflows/ci.yml`）：push 到 main 或 PR 时在 macOS runner 上运行单元测试，注意私有仓库 macOS runner 按 10 倍计费，保持触发克制。
- Release（`.github/workflows/release.yml`）：推送 `v*` 标签或手动 workflow_dispatch 触发；版本号取自 `project.yml` 的 `MARKETING_VERSION`，产物为 ad-hoc 签名的 `GitSwitch-<版本>.app.zip` 与 `.sha256`。本机安装仍以 `scripts/build_and_install.sh` 为准。
- 敏感信息审计已完成（2026-08-22）：未发现 token、私钥、密码或绝对路径；个人 noreply 邮箱仅存在于 `Shared/AccountStore.swift` 的默认播种和 `Tests/AccountSwitchingEngineTests.swift` 的测试夹具（私有仓库可接受）。Widget 占位符已改为中性示例。若未来公开仓库：需把播种改为空列表加首次引导、测试夹具改用虚构数据，并复查交付文档。
- 交付新应用包时，从已验证的 `/Applications` 安装版本生成压缩包，并同步更新源码包和交接说明。

## 重命名记录（2026-08-22 已完成）

项目已由 `GitHubAccountSwitcher`（GitHub账号切换器）正式更名为 `GitSwitch`，并在同一变更中同步了：目录名、XcodeGen 工程与 scheme、target/module/产品名（`GitSwitch`、`GitSwitchWidget`、`GitSwitchTests`）、Bundle Identifier（`com.aenvo.GitSwitch` / `com.aenvo.GitSwitch.widget` / `com.aenvo.GitSwitchTests`）、URL Scheme（`gitswitch://choose`）、Widget kind（`GitSwitchWidget`）与显示名、脚本中的进程名/应用名/插件名/安装路径、README 与交付文档。

旧应用 `/Applications/GitHub账号切换器.app` 已先注销登录项再移除，未与新应用重复注册。回滚方法：解压 `outputs/GitHub账号切换器-1.0.app.zip` 到 `/Applications`，启动一次以重新注册登录项，并在桌面重新添加旧小组件。
