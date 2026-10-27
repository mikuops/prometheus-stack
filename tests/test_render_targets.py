import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "render_targets", ROOT / "cmdb" / "render_targets.py"
)
renderer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(renderer)


class RenderTargetsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.original_paths = (
            renderer.SERVICES,
            renderer.TARGET_DIR,
            renderer.PROBE_FILE,
            renderer.NODE_FILE,
        )
        renderer.SERVICES = root / "services.json"
        renderer.TARGET_DIR = root / "targets"
        renderer.PROBE_FILE = renderer.TARGET_DIR / "http-probe.json"
        renderer.NODE_FILE = renderer.TARGET_DIR / "node.json"

    def tearDown(self):
        (
            renderer.SERVICES,
            renderer.TARGET_DIR,
            renderer.PROBE_FILE,
            renderer.NODE_FILE,
        ) = self.original_paths

    def write_services(self, url="http://127.0.0.1:18080/"):
        renderer.SERVICES.write_text(
            json.dumps(
                {
                    "services": [{"name": "website", "url": url}],
                    "hosts": [{"name": "local", "address": "127.0.0.1"}],
                }
            ),
            encoding="utf-8",
        )

    def test_valid_manifest_renders_probe_and_node_targets(self):
        self.write_services()
        self.assertEqual(renderer.main(), 0)
        probe = json.loads(renderer.PROBE_FILE.read_text(encoding="utf-8"))
        node = json.loads(renderer.NODE_FILE.read_text(encoding="utf-8"))
        self.assertEqual(probe[0]["targets"], ["http://127.0.0.1:18080/"])
        self.assertEqual(node[0]["targets"], ["127.0.0.1:9100"])

    def test_invalid_manifest_preserves_previous_targets(self):
        self.write_services()
        self.assertEqual(renderer.main(), 0)
        previous_probe = renderer.PROBE_FILE.read_bytes()
        previous_node = renderer.NODE_FILE.read_bytes()

        self.write_services("file:///etc/passwd")
        self.assertEqual(renderer.main(), 1)
        self.assertEqual(renderer.PROBE_FILE.read_bytes(), previous_probe)
        self.assertEqual(renderer.NODE_FILE.read_bytes(), previous_node)


if __name__ == "__main__":
    unittest.main()
