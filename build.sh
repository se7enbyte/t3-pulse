#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/build/T3 Pulse.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc Sources/main.swift -O -target "$(uname -m)-apple-macosx14.0" -o "$APP/Contents/MacOS/T3Pulse" -framework AppKit -framework SwiftUI -lsqlite3
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "$APP"
