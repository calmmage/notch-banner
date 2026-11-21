#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"

# Ensure 8K textures exist if rsvg-convert is available
if [[ ! -f "$ROOT/Resources/banner-math.png" || ! -f "$ROOT/Resources/banner-plates.png" ]]; then
  if command -v rsvg-convert >/dev/null 2>&1; then
    echo "Generating 8K mathematical atlases..."
    python3 "$ROOT/Scripts/banner_math.py" --out "$ROOT/Resources"
  else
    echo "Note: rsvg-convert not found; procedural velvet, embroidery, silk, and live board still work."
  fi
fi

echo "Compiling NotchBanner (Swift + Metal, -O)..."
swiftc -O \
  -framework AppKit \
  -framework SwiftUI \
  -framework Metal \
  -framework MetalKit \
  -framework Carbon \
  -framework AVFoundation \
  -framework CoreMedia \
  -framework CoreVideo \
  "$ROOT/Sources/NotchBanner/main.swift" \
  -o "$ROOT/build/NotchBanner"

if [[ "${1:-}" == "--app" ]]; then
  APP="$ROOT/build/NotchBanner.app"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$ROOT/build/NotchBanner" "$APP/Contents/MacOS/NotchBanner"
  cp "$ROOT/Resources/banner.metal" "$APP/Contents/Resources/"
  [[ -f "$ROOT/Resources/banner-math.png" ]] && cp "$ROOT/Resources/banner-math.png" "$APP/Contents/Resources/"
  [[ -f "$ROOT/Resources/banner-plates.png" ]] && cp "$ROOT/Resources/banner-plates.png" "$APP/Contents/Resources/"
  [[ -f "$ROOT/assets/icon.icns" ]] && cp "$ROOT/assets/icon.icns" "$APP/Contents/Resources/AppIcon.icns"
  cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>NotchBanner</string>
  <key>CFBundleDisplayName</key><string>Notch Banner</string>
  <key>CFBundleIdentifier</key><string>com.calmmage.notch-banner</string>
  <key>CFBundleVersion</key><string>1.0.0</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleExecutable</key><string>NotchBanner</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
  echo "Built $APP"
else
  echo "Built $ROOT/build/NotchBanner"
fi
