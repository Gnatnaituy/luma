#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$PROJECT_DIR/dist/Luma.build"
LEGACY_SOURCE_APP="$PROJECT_DIR/dist/Luma.app"
INSTALL_APP="/Applications/Luma.app"
STAGING_APP="/Applications/.Luma-installing-$$.app"
BACKUP_APP="/Applications/.Luma-backup-$$.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cleanup() {
  if [[ -e "$STAGING_APP" ]]; then
    rm -rf "$STAGING_APP"
  fi
}
trap cleanup EXIT

"$PROJECT_DIR/scripts/build-app.sh" >/dev/null

# Remove the old discoverable build artifact from LaunchServices. New builds use
# the non-.app Luma.build suffix so app search resolves only /Applications/Luma.app.
"$LSREGISTER" -u "$LEGACY_SOURCE_APP" >/dev/null 2>&1 || true
if [[ -e "$LEGACY_SOURCE_APP" ]]; then
  rm -rf "$LEGACY_SOURCE_APP"
fi

if pgrep -x Luma >/dev/null; then
  killall Luma
fi

ditto "$SOURCE_APP" "$STAGING_APP"
codesign --verify --deep --strict "$STAGING_APP"

if [[ -e "$INSTALL_APP" ]]; then
  mv "$INSTALL_APP" "$BACKUP_APP"
fi

if mv "$STAGING_APP" "$INSTALL_APP"; then
  if [[ -e "$BACKUP_APP" ]]; then
    rm -rf "$BACKUP_APP"
  fi
else
  if [[ -e "$BACKUP_APP" ]]; then
    mv "$BACKUP_APP" "$INSTALL_APP"
  fi
  exit 1
fi

touch "$INSTALL_APP"
"$LSREGISTER" -f "$INSTALL_APP"
open "$INSTALL_APP"
echo "$INSTALL_APP"
