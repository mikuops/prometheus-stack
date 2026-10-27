#!/usr/bin/env bash
# Stop this Compose project while retaining metrics, dashboards and secrets.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[ "$#" -eq 0 ] || { echo "本脚本不删除数据；请勿传入 --purge" >&2; exit 1; }

if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
elif command -v sudo >/dev/null && sudo docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker)
else
  echo "当前用户无法访问 Docker daemon" >&2
  exit 1
fi
"${DOCKER[@]}" compose down
echo "本项目容器已停止；Compose 数据卷、配置和邮箱授权码文件均保留。"
echo "需要删除数据时，请先独立备份并手动检查确切的卷名。"
