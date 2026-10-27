#!/usr/bin/env python3
"""服务清单 → Prometheus file_sd 目标文件。

cmdb/services.json 是唯一真相：新增 / 下线服务只改它，cron 每分钟渲染一次，
Prometheus 通过 file_sd 自动发现，不需要改主配置或 reload。

安全策略：渲染前校验字段与重名，校验失败直接退出并**保留上一份可用文件**，
避免错误清单把监控打空。

用法：
    python3 cmdb/render_targets.py
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
SERVICES = BASE / "cmdb" / "services.json"
TARGET_DIR = BASE / "prometheus" / "targets"
PROBE_FILE = TARGET_DIR / "http-probe.json"
NODE_FILE = TARGET_DIR / "node.json"
DEFAULT_MODULE = "http_2xx"
DEFAULT_NODE_PORT = 9100


def load() -> tuple[list, list]:
    with SERVICES.open(encoding="utf-8") as fh:
        doc = json.load(fh)
    return doc.get("services", []), doc.get("hosts", [])


def host_address(host: dict) -> str:
    """取主机地址；兼容 address / target / host / ip 几种写法，且允许带端口。"""
    return str(host.get("address") or host.get("target") or host.get("host") or host.get("ip") or "")


def host_target(host: dict) -> str:
    """渲染成 host:port；地址里已经带端口就原样返回。"""
    addr = host_address(host)
    if ":" in addr:
        return addr
    return f"{addr}:{host.get('port', DEFAULT_NODE_PORT)}"


def validate(services: list, hosts: list) -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()

    for idx, svc in enumerate(services):
        name = svc.get("name")
        if not name:
            errors.append(f"services[{idx}] 缺少 name")
        elif name in seen:
            errors.append(f"services[{idx}] name 重复：{name}")
        else:
            seen.add(name)

        url = svc.get("url", "")
        if not url.startswith(("http://", "https://")):
            errors.append(f"services[{idx}] url 必须以 http:// 或 https:// 开头：{url!r}")

    host_names: set[str] = set()
    for idx, host in enumerate(hosts):
        name = host.get("name")
        if not name:
            errors.append(f"hosts[{idx}] 缺少 name")
        elif name in host_names:
            errors.append(f"hosts[{idx}] name 重复：{name}")
        else:
            host_names.add(name)

        if not host_address(host):
            errors.append(f"hosts[{idx}] 缺少 address（也可写 target / host / ip）")

    return errors


def build(services: list, hosts: list) -> tuple[list, list]:
    probe = [
        {
            "targets": [svc["url"]],
            "labels": {
                "service": svc["name"],
                "env": svc.get("env", "prod"),
                "team": svc.get("team", "web"),
                "module": svc.get("module", DEFAULT_MODULE),
            },
        }
        for svc in services
        if svc.get("enabled", True)
    ]
    nodes = [
        {
            "targets": [host_target(host)],
            "labels": {
                "instance": host["name"],
                "env": host.get("env", "prod"),
                "role": host.get("role", "server"),
            },
        }
        for host in hosts
        if host.get("enabled", True)
    ]
    return probe, nodes


def write_if_changed(path: Path, payload: list) -> bool:
    """内容有变化才写；先写临时文件再原子替换，避免 Prometheus 读到半个文件。"""
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    if path.exists() and path.read_text(encoding="utf-8") == text:
        return False

    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".tmp-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    return True


def main() -> int:
    if not SERVICES.exists():
        print(f"缺少 {SERVICES}，请先复制 services.json.example", file=sys.stderr)
        return 2

    services, hosts = load()
    errors = validate(services, hosts)
    if errors:
        print("清单校验失败，保留上一份可用目标文件：", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    probe, nodes = build(services, hosts)
    probe_changed = write_if_changed(PROBE_FILE, probe)
    node_changed = write_if_changed(NODE_FILE, nodes)

    print(
        f"服务 {len(probe)}/{len(services)} 主机 {len(nodes)}/{len(hosts)} "
        f"http-probe={'已更新' if probe_changed else '无变化'} "
        f"node={'已更新' if node_changed else '无变化'}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
