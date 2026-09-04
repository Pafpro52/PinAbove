#!/bin/sh
set -eu

cd "$(dirname "$0")"
destination="${1:-dist}"
app="$destination/PinAbove.app"
binary="$app/Contents/MacOS/PinAbove"
identity="${DEVELOPER_ID_APPLICATION:--}"

mkdir -p "$app/Contents/MacOS" .build/module-cache
xcrun swiftc -target arm64-apple-macos13.0 -O -module-cache-path .build/module-cache \
  -framework AppKit -framework Carbon main.swift -o "$binary"
cp Info.plist "$app/Contents/Info.plist"

if [ "$identity" = "-" ]; then
  codesign --force --options runtime --sign - "$app"
else
  codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi

"$binary" --self-test
ditto -c -k --sequesterRsrc --keepParent "$app" "$destination/PinAbove.zip"
codesign --verify --deep --strict "$app"
