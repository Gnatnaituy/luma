#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$PROJECT_DIR/.build"
APP_DIR="$PROJECT_DIR/dist/Luma.build"
EXECUTABLE="$BUILD_ROOT/release/Luma"
BUILD_NUMBER="$(date -u +%Y%m%d%H%M%S)"

export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$BUILD_ROOT/release"

SOURCE_FILES=("$PROJECT_DIR"/Sources/Luma/*.swift)
swiftc \
  -parse-as-library \
  -swift-version 5 \
  -O \
  -target arm64-apple-macosx14.4 \
  -framework AppKit \
  -framework SwiftUI \
  -framework Carbon \
  -framework CryptoKit \
  -framework Security \
  -framework ServiceManagement \
  -framework Translation \
  "${SOURCE_FILES[@]}" \
  -o "$EXECUTABLE"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/Luma"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/Luma.icns" "$APP_DIR/Contents/Resources/Luma.icns"
chmod +x "$APP_DIR/Contents/MacOS/Luma"
# Keep the local designated requirement stable so macOS TCC permissions
# continue to match the app after its executable is rebuilt.
codesign \
  --force \
  --deep \
  --sign - \
  --requirements '=designated => identifier "app.luma.launcher"' \
  "$APP_DIR"

echo "$APP_DIR"
