# macOS 贴纸

无边框、圆角的桌面小窗，里面是 Home Assistant 仪表盘。不进 Dock、不进 `Command+Tab`，只在菜单栏留一个图标。

## 装

```bash
cd macos
chmod +x make-app.sh
./make-app.sh
```

产出 `macos/HASticker.app`，拖进「应用程序」文件夹，双击运行。

> 第一次运行可能被 Gatekeeper 拦：右键 app → 「打开」→ 确认。脚本已经帮你清过 quarantine 标记。

要求 macOS 13+，装过 Xcode 命令行工具（`xcode-select --install`）。

## 用

1. 首次运行自动弹设置框 → 填 HA 仪表盘地址，比如：
   ```
   http://homeassistant.local:8123/sticker?kiosk
   ```
2. 第一次会跳 HA 登录页，登录一次，之后永久自动登录。
3. 之后每次开机启动，贴纸就在那儿了。

想开机自启：系统设置 → 通用 → 登录项 → 把 `HASticker.app` 加进去。

## 操作

| 操作 | 怎么弄 |
| --- | --- |
| 移动 | 按住贴纸任意空白处拖（锁定了除外） |
| 缩放 | 拖贴纸边缘 |
| 菜单 | 在贴纸上右键，或点菜单栏图标 |
| 显示 / 隐藏 | 菜单里第一项 |

菜单里能改：贴法（桌面层 / 置顶 / 普通）、透明度、缩放、锁定位置、重新加载、清除登录状态、退出。

设置存在 `~/Library/Application Support/HASticker/settings.json`，删掉这个文件就恢复默认。

## 贴法说明

| 模式 | 表现 |
| --- | --- |
| **desktop**（默认） | 窗口 level 设到桌面层之上，切桌面空间都在，开其他程序时被正常遮挡 |
| **top** | 永远浮在别人上面，随手能点 |
| **normal** | 普通小窗口 |

> macOS 没有 Windows 那种「挂到 Explorer 桌面窗口上」的办法，桌面层是靠窗口 level 模拟的，
> 效果接近：跟着桌面显示、不抢焦点、不在 Alt+Tab 里。

## 常见问题

**白屏 / 打不开**
- 地址填对没。贴纸里右键 → 设置，改完自动重载。
- 内网 `http://` 已被 `Info.plist` 的 `NSAllowsArbitraryLoads` 放开。
- macOS 15 起会弹「本地网络」权限，一定选**允许**，否则连不上 `homeassistant.local`。

**菜单栏没图标**
app 是 `LSUIElement=1`（不占 Dock），只有菜单栏入口。如果图标被别的 app 挤掉了，从右边往左找。

**改代码**
```bash
swift build          # 编译
./make-app.sh        # 编译 + 打包
```
想用 Xcode 打开：`open Package.swift`（Xcode 12+ 支持 SPM 工程）。
