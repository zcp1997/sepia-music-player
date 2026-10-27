#!/bin/bash
# 把 Sepia/Core 和 Tests/CoreTests 编译成命令行程序并运行（不依赖 SwiftPM / XCTest，本机和 CI 通用）
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
find Sepia/Core Tests/CoreTests -name '*.swift' -print0 | xargs -0 swiftc -swift-version 5 -o "$OUT/core-tests"
"$OUT/core-tests"
