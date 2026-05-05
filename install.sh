#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ua-commander"
PLIST_NAME="com.kalskiid.uacommander"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

echo "=== UA Commander Installer ==="

# Use a pre-built binary if one is sitting next to this script (downloaded release).
# Otherwise build from source — requires Xcode Command Line Tools.
if [ -f "$SCRIPT_DIR/$APP_NAME" ]; then
    BIN_PATH="$SCRIPT_DIR/$APP_NAME"
    echo "Using pre-built binary."
else
    BIN_PATH="$SCRIPT_DIR/.build/release/$APP_NAME"
    echo "Building from source (this may take a minute)..."
    cd "$SCRIPT_DIR"
    swift build -c release
fi

launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true
launchctl unload "$PLIST_PATH" 2>/dev/null || true

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$PLIST_NAME</string>
    <key>ProgramArguments</key><array><string>$BIN_PATH</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$HOME/Library/Logs/ua-commander.log</string>
    <key>StandardErrorPath</key><string>$HOME/Library/Logs/ua-commander.log</string>
</dict>
</plist>
PLIST

launchctl load "$PLIST_PATH"
sleep 1
if pgrep -q "$APP_NAME"; then
    echo "✅ UA Commander is running"
    echo
    echo "Default keyboard shortcuts:"
    echo "  ⌘⌥↑   Volume Up   (+5%)"
    echo "  ⌘⌥↓   Volume Down (-5%)"
    echo "  ⌘⌥M   Mute toggle"
    echo "  ⌘⌥D   Dim toggle"
    echo
    echo "All shortcuts are configurable — open the menu bar icon → Shortcuts…"
    echo "Log: $HOME/Library/Logs/ua-commander.log"
else
    echo "❌ Failed to start. Check log: $HOME/Library/Logs/ua-commander.log"
    exit 1
fi
