#!/bin/bash
# 编译并打包成 TypingCat.app（输出到 build/）
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="TypingCat Dev"
APP="build/TypingCat.app"

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TypingCat "$APP/Contents/MacOS/TypingCat"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# 没有固定证书就自动生成一个（只会发生一次）
if ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    ./scripts/make_cert.sh || true
fi

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" "$APP"
    echo "✅ 已用固定证书「${IDENTITY}」签名（输入监控权限在重新构建后会保留）"
else
    codesign --force --sign - "$APP"
    echo "⚠️  使用临时签名：每次重新构建后可能需要重新授权输入监控。"
    echo "   运行 scripts/make_cert.sh 一次即可解决。"
fi
codesign -dv "$APP" 2>&1 | grep -E "Authority|Signature=" || true
echo "📦 $APP"
