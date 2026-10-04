import importlib.util
from pathlib import Path
import tempfile
import unittest
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("installer", ROOT / "tools/install.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTest(unittest.TestCase):
    def test_managed_keys_preserve_unrelated_settings(self):
        original = "# comment\n[TabBox]\nLayoutName=compact\nHighlightWindows=true\n\n[Plugins]\nkarouselEnabled=true\n"
        modified = installer.update_values(original, {"LayoutName": "scrolltab", "DelayTime": "0"})
        self.assertIn("HighlightWindows=true", modified)
        self.assertIn("[Plugins]\nkarouselEnabled=true", modified)
        restored = installer.update_values(modified, {"LayoutName": "compact", "DelayTime": None})
        self.assertEqual(restored, original)

    def test_stage_update_and_restore_keep_unrelated_edits(self):
        with tempfile.TemporaryDirectory() as temporary:
            temp = Path(temporary)
            config = temp / "config"
            config.mkdir()
            kwinrc = config / "kwinrc"
            kwinrc.write_text("[TabBox]\nLayoutName=compact\nDelayTime=90\n[Plugins]\nkarouselEnabled=true\n")
            command = [sys.executable, str(ROOT / "tools/install.py")]
            paths = ["--data-home", str(temp / "data"), "--config-home", str(config)]
            subprocess.run(command + ["install", "--configure"] + paths, check=True, capture_output=True)
            subprocess.run(command + ["install", "--configure"] + paths, check=True, capture_output=True)
            self.assertEqual(installer.read_values(kwinrc.read_text())["DelayTime"], "0")
            kwinrc.write_text(kwinrc.read_text() + "anotherEffectEnabled=true\n")
            subprocess.run(command + ["uninstall"] + paths, check=True, capture_output=True)
            values = installer.read_values(kwinrc.read_text())
            self.assertEqual(values["LayoutName"], "compact")
            self.assertEqual(values["DelayTime"], "90")
            self.assertIn("anotherEffectEnabled=true", kwinrc.read_text())

    def test_restore_refuses_to_overwrite_changed_keys(self):
        with tempfile.TemporaryDirectory() as temporary:
            temp = Path(temporary)
            command = [sys.executable, str(ROOT / "tools/install.py")]
            paths = ["--data-home", str(temp / "data"), "--config-home", str(temp / "config")]
            subprocess.run(command + ["install", "--configure"] + paths, check=True, capture_output=True)
            kwinrc = temp / "config/kwinrc"
            kwinrc.write_text(kwinrc.read_text().replace("DesktopMode=1", "DesktopMode=0"))
            result = subprocess.run(command + ["uninstall"] + paths, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("DesktopMode=0", kwinrc.read_text())


if __name__ == "__main__":
    unittest.main()
