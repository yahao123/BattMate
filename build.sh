#!/bin/bash
# BattMate 发布打包：swiftc 直编 x2 → lipo 合并 universal → 最小 .app → ad-hoc 签名
# 用法: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --show-sdk-path)"
mkdir -p .build

echo "==> swiftc 编译 x86_64"
swiftc -sdk "$SDK" -target x86_64-apple-macos13 -O \
    $(find Sources -name '*.swift') \
    -o .build/BattMate-x86_64

echo "==> swiftc 交叉编译 arm64"
swiftc -sdk "$SDK" -target arm64-apple-macos13 -O \
    $(find Sources -name '*.swift') \
    -o .build/BattMate-arm64

echo "==> 合并 universal"
lipo -create .build/BattMate-x86_64 .build/BattMate-arm64 -output .build/BattMate

APP="build/BattMate.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/BattMate "$APP/Contents/MacOS/BattMate"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>cn.wangyahao.battmate</string>
    <key>CFBundleName</key><string>BattMate</string>
    <key>CFBundleDisplayName</key><string>BattMate</string>
    <key>CFBundleExecutable</key><string>BattMate</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> ad-hoc 签名"
codesign --force -s - "$APP"

echo "==> 校验"
lipo -archs "$APP/Contents/MacOS/BattMate"
codesign --verify --verbose=1 "$APP"
echo "完成: $APP"
