#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/Scripts/build.sh" --app

DEST="/Applications/NotchBanner.app"
rm -rf "$DEST"
cp -R "$ROOT/build/NotchBanner.app" "$DEST"
echo "Installed $DEST"

PLIST="$HOME/Library/LaunchAgents/com.calmmage.notch-banner.plist"
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.calmmage.notch-banner</string>
  <key>ProgramArguments</key><array><string>$DEST/Contents/MacOS/NotchBanner</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/com.calmmage.notch-banner" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Launched com.calmmage.notch-banner (flag icon in menu bar · Ctrl+Opt+Cmd+B to toggle)"
