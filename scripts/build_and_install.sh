#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
derived_dir="$project_dir/build/ReleaseSigned"
app_name="GitSwitch.app"
source_app="$derived_dir/Build/Products/Release/$app_name"
installed_app="/Applications/$app_name"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$project_dir"

xcodegen generate
xcodebuild \
  -project GitSwitch.xcodeproj \
  -scheme GitSwitch \
  -configuration Release \
  -derivedDataPath "$derived_dir" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  build

codesign --verify --deep --strict "$source_app"
pkill -x "GitSwitch" 2>/dev/null || true
/usr/bin/ditto "$source_app" "$installed_app"
codesign --verify --deep --strict "$installed_app"
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$installed_app"
pluginkit -a "$installed_app/Contents/PlugIns/GitSwitchWidget.appex"
pluginkit -e use -i com.aenvo.GitSwitch.widget
open "$installed_app"

echo "已安装：$installed_app"
