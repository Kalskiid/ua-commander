#!/bin/bash
PLIST_NAME="com.kalskiid.apollocontroller"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

launchctl stop "$PLIST_NAME" 2>/dev/null
launchctl unload "$PLIST_PATH" 2>/dev/null
rm -f "$PLIST_PATH"
pkill -f ApolloController 2>/dev/null

echo "Apollo Controller uninstalled."
