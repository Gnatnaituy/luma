#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# 同 build-app.sh：纯 Command Line Tools 环境下换用仍以属性包装器实现
# SwiftUI 状态的 SDK（详见 scripts/select-sdk.sh）。SwiftPM 通过 SDKROOT 生效。
SDK_PATH="$("$PROJECT_DIR/scripts/select-sdk.sh" || true)"
PLUGIN_ARGS=()
if [[ -n "$SDK_PATH" ]]; then
  export SDKROOT="$SDK_PATH"
  echo "note: testing with $SDK_PATH" >&2

  # 指定 SDK 后 swift-driver 不再自动追加 Swift Testing 宏插件的搜索路径，
  # 缺少它时 @Test / #expect 会报 "plugin for module 'TestingMacros' not found"。
  # Swift Testing 的插件比 SwiftUI 宏插件深一层（host/plugins/testing），所以要单独补上。
  TOOLCHAIN_PLUGINS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins"
  for dir in "$TOOLCHAIN_PLUGINS" "$TOOLCHAIN_PLUGINS/testing"; do
    [[ -d "$dir" ]] && PLUGIN_ARGS+=(-Xswiftc -plugin-path -Xswiftc "$dir")
  done
fi

swift test "${PLUGIN_ARGS[@]}"
