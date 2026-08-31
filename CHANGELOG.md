# 变更记录 / Changelog

本文件记录 GitSwitch 各版本面向用户和贡献者的重要变化。

This file records notable GitSwitch changes for users and contributors.

## 1.3.2 - 待发布 / Unreleased

### 中文

- 新安装从空账号列表开始，不再附带维护者示例账号；已有 `UserDefaults` 数据格式保持兼容。
- 测试夹具改用虚构身份，实机双账号测试改由环境变量提供账号与提交邮箱。
- 补充中英文 README、安全政策、贡献指南以及 Issue / Pull Request 模板。
- 为 shell 脚本固定 LF 行尾，避免跨平台检出破坏 macOS 脚本入口。

### English

- New installations start with an empty account list instead of maintainer sample accounts, while the existing `UserDefaults` data format remains compatible.
- Test fixtures now use fictional identities, and live two-account tests receive account names and commit emails through environment variables.
- Added Chinese and English README entry points, a security policy, a contributing guide, and Issue / Pull Request templates.
- Enforced LF line endings for shell scripts to protect macOS entry points across platforms.
