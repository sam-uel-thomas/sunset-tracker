#!/bin/bash
# Builds Sunset Tracker.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Sunset Tracker.app"

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SunsetBar "$APP/Contents/MacOS/SunsetBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier com.samthomas.sunsettracker "$APP"

echo "Built $APP"
