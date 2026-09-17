#!/bin/zsh
# Prints the SDK path that this machine can compile SwiftUI code with, or
# nothing when the default SDK already works.
#
# SwiftUI's @State, @Environment and @FocusState are compile-time macros in the
# current macOS SDKs. Expanding them needs Apple's SwiftUIMacros plugin, which
# only ships inside Xcode. On a Command Line Tools only machine the plugin is
# missing, so the newest SDK fails to compile any SwiftUI view. Older installed
# SDKs still declare those attributes as plain property wrappers and need no
# plugin, so fall back to the most recent SDK that works.
#
# With Xcode selected the probe below passes right away and no flag is printed.
set -uo pipefail

SDK_ROOT="$(xcode-select -p)/SDKs"

probe() {
  local probe_dir probe_status
  probe_dir="$(mktemp -d)"
  cat > "$probe_dir/probe.swift" <<'SWIFT'
import SwiftUI

struct LumaSDKProbeView: View {
    @State private var value = 0
    var body: some View { Text("\(value)") }
}
SWIFT
  swiftc -typecheck -swift-version 5 -target arm64-apple-macosx14.4 "$@" \
    "$probe_dir/probe.swift" >/dev/null 2>&1
  probe_status=$?
  rm -rf "$probe_dir"
  return $probe_status
}

if probe; then
  exit 0
fi

for sdk in $(ls -d "$SDK_ROOT"/*.sdk 2>/dev/null | sort -rV); do
  # MacOSX.sdk and MacOSX27.sdk are aliases of the versioned directory.
  [[ -L "$sdk" ]] && continue
  if probe -sdk "$sdk"; then
    print -r -- "$sdk"
    exit 0
  fi
done

exit 1
