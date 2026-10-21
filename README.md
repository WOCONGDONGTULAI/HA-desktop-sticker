# HA Desktop Sticker

把 Home Assistant 的仪表盘变成**贴在桌面上的小贴纸**：不用开浏览器、不用切标签页，抬眼就能看到、伸手就能点。

- macOS 端：AppKit `NSPanel` + `WKWebView`，可真正贴进桌面层
- Windows 端：WinForms + WebView2，支持嵌入 Explorer 桌面层

两端共用同一份 Home Assistant 仪表盘，登录一次长期保持。

```
home-assistant/   贴纸专用仪表盘 YAML（放进 HA 里）
macos/            macOS 贴纸（Swift，Xcode / swift build）
windows/          Windows 贴纸（C# WinForms + WebView2）
```

## 一分钟跑起来

### 1. 先在 HA 里做一个贴纸专用仪表盘

HA 里 `设置 → 仪表盘 → 新增仪表盘`，标题随便（比如「贴纸」），把 `home-assistant/dashboard-sticker.yaml` 的内容粘进去，把里面的实体 id 换成你自己的。

记住它的地址，形如 `http://homeassistant.local:8123/sticker`（`/sticker` 是仪表盘路径，`?kiosk` 可隐藏侧边栏和顶栏）。

### 2. 装贴纸

| 平台 | 位置 | 说明 |
| --- | --- | --- |
| macOS | `macos/README.md` | 现成 app 直接下：[Releases](../../releases) 里的 `HASticker.app.zip`；或 `./make-app.sh` 自己编译 |
| Windows | `windows/README.md` | `build.bat` 产出单文件 exe，或 `run.bat` 跑源码 |

### 3. 填地址

贴纸首次运行会弹出设置框，把仪表盘地址填进去（建议带 `?kiosk`）：

```
http://homeassistant.local:8123/sticker?kiosk
```

第一次会要求你登录 HA，登录一次之后 cookie 长期保存，之后都是自动进。

## 三种贴法

两端都支持三档，右键菜单 / 托盘菜单里切换：

| 模式 | 效果 | 适合 |
| --- | --- | --- |
| **desktop** 桌面层 | 贴在桌面上，Win+D 时跟着出现，开其他程序时被正常遮挡，`Alt+Tab` 里不出现 | 长期挂着看状态 |
| **top** 置顶 | 永远浮在所有窗口之上 | 需要随时点开关 |
| **normal** 普通 | 就是个普通小窗口 | 偶尔用用 |

- Windows 桌面层用的是给 `Progman` 发 `0x052C` 消息、把窗口挂到 Explorer 的 `WorkerW` 上——资源管理器重启会失效，程序会自动重试，也可以手动「重新贴回桌面」。
- macOS 桌面层是把窗口 level 设到 `kCGDesktopWindowLevel` 之上，全空间可见（切桌面都在）。

## 常见问题

**打不开 / 白屏**
- HA 地址填错。贴纸里右键 → 设置，确认能 ping 通。
- 用了 `http://` 明文：macOS 的 ATS 已在本工程的 `Info.plist` 里放开（`NSAllowsArbitraryLoads`），Windows 无此限制。
- macOS 15 起本地网络要授权，首次会弹「HASticker 想要查找并连接本地网络上的设备」，选允许。

**老是要重新登录**
Web 数据目录是持久的（Windows：`%LOCALAPPDATA%\HASticker\WebView2Data`；macOS：默认 `WKWebsiteDataStore`）。如果被人清过缓存，重新登录一次即可。

**想改大小**
拖动贴纸边缘即可缩放（Windows 需要拖动条解锁状态），位置和大小都会记住。

## 版本

版本号纯数字递增，数字最大即最新版，见 [Releases](../../releases)。
