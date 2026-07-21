#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$PROJECT_DIR/.build/tests"
mkdir -p "$BUILD_ROOT/ModuleCache"

export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/ModuleCache"
swiftc \
  -parse-as-library \
  -swift-version 5 \
  -target arm64-apple-macosx14.4 \
  -framework AppKit \
  -framework Carbon \
  -framework Combine \
  -framework CryptoKit \
  -framework Security \
  -framework SwiftUI \
  -framework Translation \
  "$PROJECT_DIR/Sources/Luma/AIService.swift" \
  "$PROJECT_DIR/Sources/Luma/AISettings.swift" \
  "$PROJECT_DIR/Sources/Luma/AISettingsViews.swift" \
  "$PROJECT_DIR/Sources/Luma/ClipboardStorage.swift" \
  "$PROJECT_DIR/Sources/Luma/ClipboardMonitor.swift" \
  "$PROJECT_DIR/Sources/Luma/ClipboardPaster.swift" \
  "$PROJECT_DIR/Sources/Luma/ExpressionEvaluator.swift" \
  "$PROJECT_DIR/Sources/Luma/LumaButtonStyles.swift" \
  "$PROJECT_DIR/Sources/Luma/InstalledAppIndex.swift" \
  "$PROJECT_DIR/Sources/Luma/JSONSyntaxEditor.swift" \
  "$PROJECT_DIR/Sources/Luma/LauncherModel.swift" \
  "$PROJECT_DIR/Sources/Luma/LauncherView.swift" \
  "$PROJECT_DIR/Sources/Luma/Plugin.swift" \
  "$PROJECT_DIR/Sources/Luma/PluginSettings.swift" \
  "$PROJECT_DIR/Sources/Luma/RecentUsageStore.swift" \
  "$PROJECT_DIR/Sources/Luma/PluginViews.swift" \
  "$PROJECT_DIR/Sources/Luma/SearchField.swift" \
  "$PROJECT_DIR/Sources/Luma/ShortcutSettings.swift" \
  "$PROJECT_DIR/Sources/Luma/StockService.swift" \
  "$PROJECT_DIR/Sources/Luma/StockStyle.swift" \
  "$PROJECT_DIR/Sources/Luma/Toolbox.swift" \
  "$PROJECT_DIR/Sources/Luma/WindowPlacement.swift" \
  "$PROJECT_DIR/Tests/CoreTests.swift" \
  -o "$BUILD_ROOT/CoreTests"

"$BUILD_ROOT/CoreTests"
