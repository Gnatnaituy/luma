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

# 默认 SDK 的 SwiftUI 需要 Xcode 才有的宏插件时，回退到仍以属性包装器实现这些
# 属性的已安装 SDK（详见 scripts/select-sdk.sh）。装了 Xcode 时这里为空。
SDK_PATH="$("$PROJECT_DIR/scripts/select-sdk.sh" || true)"
SDK_ARGS=()
if [[ -n "$SDK_PATH" ]]; then
  SDK_ARGS=(-sdk "$SDK_PATH")
  echo "note: building with $SDK_PATH" >&2
fi

swiftc \
  -parse-as-library \
  -swift-version 5 \
  -O \
  -target arm64-apple-macosx14.4 \
  "${SDK_ARGS[@]}" \
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
