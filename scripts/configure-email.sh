#!/usr/bin/env bash
# Interactive SMTP configuration. Never pass an authorization code as an argument.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

die() { printf '错误：%s\n' "$*" >&2; exit 1; }
[ -t 0 ] || die "请在交互式终端运行，不能通过管道输入授权码"
command -v docker >/dev/null || die "未安装 Docker"
if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
elif command -v sudo >/dev/null && sudo docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker)
else
  die "当前用户无法访问 Docker daemon"
fi
if [ "$(id -u)" -eq 0 ]; then
  SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
else
  die "需要 root 或 sudo 才能设置 alertmanager.yml 与授权码文件的权限"
fi
"${DOCKER[@]}" compose version >/dev/null 2>&1 || die "未安装 Docker Compose CLI 插件"
[ -f alertmanager/alertmanager.yml ] || die "请先运行 install.sh"
[ -n "$("${DOCKER[@]}" compose ps -q alertmanager)" ] || die "本项目 Alertmanager 容器未运行，先完成安装"

read -r -p 'SMTP 发件邮箱：' sender
[[ "$sender" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || die "发件邮箱格式无效"
read -r -p "收件邮箱 [$sender]：" recipient
recipient="${recipient:-$sender}"
[[ "$recipient" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || die "收件邮箱格式无效"
read -r -p 'SMTP 主机 [smtp.163.com]：' smtp_host
smtp_host="${smtp_host:-smtp.163.com}"
[[ "$smtp_host" =~ ^[A-Za-z0-9.-]+$ ]] || die "SMTP 主机格式无效"
read -r -p 'SMTP 端口 [465]：' smtp_port
smtp_port="${smtp_port:-465}"
[[ "$smtp_port" =~ ^[0-9]{1,5}$ ]] && [ "$smtp_port" -ge 1 ] && [ "$smtp_port" -le 65535 ] || die "SMTP 端口无效"
read -r -s -p 'SMTP 客户端授权码（输入时不显示）：' smtp_code
printf '\n'
[ -n "$smtp_code" ] || die "授权码不能为空"

mkdir -p alertmanager/secrets
chmod 755 alertmanager/secrets
backup="alertmanager/alertmanager.yml.bak-$(date +%Y%m%d-%H%M%S)"
"${SUDO[@]}" cp -a alertmanager/alertmanager.yml "$backup"

# The code travels on stdin, not in shell history or process arguments.
printf '%s' "$smtp_code" | "${SUDO[@]}" sh -c 'umask 077; cat > alertmanager/secrets/smtp_password'
unset smtp_code
"${SUDO[@]}" chown root:65534 alertmanager/secrets/smtp_password
"${SUDO[@]}" chmod 0640 alertmanager/secrets/smtp_password

"${SUDO[@]}" tee alertmanager/alertmanager.yml >/dev/null <<YAML
global:
  resolve_timeout: 5m
route:
  receiver: mail
  group_by: ['alertname', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
receivers:
  - name: mail
    email_configs:
      - to: '$recipient'
        from: '$sender'
        smarthost: '$smtp_host:$smtp_port'
        auth_username: '$sender'
        auth_password_file: /etc/alertmanager/secrets/smtp_password
        require_tls: true
        send_resolved: true
YAML
"${SUDO[@]}" chmod 0644 alertmanager/alertmanager.yml

if ! "${DOCKER[@]}" run --rm --network none \
  -v "$PWD/alertmanager:/etc/alertmanager:ro" \
  --entrypoint amtool prom/alertmanager:v0.34.1 \
  check-config /etc/alertmanager/alertmanager.yml; then
  "${SUDO[@]}" cp -a "$backup" alertmanager/alertmanager.yml
  die "配置校验失败；已恢复旧配置，Alertmanager 未重启"
fi

"${DOCKER[@]}" compose up -d --no-deps --force-recreate alertmanager
printf '配置已加载。请检查容器状态，并运行 scripts/test-alert.sh 验证邮件送达。\n'
printf '回退配置备份：%s\n' "$backup"
