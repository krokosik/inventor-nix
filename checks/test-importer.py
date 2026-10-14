"""Contract tests: reproducibility and refusal of unsafe imports."""
import importlib.util
import hashlib
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("importer", sys.argv.pop(1))
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)


class ImporterTests(unittest.TestCase):
    def test_archive_is_deterministic_and_normalized(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            source.write_bytes(b"example")
            files = {"drive_c/app/data": source}
            first = root / "first.tar"
            second = root / "second.tar"
            entries = importer.write_archive(first, files)
            source.chmod(0o777)
            importer.write_archive(second, files)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(entries[0]["size"], 7)
            with tarfile.open(first) as archive:
                item = archive.getmembers()[0]
                self.assertEqual((item.uid, item.gid, item.mtime, item.mode), (0, 0, 0, 0o644))

    def test_source_links_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "private").write_text("secret")
            (root / "selected").mkdir()
            (root / "selected/link").symlink_to(root / "private")
            with self.assertRaisesRegex(ValueError, "link"):
                importer.collect_files([(root / "selected", Path("drive_c/app"))])

    def test_version_selection_is_numeric(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ("8.0.9", "8.0.31", "9.0.1", "Current"):
                (root / name).mkdir()
            self.assertEqual(importer.newest(root, major=8).name, "8.0.31")

    def test_import_refuses_existing_output_and_windows_destination(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaisesRegex(ValueError, "already exists"):
                importer.import_bundle(root, root)
            with self.assertRaisesRegex(ValueError, "outside"):
                importer.import_bundle(root, root / "output")

    def test_complete_import_excludes_account_state_and_survives_windows_removal(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "windows"
            root.mkdir()

            def file(name, data=b"application data"):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)

            app = "Program Files/Autodesk/Inventor 2026"
            resource = ("FileVersion" + "\0\0" + "30.20.29800.0000\0").encode("utf-16-le")
            for binary in ("Inventor.exe", "OGSFactory.dll"):
                file(f"{app}/Bin/{binary}", resource)
            for name in ("Configuration", "Preferences"):
                file(f"{app}/{name}/data")
            shared = "Program Files/Common Files/Autodesk Shared"
            for name in ("Components/2026/1.9.0", "RealDWG Shared 2026", "Materials"):
                file(f"{shared}/{name}/data")
            file("Program Files/Autodesk/AdskIdentityManager/1.16.5.1/AdskIdentityManager.exe")
            file("Program Files (x86)/Common Files/Autodesk Shared/AdskLicensing/16.0.3.14414/AdskLicensingService/AdskLicensingService.exe")
            for framework in ("Microsoft.NETCore.App", "Microsoft.WindowsDesktop.App"):
                file(f"Program Files/dotnet/shared/{framework}/8.0.31/data")
            file("Program Files/dotnet/host/fxr/8.0.31/hostfxr.dll")
            file("Program Files (x86)/Microsoft/EdgeWebView/Application/153.0.4234.48/msedgewebview2.exe")
            for name in importer.RUNTIMES:
                file(f"Windows/System32/{name.upper()}")
            public = "Users/Public/Documents/Autodesk/Inventor 2026"
            for name in ("Design Data", "Templates", "Textures", "Backgrounds"):
                file(f"{public}/{name}/data")
            file(f"{public}/Default.ipj")
            for private in (
                "Users/alice/NTUSER.DAT",
                "Users/alice/AppData/Local/Autodesk/Identity Services/token",
                "ProgramData/Autodesk/Adlm/ASR/license.asr",
                "ProgramData/Autodesk/AdskLicensingService/AdskLicensingService.data",
                "Windows/System32/config/SOFTWARE",
            ):
                file(private, b"DO NOT IMPORT")
            output = Path(tmp) / "snapshot"
            manifest = importer.import_bundle(root, output)
            self.assertEqual(manifest["inventorVersion"], "30.20.29800.0000")
            self.assertFalse(manifest["ogsPatched"])
            root.rename(root.with_name("unmounted"))
            with tarfile.open(output / "inventor-2026-source.tar") as archive:
                self.assertTrue(all("DO NOT IMPORT" not in archive.extractfile(item).read().decode(errors="ignore") for item in archive.getmembers()))
                for entry in manifest["files"]:
                    self.assertEqual(hashlib.sha256(archive.extractfile(entry["path"]).read()).hexdigest(), entry["sha256"])
            consumer = (output / "package/flake.nix").read_text()
            self.assertIn(manifest["archiveHash"], consumer)
            self.assertNotIn(str(root), consumer)


unittest.main()
