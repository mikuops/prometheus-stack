#!/usr/bin/env bash
# 一键安装：默认只监听 127.0.0.1（走 SSH 隧道）；加 --public <地址> 才对外开放 Grafana。
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

say() { printf '%s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
用法：./install.sh [选项]

  （不加选项）      只监听 127.0.0.1，用 SSH 隧道访问；最安全，也是默认行为
  --public <地址>   对外开放 Grafana：自动 TLS + 一层 Basic Auth
                    写域名：--public mon.example.com  需要 DNS 已解析、80/443 可访问
                    写端口：--public :8080            没有域名时用纯 HTTP（不加密）
  --no-sync         不安装 crontab 同步任务
                    （默认每分钟把 cmdb/services.json 渲染进 Prometheus file_sd）
  -y, --yes         不进入装完后的交互向导
  -h, --help        显示本帮助

邮箱配置在装完之后运行：bash scripts/configure-email.sh
新增监控网站在装完之后运行：python3 cmdb/setup_site.py --url https://example.com --name website-home
EOF
}

PUBLIC_MODE=0
PUBLIC_ADDR_ARG=""
WITH_SYNC=1
ASSUME_YES=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --public)
      [ "$#" -ge 2 ] || die "--public 需要一个地址，例如 --public mon.example.com 或 --public :8080"
      PUBLIC_MODE=1; PUBLIC_ADDR_ARG="$2"; shift 2 ;;
    --public=*) PUBLIC_MODE=1; PUBLIC_ADDR_ARG="${1#*=}"; shift ;;
    --no-sync) WITH_SYNC=0; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    *) die "不认识的参数：$1（用 --help 查看用法）" ;;
  esac
done

case "$(uname -s 2>/dev/null || true)" in
  Linux) : ;;
  *) die "只支持 Linux 宿主机；Windows 请用 WSL2，Mac/Windows 的 Docker Desktop 不支持 host 网络" ;;
esac

command -v docker >/dev/null || die "未安装 Docker"
if ! python3 -c 'import json' >/dev/null 2>&1; then
  die "未安装可用的 Python 3（用 python3 -c 'import json' 自查）"
fi
command -v curl >/dev/null || die "未安装 curl"

if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
elif command -v sudo >/dev/null && sudo docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker)
else
  die "当前用户无法访问 Docker daemon"
fi
"${DOCKER[@]}" compose version >/dev/null 2>&1 || die "未安装 Docker Compose CLI 插件"

