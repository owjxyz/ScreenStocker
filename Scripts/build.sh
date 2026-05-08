#!/usr/bin/env bash
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install with: brew install xcodegen"
  exit 1
fi

REFRESH_AFTER_INSTALL=false

for arg in "$@"; do
  case "$arg" in
    --refresh)
      REFRESH_AFTER_INSTALL=true
      ;;
    -h|--help)
      echo "Usage: $0 [--refresh]"
      echo
      echo "Options:"
      echo "  --refresh  Quit System Settings and screen saver preview processes after installing."
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: $0 [--refresh]" >&2
      exit 1
      ;;
  esac
done

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="$PROJECT_ROOT/build/DerivedData"
CONFIGURATION="${CONFIGURATION:-Debug}"
PRODUCT_NAME="ScreenStocker.saver"
PRODUCT_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$PRODUCT_NAME"
APP_NAME="ScreenStocker.app"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
INSTALL_DIR="$HOME/Library/Screen Savers"
INSTALL_PATH="$INSTALL_DIR/$PRODUCT_NAME"
APP_INSTALL_DIR="$HOME/Applications"
APP_INSTALL_PATH="$APP_INSTALL_DIR/$APP_NAME"

cd "$PROJECT_ROOT"

xcodegen generate
xcodebuild \
  -project ScreenStocker.xcodeproj \
  -scheme ScreenStocker \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

xcodebuild \
  -project ScreenStocker.xcodeproj \
  -scheme ScreenStockerApp \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_PATH"
cp -R "$PRODUCT_PATH" "$INSTALL_PATH"

mkdir -p "$APP_INSTALL_DIR"
rm -rf "$APP_INSTALL_PATH"
cp -R "$APP_PATH" "$APP_INSTALL_PATH"

echo "Installed $PRODUCT_NAME to $INSTALL_PATH"
echo "Installed $APP_NAME to $APP_INSTALL_PATH"
echo "Built app at $APP_PATH"

if [ "$REFRESH_AFTER_INSTALL" = true ]; then
  echo "Refreshing screen saver host processes..."
  pkill -x "System Settings" >/dev/null 2>&1 || true
  pkill -x "legacyScreenSaver" >/dev/null 2>&1 || true
  pkill -x "ScreenSaverEngine" >/dev/null 2>&1 || true
  echo "Refresh complete. Reopen Screen Saver settings to load the newly installed bundle."
fi
