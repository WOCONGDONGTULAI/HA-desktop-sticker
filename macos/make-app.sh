#!/bin/bash
# 编译并打包成 HASticker.app，拖进「应用程序」即可。
# 用法： ./make-app.sh
set -e
cd "$(dirname "$0")"

echo "==> 编译 (release)"
swift build -c release

APP="HASticker.app"
echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/HASticker" "$APP/Contents/MacOS/HASticker"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/HASticker"

# 去掉 quarantine 标记（自己编的 app 常被 Gatekeeper 拦）
xattr -cr "$APP" 2>/dev/null || true

echo "==> 完成: $(pwd)/$APP"
echo "    拖进「应用程序」文件夹，双击运行；菜单栏会出现贴纸图标。"
