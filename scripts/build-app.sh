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

# 默认只编本机架构；`--universal` 同时编 arm64 与 x86_64 再合成通用二进制，
# 供发布用的 DMG 使用（Intel 机器也能跑）。
ARCHS=(arm64)
if [[ "${1:-}" == "--universal" ]]; then
  ARCHS=(arm64 x86_64)
fi

# 默认 SDK 的 SwiftUI 需要 Xcode 才有的宏插件时，回退到仍以属性包装器实现这些
# 属性的已安装 SDK（详见 scripts/select-sdk.sh）。装了 Xcode 时这里为空。
SDK_PATH="$("$PROJECT_DIR/scripts/select-sdk.sh" || true)"
SDK_ARGS=()
if [[ -n "$SDK_PATH" ]]; then
  SDK_ARGS=(-sdk "$SDK_PATH")
  echo "note: building with $SDK_PATH" >&2
fi

SLICES=()
for arch in "${ARCHS[@]}"; do
  slice="$BUILD_ROOT/release/Luma-$arch"
  swiftc \
    -parse-as-library \
    -swift-version 5 \
    -O \
    -target "$arch-apple-macosx14.4" \
    "${SDK_ARGS[@]}" \
    -framework AppKit \
    -framework SwiftUI \
    -framework Carbon \
    -framework CryptoKit \
    -framework Security \
    -framework ServiceManagement \
    -framework Translation \
    -framework Vision \
    "${SOURCE_FILES[@]}" \
    -o "$slice"
  SLICES+=("$slice")
done

if (( ${#SLICES[@]} > 1 )); then
  lipo -create "${SLICES[@]}" -output "$EXECUTABLE"
else
  cp "${SLICES[1]}" "$EXECUTABLE"
fi

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
