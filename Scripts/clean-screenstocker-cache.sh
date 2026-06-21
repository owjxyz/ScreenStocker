#!/usr/bin/env bash
set -euo pipefail

paths=(
  "$HOME/Library/Preferences/ByHost/ScreenStocker.1F4295EF-B57A-5B91-A32C-AF090916BEA6.plist"
  "$HOME/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences/ByHost/ScreenStocker.1F4295EF-B57A-5B91-A32C-AF090916BEA6.plist"
  "$HOME/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences/com.tasokiii.ScreenStocker.preferences.plist"
  "$HOME/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences/com.lukeoh.ScreenStocker.preferences.plist"
  "$HOME/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches/screenSaver-/Users/lukeoh/Library/Screen Savers/ScreenStocker.saver"
)

for path in "${paths[@]}"; do
  if [ -e "$path" ]; then
    if rm -rf "$path"; then
      echo "Removed: $path"
    else
      echo "Failed: $path"
    fi
  else
    echo "Not found: $path"
  fi
done

pkill -x cfprefsd >/dev/null 2>&1 || true
pkill -x "System Settings" >/dev/null 2>&1 || true
pkill -x legacyScreenSaver >/dev/null 2>&1 || true
pkill -x ScreenSaverEngine >/dev/null 2>&1 || true
pkill -x WallpaperAgent >/dev/null 2>&1 || true
pkill -x wallpaperAgent >/dev/null 2>&1 || true

echo "ScreenStocker screen saver caches cleared."
