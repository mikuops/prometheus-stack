.DEFAULT_GOAL := help
DOCKER ?= docker
COMPOSE := $(DOCKER) compose
PROM := prom/prometheus:v3.15.0

help:  ## 显示所有命令
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

up:  ## 启动全部服务
	@test -f .env || { echo "缺少 .env，请先运行 bash install.sh"; exit 1; }
	@test -f alertmanager/alertmanager.yml || { echo "缺少 alertmanager/alertmanager.yml，请先运行 bash install.sh"; exit 1; }
	@test -f prometheus/targets/http-probe.json -a -f prometheus/targets/node.json || { echo "缺少目标文件，请先运行 python3 cmdb/render_targets.py"; exit 1; }
	$(COMPOSE) up -d

down:  ## 停止（保留数据）
	$(COMPOSE) down

restart:  ## 重启 Prometheus
	$(COMPOSE) restart prometheus

logs:  ## 跟踪 Prometheus 日志
	$(COMPOSE) logs -f --tail=100 prometheus

ps:  ## 查看容器状态
	$(COMPOSE) ps

check:  ## 一分钟巡检
	bash scripts/check.sh

board:  ## 终端数值面板
	bash scripts/board.sh

tunnel:  ## 打印访问用的 SSH 隧道命令
	bash scripts/tunnel.sh

email:  ## 在终端交互配置 SMTP 邮件，不在命令行暴露授权码
	bash scripts/configure-email.sh

test-alert:  ## 发送一条人工测试告警，核对邮件链路
	bash scripts/test-alert.sh

render:  ## 重新渲染 file_sd 目标文件
	python3 cmdb/render_targets.py

reload:  ## 热加载 Prometheus 配置
	curl -fsS -X POST http://127.0.0.1:9090/-/reload && echo reloaded

lint:  ## 校验规则与脚本（与 CI 相同）
	$(DOCKER) run --rm -v $$PWD/prometheus:/p --entrypoint sh $(PROM) -c 'promtool check rules /p/rules/*.yml'
	$(DOCKER) run --rm -v $$PWD/alertmanager:/a --entrypoint amtool prom/alertmanager:v0.34.1 check-config /a/no-notify.yml.example
	shellcheck --severity=error install.sh uninstall.sh scripts/*.sh
	python3 -m py_compile cmdb/render_targets.py

test: lint render  ## 本地跑一遍 CI 同款检查
	python3 -m unittest discover -s tests -v

clean:  ## 清理渲染产物
	rm -f prometheus/targets/*.json

install:  ## 一键安装（等同 bash install.sh）
	bash install.sh

.PHONY: help up down restart logs ps check board tunnel email test-alert render reload lint test clean install
