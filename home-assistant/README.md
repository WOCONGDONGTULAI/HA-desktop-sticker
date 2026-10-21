# HA 端：做一个贴纸专用仪表盘

贴纸窗口很小（默认 320×480），所以别拿你平时那个大仪表盘往里塞，专门做一个。

## 0. 最省事：脚本自动建

```bash
pip install websocket-client
python3 create_sticker_dashboard.py --url http://192.168.5.18:8123 --token <长期访问令牌>
```

长期访问令牌：HA → 左下角头像 → 安全 → 长期访问令牌 → 创建令牌。
脚本会建好 `ha-sticker` 仪表盘并写入配置，最后打印贴纸该填的地址。

## 1. 手动新建仪表盘

`设置 → 仪表盘 → 右下角「新增仪表盘」`

- 标题：`贴纸`
- URL 路径：`ha-sticker`
- 图标：随便
- 仅管理员可见：看你需不需要

> ⚠️ **URL 路径必须含连字符 `-`**。新版 HA（2026.x）会拒绝纯字母路径：
> `invalid_format: Url path needs to contain a hyphen (-)`。
> 写成 `sticker` 的结果是仪表盘建不出来、访问一直 404 —— 这个坑很隐蔽。
> 所以这里用 `ha-sticker`，贴纸地址就是 `/ha-sticker?kiosk`。

## 2. 贴内容

新建完是个空盘，右上角三个点 → `编辑仪表盘` → 三个点 → `原始配置编辑器`，
把 `dashboard-sticker.yaml` 整段粘进去覆盖，把实体 id 换成你自己的。

找实体 id：`开发者工具 → 状态` 里搜，复制 `entity_id`。

## 3. 排版建议（贴纸窗口窄，这几条很关键）

| 要点 | 做法 |
| --- | --- |
| 只用一列 | 不要分多 view，全堆在一屏里，宽度按 2 列 grid 走 |
| 按钮要能点中 | 用 `button` 卡片配 `tap_action: toggle`，别用 `entities`（行太矮、滑条难点） |
| 数字要一眼看清 | `glance` / `tile` 卡片，别用图表（图表在小窗里糊成一团） |
| 别放要输入的 | 贴纸就做「看 + 点」，要输入的回 HA 主界面 |
| 配色跟贴纸一致 | 贴纸是圆角小窗，HA 深色主题更搭（`点击头像 → 主题 → Dark`） |

## 4. 隐藏侧边栏和顶栏（kiosk）

默认进去左边一条侧边栏、上面一条标题栏，很占地方。在地址后加 `?kiosk`：

```
http://homeassistant.local:8123/ha-sticker?kiosk
```

贴纸里填地址时直接带上这个参数就行。

> 想更彻底（连右上角三个点都去掉）可以装 HACS 前端插件 `kiosk-mode`，
> 但 `?kiosk` 是官方自带的，够用了。

## 5. 关于登录

贴纸是一个持久化的浏览器容器，所以：

- 第一次打开会跳 HA 登录页，登录一次
- cookie 长期保存，之后打开直接进
- 想换账号 / 登出：贴纸右键 → 清除登录状态（Windows）/ 重新加载并登录（macOS）

## 6. 常用地址形式

| 场景 | 地址 |
| --- | --- |
| 本地域名 | `http://homeassistant.local:8123/ha-sticker?kiosk` |
| 内网 IP | `http://192.168.1.50:8123/ha-sticker?kiosk` |
| 有公网 + HTTPS | `https://ha.example.com/ha-sticker?kiosk` |
| 某个子视图 | `http://homeassistant.local:8123/sticker/lights?kiosk` |
