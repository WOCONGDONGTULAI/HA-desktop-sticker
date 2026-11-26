#!/bin/bash
# 编译并打包成 HASticker.app，拖进「应用程序」即可。
# 用法： ./make-app.sh          （通用二进制，Intel / Apple Silicon 都能跑）
#        ./make-dmg.sh          （打成 DMG，换电脑直接装）
set -e
cd "$(dirname "$0")"

echo "==> 编译 (release, 通用二进制)"
SDK=$(xcrun --show-sdk-path)
mkdir -p .build/release
OUT=.build/release

# 两个架构分别编，再 lipo 合起来。换电脑（尤其换到 Intel 机器）才不会打不开。
build_arch() {
    swiftc -O -target "$1-apple-macos12.0" -sdk "$SDK" \
        Sources/HASticker/*.swift -o "${OUT}/HASticker-$1"
}

if [ "$(uname -m)" = "arm64" ]; then ARCHS="arm64 x86_64"; else ARCHS="x86_64 arm64"; fi

THIN=()
for a in $ARCHS; do
    if build_arch "$a" 2>/dev/null; then
        THIN+=("${OUT}/HASticker-${a}")
        echo "    ${a} 完成"
    else
        echo "    ${a} 编译失败，跳过"
    fi
done

if [ ${#THIN[@]} -eq 0 ]; then
    echo "!! 两个架构都没编出来，先确认 Xcode Command Line Tools 装好了" >&2
    exit 1
fi
if [ ${#THIN[@]} -eq 1 ]; then
    cp "${THIN[0]}" "${OUT}/HASticker"
else
    lipo -create "${THIN[@]}" -output "${OUT}/HASticker"
fi
echo "    架构: $(lipo -archs "${OUT}/HASticker")"

APP="HASticker.app"
echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "${OUT}/HASticker" "$APP/Contents/MacOS/HASticker"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
# 图标资源：菜单栏模板图（@1x/@2x/@3x）+ 应用图标
cp Resources/StatusIcon.png Resources/StatusIcon@2x.png Resources/StatusIcon@3x.png "$APP/Contents/Resources/" 2>/dev/null || true
cp Resources/AppIcon.icns "$APP/Contents/Resources/" 2>/dev/null || true
chmod +x "$APP/Contents/MacOS/HASticker"

# 去掉 quarantine 标记（自己编的 app 常被 Gatekeeper 拦）
xattr -cr "$APP" 2>/dev/null || true

# 临时签名：Apple Silicon 上未签名的可执行文件会被直接杀掉；
# 换电脑后也能少一层麻烦（没做公证，第一次仍要「右键 → 打开」）
if codesign --force --sign - "$APP" 2>/dev/null; then
    echo "    已临时签名"
else
    echo "    签名失败（本机运行不受影响）"
fi

VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo "==> 完成: $(pwd)/$APP  (版本 $VER)"
echo "    拖进「应用程序」文件夹，双击运行；菜单栏会出现贴纸图标。"
