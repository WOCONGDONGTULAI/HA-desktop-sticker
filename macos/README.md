# macOS 贴纸

无边框、圆角的桌面小窗，里面是 Home Assistant 仪表盘。不进 Dock、不进 `Command+Tab`，只在菜单栏留一个图标。

## 装（两种方式，挑一个）

### A. 直接下载现成的 app

去 [Releases](https://github.com/WOCONGDONGTULAI/HA-desktop-sticker/releases) 下载
`HASticker.app.zip`，解压后把 `HASticker.app` 拖进「应用程序」文件夹，双击运行。

首次打开如果提示「无法打开，因为它来自身份不明的开发者」：右键 app → 「打开」→ 确认
（自己编译的 app 没有苹果开发者签名，这是正常现象，只第一次要这样）。

### B. 自己编译

```bash
cd macos
chmod +x make-app.sh
./make-app.sh
```

产出 `macos/HASticker.app`。脚本优先用 SwiftPM；机器上 SwiftPM 不完整时会自动退回 `swiftc` 直接编译。

> 第一次运行可能被 Gatekeeper 拦：右键 app → 「打开」→ 确认。脚本已经帮你清过 quarantine 标记。

要求 macOS 12+（Apple Silicon 与 Intel 通用，现成 app 是 arm64 版；Intel 机器用方式 B 自己编译）。
编译需要 Xcode 命令行工具（`xcode-select --install`）。

## 用

1. 首次运行自动弹设置框 → 填 HA 仪表盘地址，比如：
   ```
   http://homeassistant.local:8123/ha-sticker?kiosk
   ```
2. 第一次会跳 HA 登录页，登录一次，之后永久自动登录。
3. 之后每次开机启动，贴纸就在那儿了。

想开机自启：系统设置 → 通用 → 登录项 → 把 `HASticker.app` 加进去。

## 操作

| 操作 | 怎么弄 |
| --- | --- |
### 两种状态

| 状态 | 怎么进 | 能干什么 |
| --- | --- | --- |
| **调整模式**（默认） | 菜单里「锁定」**不勾选** | 贴纸任意位置按住左键就能拖；拖边缘缩放；顶部自动出现拖动条，四周有一圈细描边 |
| **锁定** | 菜单里勾选「锁定」 | 位置大小全部固定，拖不动也缩放不了，只能点里面的开关。拖动条和描边全部隐藏 |

调好位置 → 勾选「锁定」，就再也不会被误拖跑了。想重新调整就取消勾选。

| 操作 | 怎么弄 |
| --- | --- |
| 移动 | 调整模式下，在贴纸任意位置按住左键拖（或拖顶部那条横杠） |
| 点开关 | 直接点，不用按修饰键。位移小于 4pt 才算点击，不会误触 |
| 缩放 | 调整模式下拖贴纸边缘 |
| 菜单 | 在贴纸上右键，或点菜单栏图标 |
| 显示 / 隐藏 | 菜单里第一项 |

菜单里能改：贴法（桌面层 / 置顶 / 普通）、**外观（跟随系统 / 始终浅色 / 始终深色）**、
透明度、缩放、锁定位置、重新加载、清除登录状态、退出。

## 深浅色

默认是「跟随系统」：系统切成深色，贴纸和里面的 HA 仪表盘一起变深色，不用重启。
想固定某一种就在菜单 → 外观 里选「始终浅色 / 始终深色」。

实现上是两层保险：
1. 给窗口和 `WKWebView` 设 `NSAppearance`，网页的 `prefers-color-scheme` 就跟着变，
   HA 前端主题设为「默认（跟随系统）」时会自动切；
2. 另外注入一段脚本，直接给 HA 的 `home-assistant` 元素发 `settheme` 事件强制切主题，
   这样即使前端没在跟随系统也能切过去。

设置存在 `~/Library/Application Support/HASticker/settings.json`，删掉这个文件就恢复默认。

## 贴法说明

| 模式 | 表现 |
| --- | --- |
| **desktop**（默认） | 窗口 level 设到桌面层之上，切桌面空间都在，开其他程序时被正常遮挡 |
| **top** | 永远浮在别人上面，随手能点 |
| **normal** | 普通小窗口 |

> macOS 没有 Windows 那种「挂到 Explorer 桌面窗口上」的办法，桌面层是靠窗口 level 模拟的，
> 效果接近：跟着桌面显示、不抢焦点、不在 Alt+Tab 里。

## 打字 / 粘贴

贴纸里的 HA 登录框可以直接打字，`Cmd+V / Cmd+C / Cmd+X / Cmd+A` 都能用。

实现上走了三层（Nib-less app 默认一个都不通）：

1. 程序里手工建了主菜单的「编辑」子菜单（`Cmd+V` 等靠菜单项走响应链）；
2. 窗口层面拦 `performKeyEquivalent`，把 `Cmd+V/C/X/A` 直接转发给第一响应者；
3. 万一上面都不通，右键菜单里有「粘贴到页面」，读剪贴板后直接写进网页里聚焦的输入框。

> 贴纸窗口**没有**用 `.nonactivatingPanel`：带了它点击不会激活 app，窗口拿不到键盘焦点，
> 登录框里既打不了字也粘不了东西。代价是点贴纸会切换一下当前应用，这是能输入的必要代价。

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
