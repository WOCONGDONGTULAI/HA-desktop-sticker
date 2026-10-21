#!/bin/bash
# 编译并打包成 HASticker.app，拖进「应用程序」即可。
# 用法： ./make-app.sh
set -e
cd "$(dirname "$0")"

echo "==> 编译 (release)"
if swift build -c release 2>/dev/null; then
    echo "    SPM 编译完成"
else
    # 有些机器只装了命令行工具、没有完整的 SwiftPM 库，直接用 swiftc 兜底
    echo "    SPM 不可用，改用 swiftc 直接编译"
    SDK=$(xcrun --show-sdk-path)
    ARCH=$(uname -m)
    mkdir -p .build/release
    swiftc -O -target "${ARCH}-apple-macos12.0" -sdk "$SDK" \
        Sources/HASticker/*.swift -o .build/release/HASticker
fi

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
