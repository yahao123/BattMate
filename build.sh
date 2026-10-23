#!/bin/bash
# BattMate 发布打包：swiftc 直编 x2 → lipo 合并 universal → 最小 .app + Widget 扩展 → ad-hoc 签名
# 用法: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --show-sdk-path)"
mkdir -p .build

APP_SOURCES=$(find Sources -name '*.swift' ! -path 'Sources/BattMateWidget/*')
WIDGET_SOURCES="Sources/BattMateCore/WidgetSnapshot.swift $(find Sources/BattMateWidget -name '*.swift')"

echo "==> swiftc 编译主 App x86_64"
swiftc -sdk "$SDK" -target x86_64-apple-macos13 -O \
    $APP_SOURCES \
    -o .build/BattMate-x86_64

echo "==> swiftc 交叉编译主 App arm64"
swiftc -sdk "$SDK" -target arm64-apple-macos13 -O \
    $APP_SOURCES \
    -o .build/BattMate-arm64

echo "==> 合并主 App universal"
lipo -create .build/BattMate-x86_64 .build/BattMate-arm64 -output .build/BattMate

# Widget 扩展必须像 Xcode 的 app-extension 产物一样以 NSExtensionMain 为入口，
# 否则 WidgetBundle.main() 会立即返回、进程退出，chronod 拿不到 descriptors。
echo "==> swiftc 编译 Widget 扩展 x86_64"
swiftc -sdk "$SDK" -target x86_64-apple-macos14 -O -parse-as-library \
    -Xlinker -e -Xlinker _NSExtensionMain \
    $WIDGET_SOURCES \
    -o .build/BattMateWidget-x86_64

echo "==> swiftc 交叉编译 Widget 扩展 arm64"
swiftc -sdk "$SDK" -target arm64-apple-macos14 -O -parse-as-library \
    -Xlinker -e -Xlinker _NSExtensionMain \
    $WIDGET_SOURCES \
    -o .build/BattMateWidget-arm64

echo "==> 合并 Widget universal"
lipo -create .build/BattMateWidget-x86_64 .build/BattMateWidget-arm64 -output .build/BattMateWidget

APP="build/BattMate.app"
APPEX="$APP/Contents/PlugIns/BattMateWidget.appex"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APPEX/Contents/MacOS"
cp .build/BattMate "$APP/Contents/MacOS/BattMate"
cp .build/BattMateWidget "$APPEX/Contents/MacOS/BattMateWidget"

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
    <key>CFBundleShortVersionString</key><string>1.1.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

cat > "$APPEX/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>cn.wangyahao.battmate.widget</string>
    <key>CFBundleName</key><string>BattMateWidget</string>
    <key>CFBundleDisplayName</key><string>BattMate</string>
    <key>CFBundleExecutable</key><string>BattMateWidget</string>
    <key>CFBundlePackageType</key><string>XPC!</string>
    <key>CFBundleShortVersionString</key><string>1.1.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
PLIST

echo "==> ad-hoc 签名 Widget 扩展"
codesign --force -s - \
    --entitlements Resources/BattMateWidget.entitlements \
    "$APPEX"

echo "==> ad-hoc 签名主 App"
codesign --force -s - "$APP"

echo "==> 校验"
lipo -archs "$APP/Contents/MacOS/BattMate"
lipo -archs "$APPEX/Contents/MacOS/BattMateWidget"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements :- "$APPEX" 2>/dev/null
echo "完成: $APP"
