#!/bin/bash
# Install this release for the current macOS user and start the menu-bar app at login.
set -euo pipefail
version=1.3.0
base="https://github.com/calmmage/notch-banner/releases/download/v$version"
archive="NotchBanner-v$version-macOS.zip"
apps="$HOME/Applications"
label=com.calmmage.notch-banner
agent_dir="$HOME/Library/LaunchAgents"
plist="$agent_dir/$label.plist"
domain="gui/$(id -u)"
target="$apps/NotchBanner.app"

mkdir -p "$apps" "$agent_dir"
stage=$(mktemp -d "$apps/.notch-banner.XXXXXXXX")
lock="$apps/.notch-banner-install.lock"
if ! mkdir "$lock" 2>/dev/null; then
    rmdir "$stage"
    echo "Another NotchBanner installation is in progress." >&2
    exit 1
fi
changed_app=false
changed_agent=false
was_loaded=false
success=false
start_agent() {
    # launchd can acknowledge bootout before the previous service has exited.
    for delay in 0 1 1 2 3; do
        sleep "$delay"
        if launchctl bootstrap "$domain" "$plist" 2>"$stage/bootstrap-error"; then return 0; fi
    done
    cat "$stage/bootstrap-error" >&2
    return 1
}
cleanup() {
    if ! "$success"; then
        if "$changed_agent"; then
            launchctl bootout "$domain/$label" 2>/dev/null || true
            rm -f "$plist"
            if [[ -e "$stage/previous.plist" ]]; then cp -p "$stage/previous.plist" "$plist"; fi
        fi
        if "$changed_app"; then
            rm -rf "$target"
            if [[ -d "$stage/previous.app" ]]; then mv "$stage/previous.app" "$target"; fi
        fi
        if "$was_loaded" && [[ -f "$plist" ]]; then start_agent || true; fi
    fi
    rm -rf "$stage"
    rmdir "$lock"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
cd "$stage"
echo "Downloading NotchBanner ${version}..."
curl --fail --silent --show-error --location --retry 3 "$base/$archive" -o "$archive"
curl --fail --silent --show-error --location --retry 3 "$base/SHA256SUMS" -o SHA256SUMS
shasum -a 256 -c SHA256SUMS
ditto -x -k "$archive" "$stage"
app="$stage/NotchBanner.app"
codesign --verify --strict "$app"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" | grep -Fxq "$label"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" ]]
if [[ -e "$target" ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist")" == "$label" ]] || exit 1
fi
plutil -create xml1 "$stage/new.plist"
plutil -insert Label -string "$label" "$stage/new.plist"
plutil -insert ProgramArguments -array "$stage/new.plist"
plutil -insert ProgramArguments.0 -string "$target/Contents/MacOS/NotchBanner" "$stage/new.plist"
plutil -insert RunAtLoad -bool true "$stage/new.plist"
if [[ -d "$target" && -f "$plist" ]] && cmp -s "$plist" "$stage/new.plist" && diff -qr "$app" "$target" >/dev/null && launchctl print "$domain/$label" >/dev/null 2>&1; then
    launchctl kickstart "$domain/$label"
    success=true
    echo "NotchBanner $version is already installed. Click the flag in the menu bar."
    exit 0
fi
if [[ -e "$plist" ]]; then cp -p "$plist" "$stage/previous.plist"; fi
if launchctl print "$domain/$label" >/dev/null 2>&1; then
    was_loaded=true
    launchctl bootout "$domain/$label"
fi
if [[ -e "$target" ]]; then mv "$target" "$stage/previous.app"; fi
changed_app=true
mv "$app" "$target"
changed_agent=true
mv "$stage/new.plist" "$plist"
start_agent
launchctl kickstart "$domain/$label"
success=true
echo "Installed. Click the flag in the menu bar to open Banner Studio."
