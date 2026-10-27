# Changelog

本文件格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.2.0] - 2026-10-28

### Added

- `install.sh --public <域名>`：可选地由 Caddy 反向代理 Grafana，只暴露 80/443，
  自动申请 HTTPS 证书并用 Basic Auth 保护；默认安装仍然只监听 `127.0.0.1`。
- 安装脚本在打印成功信息前等待 Prometheus、Grafana、Alertmanager（公开模式含入口）
  就绪，避免刚装完打开页面遇到 502。
- README 增加三张来自真实运行的截图：正常运行看板、站点故障时的看板、Alertmanager
  中的 `ServiceProbeFailed` 告警。

### Changed

- 端口预检忽略本栈正在监听的端口，重复执行 `install.sh` 不再误报端口冲突。
- 看板的探测结果面板标题改为「各站点探测结果（1=成功 / 0=失败）」，失败时不再
  显示容易误解的静态计数。
- README 的 Desktop 演示密码改为满足正式强度要求；补充演示模式下 9100/9115
  不可从宿主机访问的说明，故障演练改为一条 `setup_site.py` 命令。
- `install.sh` 的 crontab 渲染日志只在目标变化时记录，不再每分钟写一行。

## [0.1.2] - 2026-10-28

### Changed

- 安装器仅面向端口空闲的主机，先检查冲突再写配置；已有监控栈改用接入指南。
- 移除全局固定容器名与数据卷名，卸载默认只停止本 Compose 项目并保留数据。
- 邮箱授权码改为交互输入和独立的受限文件，不再通过命令参数或可公开读取的 YAML 保存。
- 不再默认提供公网开放 Grafana 的方式：默认通过 SSH 隧道访问，需要公网入口时显式
  使用 `install.sh --public <域名>`。
- 服务清单变更需手动渲染，不再静默添加或修改用户的 crontab。
- Blackbox Exporter 更新到 v0.29.1；证书告警忽略没有证书的目标。
- 增加现有监控接入说明、目标渲染测试和发布前验收边界。

## [0.1.1] - 2026-10-28

### Added

- `scripts/tunnel.sh`：打印带真实 IP 的 SSH 隧道命令，零配置访问（不需要安全组）
- `scripts/expose.sh on|off|status`：临时把 Grafana 切到公网访问，自动处理 `ufw` / `firewalld`，并在 README 中列出各云平台安全组位置
- `make tunnel` / `make expose-on` / `make expose-off`

### Fixed

- `install.sh` 在没有 crontab 记录时被 `set -e`（配合 `pipefail`）中断，导致后续 `docker compose up` 没执行
- 清单校验只认 `hosts[].address`，改为同时接受 `target` / `host` / `ip`，且允许地址里自带端口
- 渲染目标失败不再中断整个安装流程
- `uninstall.sh` 默认用 `down -v` 会连数据卷一起删，改为仅 `--purge` 时删除

## [0.1.0] - 2026-10-28

### Added

- Prometheus + Alertmanager + Grafana + blackbox/node-exporter 编排，host 网络，全部只监听 `127.0.0.1`
- CMDB 服务清单（`cmdb/services.json`）→ `file_sd` 目标文件渲染，cron 每分钟同步，新增服务 30 秒内生效
- 15 条告警规则：实例存活、CPU、内存、磁盘水位、磁盘写满预测、探测失败、响应慢、证书到期、负载、swap、inode、文件描述符、网卡错误、主机重启、抓取变慢
- Alertmanager 邮件通知与抑制规则（critical 抑制 warning），支持 resolved 通知
- Grafana 数据源与看板 provisioning，容器重建后配置不丢；内置 `infra-overview` 看板
- `install.sh` 一键安装（幂等，自动生成密码、修正挂载权限、安装 cron、等待就绪）
- `uninstall.sh` 卸载，支持 `--purge`
- `scripts/check.sh` 一分钟巡检、`scripts/board.sh` 文本数值面板
- GitHub Actions：promtool / amtool / shellcheck / py_compile / `docker compose config` 五项校验

### Fixed

- 容器以 `nobody` 运行时挂载目录权限不足，导致规则文件静默加载 0 条
- `alertmanager.yml` 权限 600 导致 alertmanager 反复退出
- `alerting:` / `rule_files:` 已存在空段时"缺了才追加"的脚本静默跳过

[Unreleased]: https://github.com/miku00-01/prometheus-stack/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/miku00-01/prometheus-stack/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/miku00-01/prometheus-stack/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/miku00-01/prometheus-stack/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/miku00-01/prometheus-stack/releases/tag/v0.1.0
