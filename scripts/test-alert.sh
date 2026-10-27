#!/usr/bin/env bash
# Tests Alertmanager email delivery. This does not simulate a website outage.
set -euo pipefail

curl -fsS --max-time 10 -X POST http://127.0.0.1:9093/api/v2/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels":{"alertname":"ManualMailTest","severity":"info","service":"mail-test"},"annotations":{"summary":"手动测试邮件通知"}}]'
printf '\n测试告警已提交。约 30–60 秒后检查收件箱；这只验证通知链路。\n'
