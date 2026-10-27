# 参与开发

这是个个人维护的小项目，欢迎提 issue 或 PR，建议先开 issue 说明动机再动手。

## 本地验证

提交前跑一遍 CI 同款检查（需要 docker 与 shellcheck）：

```bash
make lint     # promtool / amtool / shellcheck / py_compile
make test     # lint + 重新渲染清单
```

## 改动约定

- 告警规则只放 `prometheus/rules/*.yml`，每条要有 `severity` 标签和 `summary` / `description` 注解；
- 新增抓取目标优先走 `cmdb/services.json`，不要往 `prometheus.yml` 里加 `static_configs`；
- 脚本用 `set -euo pipefail`，路径从脚本自身位置推导，不依赖调用时的当前目录；
- 涉及凭据的配置一律以 `*.example` 形式提供，真实文件写进 `.gitignore`。
- 不在脚本参数、终端输出、日志、Issue 或 PR 中展示邮箱授权码与 Grafana 密码。
- 改动安装或卸载流程时，检查已有容器、端口和数据卷不会被覆盖或误删。
- 新增目标清单校验时，运行 `python3 -m unittest discover -s tests -v`。
