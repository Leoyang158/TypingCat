#!/bin/bash
# 生成一个本地自签名代码签名证书「TypingCat Dev」并导入登录钥匙串（只需运行一次）
set -euo pipefail
NAME="TypingCat Dev"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "证书已存在"; exit 0
fi
TMP=$(mktemp -d)
cat > "$TMP/cfg" <<CFG
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
basicConstraints=critical,CA:false
CFG
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cfg" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
LEGACY=""; openssl version | grep -q "^OpenSSL 3" && LEGACY="-legacy"
openssl pkcs12 -export $LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:typingcat -name "$NAME"
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db \
    -P typingcat -T /usr/bin/codesign
rm -rf "$TMP"
# 清掉旧（临时签名）版本留下的失效授权记录，只影响 TypingCat
tccutil reset ListenEvent com.local.TypingCat >/dev/null 2>&1 || true
tccutil reset Accessibility com.local.TypingCat >/dev/null 2>&1 || true
echo "✅ 已创建证书「${NAME}」。之后运行 scripts/build_app.sh 会自动使用它。"
