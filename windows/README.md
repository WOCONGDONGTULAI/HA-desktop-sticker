# Windows 贴纸

无边框、圆角的小窗，里面是 Home Assistant 仪表盘。不进任务栏，只在右下角托盘留图标。

## 装

需要有 [.NET 8 SDK](https://dotnet.microsoft.com/download)（装 Windows 那版，勾上 desktop 开发）。

```bat
build.bat
```

产出 `publish\HASticker.exe`，单文件，双击就跑。

> **别放 `C:\Program Files`** —— WebView2 需要可写目录放缓存。放 `D:\Tools\HASticker\` 之类。

想改代码调试：`run.bat`（源码启动）。命令行参数：
- `HASticker.exe --settings` 启动就弹设置框
- `HASticker.exe --reset` 恢复默认配置

## 用

1. 首次运行自动弹设置框 → 填 HA 仪表盘地址：
   ```
   http://homeassistant.local:8123/sticker?kiosk
   ```
2. 第一次会跳 HA 登录页，登录一次，之后永久自动登录（cookie 存在 `%LOCALAPPDATA%\HASticker\WebView2Data`）。
3. 开机自启：`Win+R` → `shell:startup` → 把 exe 的快捷方式放进去。

## 操作

| 操作 | 怎么弄 |
| --- | --- |
| 移动 | 拖顶部的拖动条 |
| 缩放 | 拖窗口边缘 |
| 菜单 | 拖动条上右键，或点托盘图标 |
| 显示 / 隐藏 | 双击托盘图标，或 `Ctrl + Alt + H` |

菜单里能改：贴法、透明度、缩放、圆角、锁定位置、是否显示拖动条、重新加载、清除登录状态、退出。

配置存在 `%APPDATA%\HASticker\config.json`，删掉就恢复默认。示例见 `sticker.config.example.json`。

## 贴法说明

| 模式 | 表现 |
| --- | --- |
| **desktop**（默认） | 给 `Progman` 发 `0x052C` 消息让 Explorer 生成 `WorkerW`，把窗口挂上去。Win+D 跟着出现、被程序正常遮挡、不进 Alt+Tab |
| **top** | 永远置顶 |
| **normal** | 普通窗口 |

桌面层模式下，如果资源管理器重启了，附着就失效——程序每 10 秒检测一次自动重新贴回，也可以手动菜单 → 「重新贴回桌面」。

## 常见问题

**提示要装 WebView2 Runtime**
Win11 一般自带；Win10 需要装：[WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)。

**贴纸不见了**
可能跑到屏幕外了（多显示器拔过）。`--reset` 重置，或删掉 `%APPDATA%\HASticker\config.json`。

**只能通过托盘退出**
贴纸不占任务栏，找右下角托盘的图标，右键 → 退出。

**圆角把网页切掉一块**
设置里把圆角调成 0，或把缩放调到 90%。

**HA 页面显示不全**
设置里调缩放（比如 80%），或者把贴纸窗口拖大一点。
