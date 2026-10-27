#!/usr/bin/env python3
"""Add or update one HTTP website target without editing Prometheus YAML."""

import argparse
import json
import os
import re
import shutil
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from urllib.parse import urlsplit

import render_targets


MANIFEST = Path(__file__).resolve().parent / "services.json"


def valid_url(value: str) -> bool:
    if value != value.strip() or any(c.isspace() for c in value):
        return False
    try:
        parsed = urlsplit(value)
        return (
            parsed.scheme in ("http", "https")
            and bool(parsed.hostname)
            and parsed.port != 0
            and parsed.username is None
            and parsed.password is None
            and not parsed.query
            and not parsed.fragment
        )
    except ValueError:
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description="配置一个网站 HTTP 探测目标")
    parser.add_argument("--url", help="从探测器所在服务器能访问的 http(s) 地址")
    parser.add_argument("--name", default="website-home", help="服务名称，默认 website-home")
    args = parser.parse_args()
    url = args.url or input("网站 URL（从监控服务器访问）：").strip()
    name = args.name.strip()

    if not re.fullmatch(r"[A-Za-z0-9._-]{1,64}", name):
        print("服务名称只允许字母、数字、点、下划线和短横线", file=sys.stderr)
        return 1
    if not valid_url(url):
        print("URL 必须是无凭据、无查询参数的完整 http(s) 地址", file=sys.stderr)
        return 1
    if not MANIFEST.exists():
        print("没有 cmdb/services.json；请先运行 install.sh", file=sys.stderr)
        return 1

    try:
        document = json.loads(MANIFEST.read_text(encoding="utf-8"))
        services = document["services"]
        hosts = document["hosts"]
        if not isinstance(services, list) or not isinstance(hosts, list):
            raise ValueError("services 和 hosts 必须是数组")
        existing = next((item for item in services if isinstance(item, dict) and item.get("name") == name), None)
        if existing is None:
            services.append({"name": name, "url": url, "env": "prod", "team": "web"})
        else:
            existing["url"] = url
            existing["enabled"] = True
            existing.pop("note", None)
        errors = render_targets.validate(services, hosts)
        if errors:
            raise ValueError("; ".join(errors))
    except (AttributeError, KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        print(f"服务清单无效，未写入：{error}", file=sys.stderr)
        return 1

    backup = MANIFEST.with_name(
        f"services.json.bak-{datetime.now().strftime('%Y%m%d-%H%M%S-%f')}"
    )
    shutil.copy2(MANIFEST, backup)
    fd, temporary = tempfile.mkstemp(dir=str(MANIFEST.parent), prefix=".services-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            json.dump(document, output, ensure_ascii=False, indent=2)
            output.write("\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, MANIFEST)
        if render_targets.main() != 0:
            shutil.copy2(backup, MANIFEST)
            print("目标渲染失败，已恢复旧清单", file=sys.stderr)
            return 1
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

    print(f"已启用 {name}: {url}")
    print("约 30 秒后查询 Prometheus 的 probe_success{job=\"http-probe\"}；旧清单备份：" + str(backup))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
