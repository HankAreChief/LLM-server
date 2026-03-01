#!/usr/bin/env bash
# install-launchagent.sh
# Installs and activates the LaunchAgent for automatic startup at login.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

PLIST_SRC="$PROJECT_DIR/launchagent/com.hank.llm-server.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.hank.llm-server.plist"

mkdir -p "$HOME/Library/LaunchAgents"
cp "$PLIST_SRC" "$PLIST_DST"

# Unload first in case it was previously loaded
launchctl unload "$PLIST_DST" 2>/dev/null || true

launchctl load "$PLIST_DST"

echo "✓ LaunchAgent installed and loaded."
echo ""
echo "The stack will now start automatically at each login."
echo ""
echo "Useful commands:"
echo "  Disable:  launchctl unload ~/Library/LaunchAgents/com.hank.llm-server.plist"
echo "  Re-enable: launchctl load ~/Library/LaunchAgents/com.hank.llm-server.plist"
echo "  Status:   launchctl list | grep llm-server"
echo "  Log:      tail -f $PROJECT_DIR/logs/launchagent.log"
