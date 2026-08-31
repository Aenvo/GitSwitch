#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
live=0
if [ "${1:-}" = "--live" ]; then live=1; fi

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$project_dir"
xcodegen generate
xcodebuild \
  -project GitSwitch.xcodeproj \
  -scheme GitSwitch \
  -configuration Debug \
  -derivedDataPath "$project_dir/build/Tests" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  build-for-testing

test_bundle="$project_dir/build/Tests/Build/Products/Debug/GitSwitchTests.xctest"
if [ "$live" -eq 1 ]; then
  : "${GITSWITCH_LIVE_ACCOUNT_1_LOGIN:?Set GITSWITCH_LIVE_ACCOUNT_1_LOGIN before --live}"
  : "${GITSWITCH_LIVE_ACCOUNT_1_EMAIL:?Set GITSWITCH_LIVE_ACCOUNT_1_EMAIL before --live}"
  : "${GITSWITCH_LIVE_ACCOUNT_2_LOGIN:?Set GITSWITCH_LIVE_ACCOUNT_2_LOGIN before --live}"
  : "${GITSWITCH_LIVE_ACCOUNT_2_EMAIL:?Set GITSWITCH_LIVE_ACCOUNT_2_EMAIL before --live}"
  RUN_LIVE_SWITCH_TESTS=1 xcrun xctest "$test_bundle"
else
  xcrun xctest "$test_bundle"
fi
