"""Exercise the OAuth callback against a fake Wine client, without credentials."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

script = Path(sys.argv.pop(1)).resolve()


class CallbackTests(unittest.TestCase):
    def test_callback_targets_active_prefix_and_constructs_event(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            prefix = root / "active-prefix"
            ipc = prefix / "drive_c/ProgramData/Autodesk/IDSDK/616C696365/interprocess/01000000"
            ipc.mkdir(parents=True)
            (ipc / "IDSDKQuit-v2-123").touch()
            fake = root / "wine"
            fake.write_text('#!/bin/sh\nprintf "%s\\n" "$WINEPREFIX" "$@" > "$CAPTURE"\n')
            fake.chmod(0o700)
            capture = root / "capture"
            env = os.environ | {
                "WINEPREFIX": str(prefix), "originalUser": "alice", "INVENTOR_WINE": str(fake),
                "callback_url": "adskidmgr://test-callback", "CAPTURE": str(capture),
            }
            subprocess.run(["bash", str(script)], env=env, check=True)
            self.assertEqual((ipc / "AdOAuth2Code-123").read_bytes(), b"\x01" + b"\0" * 23)
            args = capture.read_text().splitlines()
            self.assertEqual(args[0], str(prefix))
            self.assertIn("AdskIdentityManager.exe", args[1])
            self.assertEqual(args[2], env["callback_url"])
            (ipc / "AdOAuth2Code-123").write_bytes(b"existing")
            subprocess.run(["bash", str(script)], env=env, check=True)
            self.assertEqual((ipc / "AdOAuth2Code-123").read_bytes(), b"existing")

    def test_other_uri_schemes_are_rejected(self):
        result = subprocess.run(["bash", str(script)], env=os.environ | {
            "callback_url": "https://example.invalid", "INVENTOR_WINE": "/does/not/exist",
        }, capture_output=True)
        self.assertEqual(result.returncode, 2)


unittest.main()
