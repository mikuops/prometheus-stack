#!/usr/bin/env bash
# 一分钟巡检：目标 / 规则 / 告警 / 渲染
# 用法：./scripts/check.sh
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
P=${PROM:-http://127.0.0.1:9090}
A=${AM:-http://127.0.0.1:9093}

echo "=== $(date '+%F %T %Z') ==="

echo "[采集目标]"
curl -s "$P/api/v1/targets" | python3 -c "
import sys, json
try:
    ts = json.load(sys.stdin)['data']['activeTargets']
except Exception:
    print('  (Prometheus 不可达)'); raise SystemExit
for t in sorted(ts, key=lambda x: (x['labels'].get('job',''), x['labels'].get('service',''))):
    name = t['labels'].get('service') or t['labels'].get('instance','')
    print(f\"  {t['health']:<8} {t['labels'].get('job',''):<12} {name}\")
" 2>/dev/null

echo "[规则]"
curl -s "$P/api/v1/rules" | python3 -c "
import sys, json
try:
    gs = json.load(sys.stdin)['data']['groups']
except Exception:
    print('  (不可达)'); raise SystemExit
print(f\"  {len(gs)} 组 / {sum(len(g['rules']) for g in gs)} 条\")
" 2>/dev/null

echo "[正在触发]"
curl -s "$P/api/v1/alerts" | python3 -c "
import sys, json
try:
    als = json.load(sys.stdin)['data']['alerts']
except Exception:
    print('  (不可达)'); raise SystemExit
if not als:
    print('  无')
for a in als:
    print(f\"  {a['state']:<8} {a['labels'].get('alertname','')} {a['labels'].get('service','')}\")
" 2>/dev/null

echo "[Alertmanager]"
curl -s "$A/api/v2/alerts" 2>/dev/null | python3 -c "
import sys, json
print(f\"  在线告警 {len(json.load(sys.stdin))} 条\")" 2>/dev/null || echo "  不可达"

echo "[清单渲染]"
tail -1 cmdb/render.log 2>/dev/null || echo "  无日志"
