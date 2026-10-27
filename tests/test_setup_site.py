import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "cmdb"))
import render_targets  # noqa: E402
import setup_site  # noqa: E402


class SetupSiteTests(unittest.TestCase):
    def test_url_rejects_credentials_and_query_tokens(self):
        self.assertTrue(setup_site.valid_url("http://127.0.0.1:18080/"))
        self.assertFalse(setup_site.valid_url("https://user:pass@example.com/"))
        self.assertFalse(setup_site.valid_url("https://example.com/?token=private"))
        self.assertFalse(setup_site.valid_url("file:///etc/passwd"))

    def test_updates_disabled_example_and_preserves_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "services.json"
            manifest.write_text(
                json.dumps(
                    {
                        "hosts": [{"name": "local", "address": "127.0.0.1"}],
                        "services": [
                            {
                                "name": "website-home",
                                "url": "http://old.invalid/",
                                "enabled": False,
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            targets = root / "targets"
            with (
                patch.object(setup_site, "MANIFEST", manifest),
                patch.object(render_targets, "SERVICES", manifest),
                patch.object(render_targets, "TARGET_DIR", targets),
                patch.object(render_targets, "PROBE_FILE", targets / "http-probe.json"),
                patch.object(render_targets, "NODE_FILE", targets / "node.json"),
                patch.object(
                    sys,
                    "argv",
                    [
                        "setup_site.py",
                        "--url",
                        "http://127.0.0.1:18080/",
                    ],
                ),
            ):
                self.assertEqual(setup_site.main(), 0)
            data = json.loads(manifest.read_text(encoding="utf-8"))
            self.assertTrue(data["services"][0]["enabled"])
            self.assertEqual(data["services"][0]["url"], "http://127.0.0.1:18080/")
            self.assertEqual(len(list(root.glob("services.json.bak-*"))), 1)
            rendered = json.loads((targets / "http-probe.json").read_text(encoding="utf-8"))
            self.assertEqual(rendered[0]["targets"], ["http://127.0.0.1:18080/"])


if __name__ == "__main__":
    unittest.main()
