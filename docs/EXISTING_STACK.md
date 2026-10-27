# 在已有 Prometheus 和 Grafana 的服务器上接入网站探测

本仓库的 `install.sh` 会启动一套完整监控栈。若服务器已有 Prometheus、Grafana 或 node-exporter，**不要运行安装器**：端口会冲突，也可能使用另一组数据卷。

已有环境建议逐项接入，而不是替换旧容器：

1. 记录现有容器、配置文件挂载路径和数据卷；备份 Prometheus 配置与 Grafana 数据。
2. 在本机回环地址启动 Blackbox Exporter，先手动请求 `/probe?module=http_2xx&target=<网站地址>`，确认 `probe_success 1` 和预期 HTTP 状态。
3. 给现有 Prometheus 增加独立的 HTTP 探测 job。先用 `promtool check config` 校验，再热加载或重启 Prometheus；查询 `probe_success{job="<新 job 名>"}`，确认定时采集。
4. 在现有 Grafana 中为探测失败建立告警规则和邮件 contact point。自建 Grafana 发送邮件前，需要在**现有 Grafana 实例**配置 SMTP；本仓库的 `scripts/configure-email.sh` 只适用于本仓库新装的 Alertmanager。
5. 用单独的测试路径或测试站点触发故障并恢复，核对 firing、resolved、邮件送达和网站仍正常运行。

如果 Blackbox 与 Prometheus 均用 `network_mode: host`，探测器的监听地址和 Prometheus relabel 后的 exporter 地址通常应为 `127.0.0.1:9115`，而不是 Compose 服务名。请以实际网络配置为准。

**范围说明：**在同一台服务器上探测 `127.0.0.1` 只覆盖本地 Web 服务。要验证外部用户能否通过域名、DNS、公网链路和 HTTPS 访问，需要增加外部探测点。

官方参考：[Blackbox Exporter](https://github.com/prometheus/blackbox_exporter)、[Prometheus 多目标探测指南](https://prometheus.io/docs/guides/multi-target-exporter/)、[Grafana 邮件告警](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/)。
