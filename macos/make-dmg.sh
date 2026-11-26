#!/bin/bash
# 打成 DMG：打开后把 HASticker 拖到「应用程序」就装好了，换电脑直接用。
# 用法： ./make-dmg.sh
set -e
cd "$(dirname "$0")"

./make-app.sh

APP="HASticker.app"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="HASticker-${VER}.dmg"

echo "==> 准备 DMG 内容"
STAGE=$(mktemp -d /tmp/ha-sticker-dmg.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
# 拖到这个快捷方式上就等于放进「应用程序」
ln -s /Applications "$STAGE/应用程序"

cat > "$STAGE/安装说明.txt" <<'TXT'
HA 贴纸（HASticker）安装说明
==============================

一、安装
   把左边的 HASticker 拖到右边的「应用程序」文件夹上，就装好了。
   然后到「应用程序」里双击打开，菜单栏会出现一个房子图标。

二、第一次打开被系统拦下来怎么办
   这个 app 没有 Apple 公证（个人项目，没交年费），所以第一次打开
   可能提示「无法打开，因为无法验证开发者」或者「已损坏」。

   正规做法：在 HASticker 上按住 Control 点一下（或右键）→ 选「打开」
            → 弹窗里再点一次「打开」。之后就正常双击就行。

   如果还是不行，打开「终端」粘这一行，回车：
       xattr -dr com.apple.quarantine /Applications/HASticker.app

三、第一次运行要填两样东西
   1. 仪表盘地址，形如 http://homeassistant.local:8123/ha-sticker?kiosk
   2. HA 的长期访问令牌（HA 里：点左下角头像 → 安全 → 长期访问令牌 → 创建）

四、换电脑想连原来的配置一起搬
   把旧机器上的这个文件拷到新机器同样的位置：
       ~/Library/Application Support/HASticker/settings.json
   里面有 HA 地址、令牌、贴纸上放了哪些开关、位置和大小。
   注意：这个文件里存着令牌明文，别随便发给别人。

五、不想要了
   菜单栏图标 → 取消「开机自动启动」，然后直接把 app 拖进废纸篓。
TXT

echo "==> 生成 $DMG"
rm -f "$DMG"
hdiutil create -volname "HA 贴纸" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "==> 完成: $(pwd)/$DMG  ($(du -h "$DMG" | cut -f1))"
