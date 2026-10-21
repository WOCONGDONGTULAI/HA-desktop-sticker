#!/usr/bin/env python3
"""自动在 Home Assistant 上建一个贴纸专用仪表盘。

用法：
    pip install websocket-client
    python3 create_sticker_dashboard.py --url http://192.168.5.18:8123 --token <长期访问令牌>

长期访问令牌：HA → 点左下角头像 → 安全 → 长期访问令牌 → 创建令牌

为什么不用 REST：新版 HA（2026.x）不再注册 /api/lovelace/* 这些 REST 端点，
只有 WebSocket API 能用，所以这里走 ws。

⚠️ 两个坑（都踩过）：
  1. 仪表盘 url_path 必须含连字符 -，写 sticker 会被拒：invalid_format
  2. WebSocket 的 id 必须递增，重复用同一个 id 会报 id_reuse
"""

import argparse
import json
import sys

try:
    import websocket
except ImportError:
    sys.exit("缺少依赖：pip install websocket-client")


def build_config():
    """贴纸仪表盘内容：大按钮开关 + 空调 + 净化器 + 环境数据。
    换掉这些 entity 就能适配你自己的设备。"""

    def btn(name, icon, entity):
        return {"type": "button", "name": name, "icon": icon,
                "tap_action": {"action": "toggle"}, "entity": entity}

    return {
        "title": "贴纸",
        "views": [{
            "title": "贴纸", "path": "main", "icon": "mdi:sticker", "panel": True,
            "cards": [
                {"type": "grid", "columns": 2, "square": False, "cards": [
                    btn("电暖器", "mdi:radiator", "switch.yutai_fsov7m_9a4f_switch"),
                    btn("热水器", "mdi:water-boiler", "switch.yutai_fsov7m_5ac9_switch"),
                    btn("电脑", "mdi:desktop-tower-monitor", "switch.pzg_0002_069f_switch"),
                    btn("牌匾灯", "mdi:led-strip-variant", "switch.cuco_v3_3d3f_switch"),
                    btn("充电器", "mdi:battery-charging", "switch.yutai_fsov7m_778d_switch"),
                    btn("闪光灯", "mdi:camera-flash", "switch.yutai_fsov7m_6938_switch"),
                ]},
                {"type": "entities", "title": "阁楼空调", "show_header_toggle": False,
                 "entities": [
                     {"entity": "climate.ge_lou_wen_kong", "name": "温控"},
                     {"entity": "input_boolean.kong_diao_zong_kong_kai_guan", "name": "空调总控"},
                 ]},
                {"type": "entities", "title": "空气净化器", "show_header_toggle": False,
                 "entities": [
                     {"entity": "fan.zhimi_rma3_94e5_air_purifier", "name": "净化器开关"},
                     {"entity": "sensor.zhimi_rma3_94e5_pm25_density", "name": "PM2.5"},
                 ]},
                {"type": "glance", "title": "家里现在", "show_state": True, "columns": 3,
                 "entities": [
                     {"entity": "sensor.miaomiaoce_t2_568c_temperature", "name": "温度"},
                     {"entity": "sensor.miaomiaoce_t2_568c_relative_humidity", "name": "湿度"},
                     {"entity": "weather.forecast_wo_de_jia", "name": "天气"},
                 ]},
                {"type": "glance", "title": "谁在家", "show_state": True, "columns": 2,
                 "entities": [
                     {"entity": "person.min", "name": "MIN"},
                     {"entity": "device_tracker.xiao_min_de_iphone_15", "name": "iPhone 15"},
                 ]},
            ]}],
    }


class HA:
    def __init__(self, url, token):
        self.ws_url = url.replace("http://", "ws://").replace("https://", "wss://") + "/api/websocket"
        self.token = token
        self._id = 0

    def __enter__(self):
        self.ws = websocket.create_connection(self.ws_url, timeout=20)
        self.ws.recv()
        self.ws.send(json.dumps({"type": "auth", "access_token": self.token}))
        msg = json.loads(self.ws.recv())
        if msg.get("type") != "auth_ok":
            sys.exit("认证失败，检查令牌：" + str(msg))
        return self

    def __exit__(self, *a):
        self.ws.close()

    def call(self, cmd, **extra):
        self._id += 1
        self.ws.send(json.dumps({"id": self._id, "type": cmd, **extra}))
        while True:
            m = json.loads(self.ws.recv())
            if m.get("type") == "result" and m.get("id") == self._id:
                return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://192.168.5.18:8123", help="HA 地址")
    ap.add_argument("--token", required=True, help="长期访问令牌")
    ap.add_argument("--path", default="ha-sticker", help="仪表盘 URL 路径（必须带 -）")
    ap.add_argument("--title", default="贴纸")
    args = ap.parse_args()

    if "-" not in args.path:
        sys.exit(f"路径必须含连字符，'{args.path}' 会被 HA 拒掉。用 ha-sticker 之类。")

    with HA(args.url, args.token) as ha:
        dash = ha.call("lovelace/dashboards/list")["result"]
        print("现有仪表盘:", [(d["url_path"], d["title"]) for d in dash])

        if any(d["url_path"] == args.path for d in dash):
            print(f"'{args.path}' 已存在，直接覆盖配置")
        else:
            r = ha.call("lovelace/dashboards/create", url_path=args.path, title=args.title,
                        icon="mdi:sticker", require_admin=False, show_in_sidebar=True,
                        mode="storage")
            if not r.get("success"):
                sys.exit("创建失败：" + json.dumps(r.get("error"), ensure_ascii=False))
            print("创建成功:", r["result"]["url_path"])

        r = ha.call("lovelace/config/save", url_path=args.path, config=build_config())
        if not r.get("success"):
            sys.exit("保存配置失败：" + json.dumps(r.get("error"), ensure_ascii=False))

    print(f"\n完成。贴纸里填这个地址：\n  {args.url}/{args.path}?kiosk")


if __name__ == "__main__":
    main()
