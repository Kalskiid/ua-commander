#!/bin/bash
# Build UA Commander from source and install it to /Applications.
#
# Most users should grab the .dmg from Releases instead — this is the
# build-from-source path and requires Xcode Command Line Tools.
#
# Launch-at-login is no longer configured here: open the menu-bar icon and
# toggle "Launch at Login" whenever you want it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="UA Commander"
DEST="/Applications/$APP_NAME.app"

echo "=== UA Commander Installer ==="

# Build into a temp dir so no stray .app is left in the repo for Launchpad to
# index alongside the installed one.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
OUT_DIR="$WORK" "$SCRIPT_DIR/scripts/build-app.sh"

# Replace any previous copy and run the fresh one.
pkill -f "ua-commander" 2>/dev/null || true
rm -rf "$DEST"
cp -R "$WORK/$APP_NAME.app" "$DEST"
open "$DEST"

echo
echo "✅ Installed to $DEST and launched."
echo "   Menu-bar icon → Launch at Login to start it automatically."
echo "   Log: $HOME/Library/Logs/ua-commander.log"
