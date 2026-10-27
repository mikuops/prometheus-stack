#!/usr/bin/env bash
# 终端数值面板：CPU / 内存 / 磁盘 / 站点可用性 / 探测耗时
# 用法：./scripts/board.sh
P=${PROM:-http://127.0.0.1:9090}

q() {
  curl -s --get "$P/api/v1/query" --data-urlencode "query=$1" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)['data']['result']
except Exception:
    print('  (不可达)'); raise SystemExit
if not d:
    print('  (无数据)'); raise SystemExit
for r in d:
    name = (r['metric'].get('instance') or r['metric'].get('service')
            or r['metric'].get('mountpoint') or '')
    print(f\"  {name:<30} {float(r['value'][1]):.1f}\")
" 2>/dev/null
}

echo "=== $(date '+%F %T %Z') ==="
echo "[CPU 使用率 %]";      q '100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m]))*100)'
echo "[内存使用率 %]";      q '(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100'
echo "[磁盘使用率 %]";      q '(1 - (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs|nsfs"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay|squashfs|nsfs"})) * 100'
echo "[站点可用性 1=通]";   q 'probe_success{job="http-probe"}'
echo "[探测耗时 s]";        q 'probe_duration_seconds{job="http-probe"}'
