#!/bin/bash
# 打包可分发的通用版（Apple 芯片 + Intel）：dist/TypingCat-<版本>.zip
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
UNIVERSAL=1 ./scripts/build_app.sh

mkdir -p dist
ZIP="dist/TypingCat-${VERSION}.zip"
rm -f "$ZIP"
# 用 ditto 打包，保留签名和扩展属性
ditto -c -k --keepParent build/TypingCat.app "$ZIP"
echo "架构：$(lipo -archs build/TypingCat.app/Contents/MacOS/TypingCat)"
echo "🎁 $ZIP ($(du -h "$ZIP" | cut -f1))"
