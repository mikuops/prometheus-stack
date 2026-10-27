"""校验随仓库发布的 Grafana 面板 JSON。

面板是基础设施的一部分：JSON 里写错一个 expr，Grafana 只会画个红三角，
不会让安装失败。这里在 CI 里做结构校验，真实 PromQL 语法由 CI 启动栈后
逐条查询验证（见 .github/workflows/ci.yml）。
"""
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DASHBOARD = ROOT / "grafana" / "provisioning" / "dashboards" / "infra-overview.json"
DATASOURCE_UID = "prom-prod"

# 首页必须一眼看到的结论；标题改动要同步改 README 里的截图说明。
REQUIRED_TITLES = {
    "采集目标 UP 数",
    "HTTP 探测成功率（5 分钟）",
    "正在触发的告警",
    "CPU 使用率 (%)",
    "内存使用率 (%)",
    "磁盘使用率 (%)",
    "站点探测耗时 (s)",
    "各站点探测结果（1=成功 / 0=失败）",
    "各站点探测成功率 (%)",
    "HTTP 状态码",
}


class DashboardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = json.loads(DASHBOARD.read_text(encoding="utf-8"))
        cls.panels = cls.doc["panels"]

    def test_identity_and_datasource(self):
        self.assertEqual(self.doc["uid"], "infra-overview")
        for panel in self.panels:
            self.assertEqual(panel["datasource"], {"type": "prometheus", "uid": DATASOURCE_UID})
            self.assertTrue(panel["targets"], panel["title"])

    def test_ids_unique_and_titles_complete(self):
        ids = [panel["id"] for panel in self.panels]
        self.assertEqual(len(ids), len(set(ids)))
        titles = {panel["title"] for panel in self.panels}
        self.assertTrue(REQUIRED_TITLES <= titles, REQUIRED_TITLES - titles)

    def test_grid_fits_24_columns_without_overlap(self):
        cells = set()
        for panel in self.panels:
            grid = panel["gridPos"]
            self.assertGreaterEqual(grid["x"], 0, panel["title"])
            self.assertGreaterEqual(grid["y"], 0, panel["title"])
            self.assertLessEqual(grid["x"] + grid["w"], 24, panel["title"])
            for y in range(grid["y"], grid["y"] + grid["h"]):
                for x in range(grid["x"], grid["x"] + grid["w"]):
                    self.assertNotIn((x, y), cells, f"{panel['title']} 与其它面板重叠")
                    cells.add((x, y))

    def test_no_data_falls_back_to_zero(self):
        """没有 target / 没有告警时要显示 0，而不是 Grafana 的默认空白。"""
        by_title = {panel["title"]: panel for panel in self.panels}
        for title in ("采集目标 UP 数", "正在触发的告警"):
            expr = by_title[title]["targets"][0]["expr"]
            self.assertIn("or vector(0)", expr, title)
        self.assertEqual(by_title["正在触发的告警"]["fieldConfig"]["defaults"]["noValue"], "无告警")
        self.assertIn("avg_over_time(probe_success", by_title["HTTP 探测成功率（5 分钟）"]["targets"][0]["expr"])

    def test_duration_and_status_code_are_separate(self):
        """耗时和状态码量纲不同，不能画在同一张图里。"""
        by_title = {panel["title"]: panel for panel in self.panels}
        duration = by_title["站点探测耗时 (s)"]["targets"][0]["expr"]
        status = by_title["HTTP 状态码"]["targets"][0]["expr"]
        self.assertIn("probe_duration_seconds", duration)
        self.assertIn("probe_http_status_code", status)
        self.assertNotEqual(duration, status)

    def test_probe_panels_filter_http_job(self):
        for panel in self.panels:
            expr = panel["targets"][0]["expr"]
            if "probe_" in expr:
                self.assertIn('job="http-probe"', expr, panel["title"])


if __name__ == "__main__":
    unittest.main()
