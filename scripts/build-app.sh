#!/bin/bash
# Build a proper "UA Commander.app" bundle from the SwiftPM executable.
#
# No Apple Developer account required — the app is ad-hoc signed, which is
# enough for a local menu-bar app and for SMAppService "Launch at Login".
#
# Usage:
#   scripts/build-app.sh              # build for the host arch
#   VERSION=1.2.3 scripts/build-app.sh
#
# Output: dist/UA Commander.app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

EXEC_NAME="ua-commander"
APP_NAME="UA Commander"
BUNDLE_ID="com.kalskiid.uacommander"
VERSION="${VERSION:-0.0.0-dev}"

# Where the finished .app lands. Callers that only want a DMG (make-dmg.sh)
# or an /Applications install (install.sh) point this at a temp dir so no
# stray .app is left in the repo for Spotlight/Launchpad to index.
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/dist}"
APP="$OUT_DIR/$APP_NAME.app"
mkdir -p "$OUT_DIR"

echo "=== Building $APP_NAME.app ($VERSION) ==="

# 1. Compile the release binary.
echo "→ swift build -c release"
swift build -c release

BIN="$SCRIPT_DIR/.build/release/$EXEC_NAME"
[ -f "$BIN" ] || { echo "❌ binary not found at $BIN"; exit 1; }

# 2. Lay out the .app skeleton.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$EXEC_NAME"

# Menu-bar icons go loose into Contents/Resources — the standard macOS spot
# that Bundle.main resolves. (SwiftPM's Bundle.module looks elsewhere and would
# crash; the app loads via Bundle.main instead. See loadIcon in AppDelegate.)
cp "$SCRIPT_DIR/Sources/ua-commander/Resources/"*.png "$APP/Contents/Resources/"

# 3. Finder/DMG icon — generated from the hi-res asset if present.
ICON_SRC="$SCRIPT_DIR/assets/ua-commander-hi-res.png"
if [ -f "$ICON_SRC" ]; then
    echo "→ generating AppIcon.icns"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 64 128 256 512; do
        sips -z "$size" "$size"       "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png"     >/dev/null
        sips -z $((size*2)) $((size*2)) "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET")"
fi

# 4. Info.plist. LSUIElement keeps it out of the Dock (menu-bar agent).
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXEC_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Rosen Stoyanov. MIT License.</string>
</dict>
</plist>
PLIST

# 5. Ad-hoc code signature. Stable identity, no paid cert.
echo "→ ad-hoc codesign"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
    codesign --force --sign - "$APP"

echo "✅ $APP"
