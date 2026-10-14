import json
from pathlib import Path
import tempfile
import unittest

from agentask.config import load_config


class ConfigTests(unittest.TestCase):
    def test_missing_and_partial_files_use_defaults(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.json"
            self.assertTrue(load_config(path)["behavior"]["enabled"])
            path.write_text('{"appearance":{"font_size":22}}', encoding="utf-8-sig")
            config = load_config(path)
            self.assertEqual(22, config["appearance"]["font_size"])
            self.assertFalse(config["behavior"]["timeout_enabled"])

    def test_invalid_settings_are_rejected(self):
        cases = [
            [], None, {"behaviour": {}}, {"appearance": {"fontsize": 16}},
            {"behavior": {"enabled": "false"}}, {"appearance": {"edge_animation": 1}},
            {"appearance": {"window_scale": float("nan")}},
            {"appearance": {"window_scale": 2}}, {"appearance": {"font_size": 12.5}},
            {"behavior": {"timeout_seconds": 0}}, {"behavior": {"timeout_seconds": True}},
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.json"
            for value in cases:
                with self.subTest(value=value):
                    path.write_text(json.dumps(value), encoding="utf-8")
                    with self.assertRaises(ValueError):
                        load_config(path)
            path.write_text('{"behavior":')
            with self.assertRaises(ValueError):
                load_config(path)
