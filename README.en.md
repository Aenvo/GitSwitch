# GitSwitch

[简体中文](README.md) | English

GitSwitch is a macOS desktop widget for switching between multiple GitHub CLI accounts while keeping the global Git commit identity in sync. It is intended for developers who use personal, work, or open-source accounts on the same Mac.

> GitSwitch is an independent open-source project and is not an official GitHub product. It changes the active GitHub CLI account and the global `git config user.name` / `user.email` values for the current macOS user.

## Getting started

### Requirements

- macOS 15.0 or later
- [GitHub CLI](https://cli.github.com/) (`gh`)

GitSwitch selects the first executable `gh` found at `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, or `/opt/local/bin`. It uses the system Git executable at `/usr/bin/git`.

### Download and install

1. Download `GitSwitch-<version>.app.zip` and its matching `.sha256` file from [Releases](https://github.com/Aenvo/GitSwitch/releases/latest).
2. Verify the download in the directory containing both files:

   ```bash
   shasum -a 256 -c GitSwitch-*.app.zip.sha256
   ```

3. Extract the archive and move `GitSwitch.app` to `/Applications`.
4. If macOS cannot verify the developer on first launch, right-click GitSwitch in Applications, choose **Open**, and confirm again.

Release builds use ad-hoc signing without debugger-attachment entitlement and are not notarized by Apple. Only use packages from this repository's Releases page after their SHA-256 check succeeds.

### First-time setup

1. If GitHub CLI is not installed, run `brew install gh`.
2. Right-click an empty area of the desktop, choose **Edit Widgets**, search for **GitSwitch**, and add the widget.
3. Select **Switch current account** in the widget, then choose **Add account** in the upper-right corner.
4. GitSwitch displays a one-time device code and opens a browser. Complete authorization on GitHub, confirm the Git commit email, and save.
5. Repeat the process for additional accounts. To switch later, select an account and confirm the choice.

New installations start without sample accounts. When upgrading, an account list already stored in `UserDefaults` keeps the same data format and remains available.

## Features

- Show the current GitHub account and Git commit identity in a desktop widget
- Add accounts through the GitHub CLI device-code flow without entering a password or token in the app
- Switch the active `gh` account and update the global Git user name and email together
- Edit the Git commit identity associated with each account and restore its initial values
- Require confirmation before removal and try to switch away before removing the active account
- Restore the original GitHub account and global Git identity when a switch fails
- Show locally cached status when GitHub is temporarily unreachable while keeping the account chooser available

## Security and privacy boundaries

- GitHub credentials are managed by GitHub CLI and the macOS Keychain. GitSwitch does not read, log, or persist GitHub tokens.
- The main app is not sandboxed so it can invoke `gh` and update the global Git configuration. Keychain credentials remain accessed and managed by `gh`.
- The Widget Extension stays sandboxed. It only reads status through `GET http://127.0.0.1:47831/v1/status` and opens the main app through `gitswitch://choose`.
- The local status service binds only to `127.0.0.1:47831`, exposes no account-switching write endpoint, and never returns tokens.
- Removing an account runs `gh auth logout --hostname github.com --user <account>`, which signs that account out of GitHub CLI on the local Mac.

GitSwitch is not a per-repository identity switcher: every switch affects the current macOS user's global Git configuration. Confirm the target account and commit email before switching or removing an account.

## Build from source

Building requires Xcode 26 or later, XcodeGen, and GitHub CLI:

```bash
git clone https://github.com/Aenvo/GitSwitch.git
cd GitSwitch
brew install xcodegen gh
./scripts/build_and_install.sh
```

The script generates the Xcode project from `project.yml`, builds the Release configuration, installs the app at `/Applications/GitSwitch.app`, registers the widget, and launches the app. `GitSwitch.xcodeproj` is generated and is not committed.

## Testing

Run the regular unit tests with:

```bash
./scripts/test.sh
```

The live two-account test changes the real GitHub CLI account and global Git identity. Run it only after both accounts are authorized with `gh` and the original state has been recorded:

```bash
export GITSWITCH_LIVE_ACCOUNT_1_LOGIN="<account-one>"
export GITSWITCH_LIVE_ACCOUNT_1_EMAIL="<account-one-commit-email>"
export GITSWITCH_LIVE_ACCOUNT_2_LOGIN="<account-two>"
export GITSWITCH_LIVE_ACCOUNT_2_EMAIL="<account-two-commit-email>"
./scripts/test.sh --live
```

The test attempts to restore the original account and Git identity. Whether it passes or fails, manually verify `gh api user --jq .login`, `git config --global user.name`, and `git config --global user.email` afterward.

## Architecture

- `App/`: non-sandboxed main app, first-run setup, account management, device-code authorization, and loopback status service
- `Widget/`: sandboxed WidgetKit extension that only reads local status and opens the account chooser
- `Shared/`: account storage, toolchain discovery, switch and rollback transactions, and concurrency coordination
- `Tests/`: storage, status parsing, offline behavior, switching, rollback, removal, and live tests
- `project.yml`: source of truth for XcodeGen targets, versions, and signing settings

## Contributing

- [Contributing guide](CONTRIBUTING.md): development setup, verification requirements, and change boundaries
- [Security policy](SECURITY.md): how to report security issues privately and what information to include
- [Changelog](CHANGELOG.md): notable changes in released and upcoming versions

## License

[MIT](LICENSE) © 2026 Aenvo
