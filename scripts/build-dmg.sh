#!/bin/zsh
# 打出可直接分发的 DMG：通用二进制 + 拖进「应用程序」的安装布局。
# 版本号取自 Resources/Info.plist 的 CFBundleShortVersionString。
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist")"
APP_DIR="$PROJECT_DIR/dist/Luma.build"
STAGING="$PROJECT_DIR/dist/dmg-staging"
DMG="$PROJECT_DIR/dist/Luma-$VERSION.dmg"

"$PROJECT_DIR/scripts/build-app.sh" --universal >/dev/null

rm -rf "$STAGING"
mkdir -p "$STAGING"
# ditto 而不是 cp -R：保留 bundle 内的代码签名与扩展属性。
ditto "$APP_DIR" "$STAGING/Luma.app"
ln -s /Applications "$STAGING/Applications"

# 应用只做了 ad-hoc 签名（没有 Apple 开发者证书，无法公证），从浏览器下载后
# 会被 Gatekeeper 拦下。把绕过办法放在盘里，用户不必回发布页找。
cat > "$STAGING/安装说明.txt" <<'TXT'
Luma 安装说明
=============

1. 把 Luma.app 拖到右侧的「应用程序」文件夹。

2. 第一次打开会被 macOS 拦下，提示「无法验证开发者」或「已损坏」。
   Luma 没有 Apple 开发者签名，这是预期行为，不是文件损坏。

   任选一种方式放行：

   · 在「应用程序」中右键点击 Luma，选择「打开」，再在弹窗里点「打开」。
     之后双击即可正常启动。

   · 或者打开「终端」执行：
     xattr -dr com.apple.quarantine /Applications/Luma.app

3. Luma 是常驻菜单栏的应用（不会出现在 Dock 里），
   默认快捷键 ⌥Space 唤起，菜单栏图标里可以退出。

系统要求：macOS 14.4 或更高版本，Apple 芯片与 Intel 均可。
TXT

rm -f "$DMG"
hdiutil create \
  -volname "Luma $VERSION" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -ov \
  "$DMG" >/dev/null

rm -rf "$STAGING"
echo "$DMG"
