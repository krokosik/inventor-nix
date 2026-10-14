"""Exercise service startup ordering and versioned paths without Autodesk code."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest

script = Path(sys.argv.pop(1)).resolve()


class PrelaunchTests(unittest.TestCase):
    def test_services_start_in_order_with_expanded_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fake = root / "wine"
            fake.write_text(f"#!{sys.executable}\n" + '''import os
from pathlib import Path
import sys
import time
executable = sys.argv[1]
with open(os.environ["CAPTURE"], "a") as stream:
    stream.write(executable + "\\n")
if executable.endswith("AdskIdentityManager.exe"):
    log = Path(os.environ["WINEPREFIX"]) / "drive_c/users/alice/AppData/Local/Autodesk/Identity Services/Log/IdServices.log"
    log.parent.mkdir(parents=True)
    log.write_text("SSO Server is ready\\n")
time.sleep(30)
''')
            fake.chmod(0o700)
            env = os.environ | {
                "WINEPREFIX": str(root / "prefix"), "originalUser": "alice",
                "appdir": str(root / "upper"), "INVENTOR_WINE": str(fake),
                "INVENTOR_LICENSING_VERSION": "16.0.3.14414",
                "NIX_OVERLAYFS_DIRECT_MODE": "1", "CAPTURE": str(root / "capture"),
            }
            process = subprocess.Popen(["bash", str(script)], env=env, start_new_session=True)
            try:
                self.assertEqual(process.wait(timeout=15), 0)
                commands = (root / "capture").read_text().splitlines()
                self.assertEqual(len(commands), 2)
                self.assertTrue(commands[0].endswith("AdskIdentityManager.exe"))
                self.assertIn("AdskLicensing\\16.0.3.14414\\AdskLicensingService", commands[1])
                self.assertNotIn("$", commands[1])
            finally:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                process.wait(timeout=5)


unittest.main()
