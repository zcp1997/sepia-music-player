#!/bin/bash
# 把主要界面渲染成 PNG（浅色 / 深色），本机没有 Xcode 也能检查配色和布局。
# 借 macOS 26.5 SDK 里的 Mac Catalyst 框架编译成命令行程序运行；画面由 scripts/previews/main.swift 拼出。
set -euo pipefail
cd "$(dirname "$0")/.."

OUTPUT=${1:-build/previews}
mkdir -p "$OUTPUT"
OUTPUT=$(cd "$OUTPUT" && pwd)
BIN=$(mktemp -d)
trap 'rm -rf "$BIN"' EXIT

SDK=${SDK:-$(xcrun --show-sdk-path --sdk macosx26.5 2>/dev/null || xcrun --show-sdk-path)}
# SepiaApp.swift 里有 @main，预览程序用自己的 main.swift
find Sepia -name '*.swift' ! -name 'SepiaApp.swift' -print0 | xargs -0 swiftc -swift-version 5 \
  -target arm64-apple-ios16.0-macabi -sdk "$SDK" \
  -Fsystem "$SDK/System/iOSSupport/System/Library/Frameworks" \
  -I "$SDK/System/iOSSupport/usr/lib/swift" \
  -L "$SDK/System/iOSSupport/usr/lib/swift" \
  scripts/previews/main.swift -o "$BIN/previews"
"$BIN/previews" "$OUTPUT"
