#!/usr/bin/env bash
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install with: brew install xcodegen"
  exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="$PROJECT_ROOT/build/DerivedData"
CONFIGURATION="${CONFIGURATION:-Debug}"
PRODUCT_NAME="ScreenStocker.saver"
PRODUCT_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$PRODUCT_NAME"
APP_NAME="ScreenStocker Manager.app"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
INSTALL_DIR="$HOME/Library/Screen Savers"
INSTALL_PATH="$INSTALL_DIR/$PRODUCT_NAME"

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

echo "Installed $PRODUCT_NAME to $INSTALL_PATH"
echo "Built manager app at $APP_PATH"
