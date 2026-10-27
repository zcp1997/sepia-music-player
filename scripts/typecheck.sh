#!/bin/bash
# 本机没有 Xcode：借 macOS SDK 自带的 Mac Catalyst 框架，按 iOS 16 把整个 App 编译到 SIL 阶段。
# 能抓到语法/类型错误、iOS 17+ API 误用、变量未初始化等；真正的 iOS 编译和链接仍以 CI 为准。
set -euo pipefail
cd "$(dirname "$0")/.."

# 用和 CI（Xcode 26.x）同代的 SDK；更新的 SDK 里 @State 等是宏，Command Line Tools 缺少对应插件
SDK=${SDK:-$(xcrun --show-sdk-path --sdk macosx26.5 2>/dev/null || xcrun --show-sdk-path)}
find Sepia -name '*.swift' -print0 | xargs -0 swiftc -emit-sil -wmo -module-name Sepia -parse-as-library -swift-version 5 \
  -target arm64-apple-ios16.0-macabi -sdk "$SDK" \
  -Fsystem "$SDK/System/iOSSupport/System/Library/Frameworks" \
  -I "$SDK/System/iOSSupport/usr/lib/swift" \
  -o /dev/null
echo "typecheck OK"
