#!/bin/bash
# Build, sign with a stable local certificate, and run Luminary.
# Why: the Keychain remembers "Always Allow" per code signature. An unsigned debug build gets a new
# signature on every compile, so macOS asks for your password again each time. Signing every build with
# the same certificate makes macOS see it as the same app.
set -euo pipefail
cd "$(dirname "$0")/.."
CERT="Luminary Dev Signing"

if ! security find-certificate -c "$CERT" >/dev/null 2>&1; then
  echo "Creating local code-signing certificate '$CERT' (one time)…"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  cat > "$tmp/c.cnf" <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$CERT
[ext]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
basicConstraints=critical,CA:false
CNF
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$tmp/k.pem" -out "$tmp/c.pem" -config "$tmp/c.cnf" 2>/dev/null
  openssl pkcs12 -export -inkey "$tmp/k.pem" -in "$tmp/c.pem" -out "$tmp/c.p12" -passout pass:luminary -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null
  security import "$tmp/c.p12" -k ~/Library/Keychains/login.keychain-db -P luminary -T /usr/bin/codesign
fi

# Release (optimised) build: SwiftUI in a debug build is several times slower and drops to ~60 fps on the
# poster grid; release holds the display's full 120 Hz. LUMINARY_DEV_STORE keeps the file-based session
# (no Keychain prompts) that debug builds use.
swift build -c release -Xswiftc -DLUMINARY_DEV_STORE
BIN=".build/arm64-apple-macosx/release/Luminary"
codesign --force --sign "$CERT" --identifier dev.luminary.app "$BIN"
exec "$BIN" "$@"
