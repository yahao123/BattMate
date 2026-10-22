#!/bin/bash
# BattMate 单元测试：swiftc 直编 Core+Tests 并运行（失败退出码 1）
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --show-sdk-path)"
TARGET="x86_64-apple-macos13"
mkdir -p .build

swiftc \
    -sdk "$SDK" \
    -target "$TARGET" \
    $(find Sources/BattMateCore Tests -name '*.swift' 2>/dev/null) \
    -o .build/battmate-tests

.build/battmate-tests