# ---------- 公开访问模式的地址与端口 ----------
PUBLIC_ADDR=""
if [ "$PUBLIC_MODE" -eq 1 ]; then
  [ -n "$PUBLIC_ADDR_ARG" ] || die "--public 的地址不能为空"
  case "$PUBLIC_ADDR_ARG" in
    :*)
      PUBLIC_ADDR="$PUBLIC_ADDR_ARG"
      PUBLIC_PORT="${PUBLIC_ADDR_ARG#:}"
      case "$PUBLIC_PORT" in
        ''|*[!0-9]*) die "端口写法应形如 :8080" ;;
      esac
      say "公开模式：纯 HTTP，监听 ${PUBLIC_ADDR}（没有 TLS，密码会明文传输，仅适合临时演示）"
      ;;
    */*|*" "*)
      die "地址只能是域名（mon.example.com）或端口（:8080），不要带 http:// 和路径" ;;
    *)
      PUBLIC_ADDR="$PUBLIC_ADDR_ARG"
      case "$PUBLIC_ADDR" in
        *.*) : ;;
        *) die "看起来不像域名：$PUBLIC_ADDR（没有域名请用 --public :8080）" ;;
      esac
      say "公开模式：域名 ${PUBLIC_ADDR}，Caddy 会自动申请证书，需要 80/443 端口可访问且 DNS 已解析到本机"
      ;;
  esac
fi

# ---------- 端口预检：绝不覆盖别人的监听 ----------
# 重装或切换模式时，本项目自己的容器还占着 3000/9090/9093/9100/9115 是正常的，
# 不能因此拒绝；但这些端口如果被别的进程占着，仍然要拦下来。
ours_running=0
if [ -n "$("${DOCKER[@]}" compose ps -q 2>/dev/null || true)" ]; then
  ours_running=1
fi
caddy_running=0
if "${DOCKER[@]}" compose --profile public ps -q caddy 2>/dev/null | grep -q .; then
  caddy_running=1
fi
current_public_addr="$(sed -n 's/^PUBLIC_ADDR=//p' .env 2>/dev/null | tail -n1 || true)"

PORTS=()
if [ "$ours_running" -eq 0 ]; then
  PORTS+=(3000 9090 9093 9100 9115)
fi
if [ "$PUBLIC_MODE" -eq 1 ]; then
  if [ -n "${PUBLIC_PORT:-}" ]; then
    if [ "$caddy_running" -eq 1 ] && [ "$PUBLIC_ADDR" = "$current_public_addr" ]; then
      say "对外入口已经是 ${PUBLIC_ADDR}，其端口由本项目的 caddy 占用，跳过该端口检查"
    else
      PORTS+=("$PUBLIC_PORT")
    fi
  elif [ "$(id -u)" -eq 0 ]; then
    if [ "$caddy_running" -eq 1 ] && [ "$PUBLIC_ADDR" = "$current_public_addr" ]; then
      say "对外入口已经是 https://${PUBLIC_ADDR}，80/443 由本项目的 caddy 占用，跳过检查"
    else
      PORTS+=(80 443)
    fi
  else
    say "提示：当前不是 root，跳过 80/443 预检，请自行确认这两个端口空闲"
  fi
fi
if [ "$ours_running" -eq 1 ]; then
  say "检测到本项目容器仍在运行：跳过 3000/9090/9093/9100/9115 的预检"
fi

if [ "${#PORTS[@]}" -gt 0 ]; then
python3 - "${PORTS[@]}" <<'PY' || die "端口已占用；本安装器只适用于空闲主机。已有监控请看 docs/EXISTING_STACK.md"
import socket
import sys

busy = []
for raw in sys.argv[1:]:
    port = int(raw)
    with socket.socket() as sock:
        # 上一次运行留下的 TIME_WAIT 连接不应阻止重装；仍有进程在监听时 bind 依旧失败。
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            busy.append(port)
if busy:
    print("已占用的端口：", ", ".join(map(str, busy)))
    raise SystemExit(1)
PY
fi

# ---------- .env 读写 ----------
env_set() {
  python3 - "$1" "$2" <<'PY'
import sys

key, value = sys.argv[1], sys.argv[2]
lines, found = [], False
try:
    with open(".env", encoding="utf-8") as handle:
        for line in handle.read().splitlines():
            if line.startswith(key + "="):
                if not found:
                    lines.append(f"{key}={value}")
                    found = True
                continue
            lines.append(line)
except FileNotFoundError:
    pass
if not found:
    lines.append(f"{key}={value}")
with open(".env", "w", encoding="utf-8") as handle:
    handle.write("\n".join(lines) + "\n")
PY
}
env_get() { sed -n "s/^$1=//p" .env 2>/dev/null | tail -n 1; }

umask 077
if [ ! -f .env ]; then
  if command -v openssl >/dev/null; then
    password="$(openssl rand -hex 16)"
  else
    password="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
  fi
  env_set GRAFANA_PASSWORD "$password"
  say "已生成 .env；管理员密码保存在该文件中，不在终端打印"
fi
chmod 600 .env
grep -Eq '^GRAFANA_PASSWORD=.{12,}$' .env || die ".env 中需要至少 12 个字符的 GRAFANA_PASSWORD"

if [ "$PUBLIC_MODE" -eq 1 ]; then
  if [ -n "${PUBLIC_PORT:-}" ]; then
    :
  fi
  env_set PUBLIC_ADDR "$PUBLIC_ADDR"
  env_set BASIC_AUTH_USER "${BASIC_AUTH_USER:-admin}"
  auth_password="$(env_get CADDY_AUTH_PASSWORD)"
  if [ "${#auth_password}" -lt 12 ]; then
    auth_password="$(python3 -c 'import secrets; print(secrets.token_urlsafe(18))')"
    env_set CADDY_AUTH_PASSWORD "$auth_password"
  fi
  say "正在用 caddy 容器生成 Basic Auth 密码哈希（首次会拉取镜像，请稍候）"
  auth_hash="$("${DOCKER[@]}" run --rm caddy:2.10.0 caddy hash-password --plaintext "$auth_password" 2>/dev/null | tr -d '\r\n')" \
    || die "生成密码哈希失败；请确认可以 pull caddy:2.10.0"
  case "$auth_hash" in
    '$2'*) : ;;
    *) die "生成密码哈希失败，输出不是 bcrypt："$'\n'"$auth_hash" ;;
  esac
  # bcrypt 哈希里带 $，.env 里不引用就会补 Compose 当成变量插值（$2a$14 被截断），
  # 单引号让 Compose 原样读取。
  env_set CADDY_BASIC_AUTH "'$auth_hash'"
  env_set GF_AUTH_ANONYMOUS_ENABLED true
  env_set COMPOSE_PROFILES public
  say "已写入 .env：PUBLIC_ADDR / CADDY_BASIC_AUTH / COMPOSE_PROFILES=public"
else
  env_set GF_AUTH_ANONYMOUS_ENABLED false
  env_set COMPOSE_PROFILES ""
fi
chmod 600 .env

# ---------- 目录、配置、清单 ----------
mkdir -p alertmanager/secrets prometheus/targets
chmod 755 alertmanager alertmanager/secrets prometheus prometheus/rules prometheus/targets
chmod +x scripts/*.sh install.sh uninstall.sh
if [ ! -f alertmanager/alertmanager.yml ]; then
  cp alertmanager/no-notify.yml.example alertmanager/alertmanager.yml
  chmod 644 alertmanager/alertmanager.yml
  say "已创建无通知接收器；邮件需单独配置并验收"
fi

if [ ! -f cmdb/services.json ]; then
  cp cmdb/services.json.example cmdb/services.json
  chmod 600 cmdb/services.json
fi
python3 cmdb/render_targets.py || die "服务清单无效，未启动容器"

# 上次用 --public 装过、这次改回默认：caddy 不在默认 profile 里，
# 只跑 up -d 不会停它，必须显式移除，否则对外入口会一直留着。
if [ "$PUBLIC_MODE" -eq 0 ]; then
  if "${DOCKER[@]}" compose --profile public ps -q caddy 2>/dev/null | grep -q .; then
    say "检测到上次以公开模式安装：正在停止并移除对外入口 caddy"
    "${DOCKER[@]}" compose --profile public rm -sf caddy >/dev/null 2>&1 || true
  fi
fi

"${DOCKER[@]}" compose config -q || die "Compose 配置无效，未启动容器"

"${DOCKER[@]}" compose up -d

wait_http() { # url, name, attempts（每次 2 秒）
  local url="$1" name="$2" attempts="${3:-60}" i=0
  while [ "$i" -lt "$attempts" ]; do
    if curl -fsS -o /dev/null --max-time 2 "$url" 2>/dev/null; then
      say "  ${name} 已就绪"
      return 0
    fi
    i=$((i + 1))
    sleep 2
  done
  return 1
}

say "等待服务就绪（Grafana 首次启动会安装内置插件，通常要 20 秒左右）……"
wait_http http://127.0.0.1:9090/-/ready Prometheus 60 \
  || die "Prometheus 未在 120 秒内就绪；运行 docker compose logs --tail=50 prometheus 排查"
wait_http http://127.0.0.1:3000/api/health Grafana 60 \
  || die "Grafana 未在 120 秒内就绪；运行 docker compose logs --tail=50 grafana 排查"
wait_http http://127.0.0.1:9093/-/healthy Alertmanager 60 \
  || die "Alertmanager 未在 120 秒内就绪；运行 docker compose logs --tail=50 alertmanager 排查"

if [ "$PUBLIC_MODE" -eq 1 ]; then
  if [ -n "${PUBLIC_PORT:-}" ]; then
    public_url="http://127.0.0.1:${PUBLIC_PORT}/"
  else
    public_url="https://127.0.0.1/"
  fi
  public_ready=0
  for _ in $(seq 1 30); do
    code="$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 3 \
      -H "Host: ${PUBLIC_ADDR}" "$public_url" 2>/dev/null || true)"
    # 401 说明 Caddy 已起来且 Basic Auth 生效，正是期望结果
    case "$code" in 200|301|302|401) public_ready=1; break ;; esac
    sleep 2
  done
  if [ "$public_ready" -eq 1 ]; then
    say "  对外入口已响应（HTTP ${code}）"
  else
    say "提示：对外入口暂时没有响应；域名模式的首张证书可能要几十秒，稍后重试 curl -I ${public_url} -H 'Host: ${PUBLIC_ADDR}'"
  fi
fi

# ---------- 清单变更自动同步（crontab，幂等） ----------
SYNC_MARK="# prometheus-stack:sync"
if [ "$WITH_SYNC" -eq 1 ]; then
  if command -v crontab >/dev/null; then
    sync_line="* * * * * cd '$(pwd -P)' && python3 cmdb/render_targets.py 2>&1 | grep -v 'http-probe=无变化 node=无变化' >>cmdb/render.log $SYNC_MARK"
    ( crontab -l 2>/dev/null | grep -vF "$SYNC_MARK" || true
      printf '%s\n' "$sync_line" ) | crontab - || say "写入 crontab 失败，跳过自动同步"
    say "已安装 crontab 同步：改完 cmdb/services.json，最多 1 分钟自动进 Prometheus"
  else
    say "未找到 crontab，跳过自动同步；改完清单请手动运行 python3 cmdb/render_targets.py"
  fi
fi

# ---------- 装完向导 ----------
if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
  ask() {
    local answer
    printf '%s [y/N] ' "$1"
    read -r answer || true
    case "${answer:-}" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
  }
  say ""
  if ask "现在就加一个要监控的网站吗？"; then
    python3 cmdb/setup_site.py || say "网站未添加；之后可用 python3 cmdb/setup_site.py --url ... --name ... 补上"
  fi
  if ask "现在就配置邮件告警吗？"; then
    bash scripts/configure-email.sh || say "邮件未配置；之后可用 bash scripts/configure-email.sh 补上"
  fi
fi

# ---------- 收尾提示 ----------
say ""
if [ "$PUBLIC_MODE" -eq 1 ]; then
  if [ -n "${PUBLIC_PORT:-}" ]; then
    say "打开地址：http://<本机公网IP>:${PUBLIC_PORT}"
  else
    say "打开地址：https://${PUBLIC_ADDR}"
    say "打不开时依次检查：DNS 是否解析到本机、云安全组/防火墙是否放行 80 和 443"
  fi
  say "登录用户：$(env_get BASIC_AUTH_USER)    密码：见本机 .env 的 CADDY_AUTH_PASSWORD 一项"
  say "公开模式下 Grafana 是只读匿名访问；管理员仍可用 admin + GRAFANA_PASSWORD 登录"
  say "只想给自己看时，重新运行 ./install.sh（不带 --public）：会移除 caddy，对外入口随即关闭"
else
  say "Prometheus 已就绪；Grafana: http://127.0.0.1:3000"
  say "管理员密码只保存在本机 .env；请勿把该文件或截图上传 GitHub"
  say "界面只监听回环：先运行 bash scripts/tunnel.sh 建 SSH 隧道，再打开上面的地址"
  say "需要让别人也能打开时：sudo ./install.sh --public monitor.example.com"
fi
