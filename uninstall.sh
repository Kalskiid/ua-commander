#!/bin/bash
# Remove UA Commander completely.
set -euo pipefail

APP_NAME="UA Commander"
LABEL="com.kalskiid.uacommander"
UID_NUM="$(id -u)"

# Stop the running app.
pkill -f "ua-commander" 2>/dev/null || true

# Remove the app bundle (both /Applications and a user-local copy).
rm -rf "/Applications/$APP_NAME.app"
rm -rf "$HOME/Applications/$APP_NAME.app"

# Drop the SMAppService login item, if registered.
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true

# Clean up the legacy pre-1.x LaunchAgent, if it's still around.
LEGACY_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
if [ -f "$LEGACY_PLIST" ]; then
    launchctl unload "$LEGACY_PLIST" 2>/dev/null || true
    rm -f "$LEGACY_PLIST"
fi

echo "UA Commander uninstalled."
