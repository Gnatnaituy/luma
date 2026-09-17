#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# 同 build-app.sh：纯 Command Line Tools 环境下换用仍以属性包装器实现
# SwiftUI 状态的 SDK（详见 scripts/select-sdk.sh）。SwiftPM 通过 SDKROOT 生效。
SDK_PATH="$("$PROJECT_DIR/scripts/select-sdk.sh" || true)"
if [[ -n "$SDK_PATH" ]]; then
  export SDKROOT="$SDK_PATH"
  echo "note: testing with $SDK_PATH" >&2
fi

swift test
