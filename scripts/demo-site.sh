#!/usr/bin/env bash
# 本地演示站点：用于验证 HTTP 探测与 ServiceProbeFailed 告警，不要指向真实业务站点。
# 用法：bash scripts/demo-site.sh start|stop|status
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

PORT=${DEMO_SITE_PORT:-18080}
DIR=${DEMO_SITE_DIR:-/tmp/prometheus-stack-demo-site}
PIDFILE="$DIR/server.pid"

is_running() {
  [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

start() {
  if is_running; then
    printf '演示站点已在运行：http://127.0.0.1:%s/\n' "$PORT"
    return 0
  fi
  command -v python3 >/dev/null 2>&1 || { printf '错误：未安装 Python 3\n' >&2; exit 1; }
  mkdir -p "$DIR"
  cat > "$DIR/index.html" <<'HTML'
<!doctype html>
<html lang="zh-CN">
<meta charset="utf-8">
<title>prometheus-stack 演示站点</title>
<h1>prometheus-stack 演示站点</h1>
<p>这个页面由 scripts/demo-site.sh 启动，用于验证 HTTP 探测和告警恢复。</p>
HTML
  nohup python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$DIR" >"$DIR/server.log" 2>&1 &
  printf '%s\n' "$!" > "$PIDFILE"
  for _ in 1 2 3 4 5; do
    if curl -fsS "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
      printf '演示站点已启动：http://127.0.0.1:%s/\n' "$PORT"
      printf '请把 cmdb/services.json 里 website-home 的 url 设为 http://127.0.0.1:%s/\n' "$PORT"
      return 0
    fi
    sleep 0.5
  done
  printf '演示站点启动失败，查看 %s\n' "$DIR/server.log" >&2
  exit 1
}

stop() {
  if ! is_running; then
    printf '演示站点未运行\n'
    rm -f "$PIDFILE"
    return 0
  fi
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
  printf '演示站点已停止\n'
}

status() {
  if is_running; then
    printf '运行中：http://127.0.0.1:%s/ (pid %s)\n' "$PORT" "$(cat "$PIDFILE")"
  else
    printf '未运行\n'
  fi
}

case "${1:-status}" in
  start) start ;;
  stop) stop ;;
  status) status ;;
  *) printf '用法：bash scripts/demo-site.sh start|stop|status\n' >&2; exit 2 ;;
esac
