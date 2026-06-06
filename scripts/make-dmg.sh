#!/bin/bash
# Wrap "UA Commander.app" in a drag-to-Applications DMG.
#
# Usage:
#   scripts/make-dmg.sh           # builds the app first, then the DMG
#   VERSION=1.2.3 scripts/make-dmg.sh
#
# Output: dist/UA-Commander-<version>-<arch>.dmg
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

VERSION="${VERSION:-0.0.0-dev}"
ARCH="$(uname -m)"
APP_NAME="UA Commander"
DIST="$SCRIPT_DIR/dist"
DMG="$DIST/UA-Commander-$VERSION-$ARCH.dmg"

# Build the .app into a temp dir — it's just an ingredient for the DMG, so we
# don't want it left in the repo where Spotlight/Launchpad would index it.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
OUT_DIR="$WORK" VERSION="$VERSION" "$SCRIPT_DIR/scripts/build-app.sh"

echo "=== Building DMG ==="

STAGE="$WORK/dmg"
mkdir -p "$STAGE" "$DIST"
cp -R "$WORK/$APP_NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag target

rm -f "$DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

echo "✅ $DMG"
