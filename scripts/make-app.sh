#!/bin/bash
# Builds a real, double-clickable Luminary.app (optimized release build) into dist/ and installs a copy
# into ~/Applications so it shows up in Spotlight/Launchpad.
#   ./scripts/make-app.sh            build + install
#   ./scripts/make-app.sh --no-install
#   ./scripts/make-app.sh --package     dist/Luminary-<version>.dmg for a release (see scripts/release.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

# Bump both for every release. BUILD must always go up: Sparkle compares it to decide what's newer.
VERSION="0.2.0"
BUILD="2"
BUNDLE_ID="app.luminary.Luminary"
APP="dist/Luminary.app"

swift build -c release          # release (no dev session store): the installed app uses the real Keychain
BIN=".build/arm64-apple-macosx/release/Luminary"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Luminary"
# Drop debug symbols: they hold the build machine's folder paths (privacy) and add ~7 MB.
strip -S -x "$APP/Contents/MacOS/Luminary"

# Sparkle (in-app updates) is a dynamic framework; the binary looks for it in Contents/Frameworks.
mkdir -p "$APP/Contents/Frameworks"
ditto ".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

# App icon: assets/icon-1024.png (drawn by scripts/make-icon.swift) -> AppIcon.icns
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "assets/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size*2)) $((size*2)) "assets/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleName</key><string>Luminary</string>
  <key>CFBundleDisplayName</key><string>Luminary</string>
  <key>CFBundleExecutable</key><string>Luminary</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <!-- Jellyfin servers are often plain http on the home network. -->
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
  <key>NSLocalNetworkUsageDescription</key><string>Luminary connects to your Jellyfin server on your local network.</string>
  <!-- In-app updates: the list of releases, and the public half of the key that signs them. -->
  <key>SUFeedURL</key><string>https://raw.githubusercontent.com/portwhy/Luminary/main/appcast.xml</string>
  <key>SUPublicEDKey</key><string>F3rM2N/3uqlZ3lN8ChHFRSsBR4pPQIFKSX9oJR5UKFo=</string>
  <key>SUEnableAutomaticChecks</key><true/>
</dict></plist>
PLIST

# Stable local certificate if scripts/dev.sh created one, otherwise ad-hoc. Releases use it too: macOS doesn't trust
# it (no paid Developer ID), but a signature that stays the same means the Keychain keeps trusting updated versions
# instead of asking for the password after every update.
if security find-certificate -c "Luminary Dev Signing" >/dev/null 2>&1; then
  IDENTITY="Luminary Dev Signing"
else
  IDENTITY="-"
fi
# Inside out: Sparkle's helpers, then the framework, then the app.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in "$SPARKLE"/XPCServices/*.xpc "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
  codesign --force --sign "$IDENTITY" "$part"
done
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP" && echo "signed with: $IDENTITY"

if [ "${1:-}" = "--package" ]; then
  # Privacy: nothing in a public download may contain this Mac's home folder path (user name, folder names).
  if grep -raqF "$HOME/" "$APP"; then
    echo "Refusing to package: $APP contains this Mac's home folder path." >&2
    exit 1
  fi
  # Disk image with the app next to an Applications shortcut, so installing is one drag.
  DMG="dist/Luminary-$VERSION.dmg"
  STAGE="$(mktemp -d)"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMG"
  hdiutil create -volname "Luminary" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -quiet "$DMG"
  rm -rf "$STAGE" "$APP"
  echo "packaged: $DMG"
elif [ "${1:-}" != "--no-install" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Luminary.app"
  cp -R "$APP" "$HOME/Applications/Luminary.app"
  echo "installed: $HOME/Applications/Luminary.app"
  rm -rf "$APP"   # keep a single copy so Spotlight/Launchpad don't list duplicates
else
  echo "built: $APP"
fi
