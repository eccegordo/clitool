#!/bin/bash
# Builds CLITool and packages it as build/CLITool.app
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/CLITool.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$(swift build -c release --show-bin-path)/CLITool" "$APP/Contents/MacOS/CLITool"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
