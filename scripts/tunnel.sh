#!/usr/bin/env bash
# 打印一条可直接粘贴的 SSH 隧道命令（在**你自己的电脑**上执行，不是在服务器上）
# 用法：./scripts/tunnel.sh [用户@主机]     不传就自动猜公网 IP
set -euo pipefail

TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  IP="$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  [ -n "$IP" ] || IP="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  [ -n "$IP" ] || IP="<你的服务器公网IP>"
  TARGET="$(id -un)@$IP"
fi

cat <<EOF

在你自己电脑的终端（Windows 的 cmd / PowerShell 都可以）执行：

  ssh -N -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 -L 9093:127.0.0.1:9093 $TARGET

执行后窗口没有输出、光标停住，就说明隧道建立成功，别关。
然后浏览器访问：

  Grafana        http://127.0.0.1:3000
  Prometheus     http://127.0.0.1:9090
  Alertmanager   http://127.0.0.1:9093

用完按 Ctrl+C 关闭隧道。

说明：所有服务都只监听服务器本机（127.0.0.1），所以公网直连是连不上的，
隧道等于把这几个端口"搬"到你电脑上，不需要碰安全组，也不向公网暴露。

如果只想看数据、不想开浏览器：在服务器上跑 ./scripts/check.sh 或 ./scripts/board.sh。
EOF
