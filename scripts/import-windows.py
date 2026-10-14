#!/usr/bin/env python3
"""Import an allowlisted, credential-free Windows application snapshot.

No Wine execution, registry hive copying, or writes to the Windows volume.
The output is deliberately outside the public source repository.
"""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tarfile
import tempfile


RUNTIMES = (
    "msvcp140.dll", "msvcp140_1.dll", "msvcp140_2.dll",
    "vcruntime140.dll", "vcruntime140_1.dll", "concrt140.dll",
    "vcomp140.dll", "mfc140u.dll", "mfc140.dll", "d3dcompiler_47.dll",
)


def regular_file(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode):
        raise ValueError(f"Expected a regular file, refusing links/special files: {path}")
    return info


def windows_path(root, relative):
    """Resolve Windows' case-insensitive paths on a case-sensitive Linux mount."""
    path = root
    for part in Path(relative).parts:
        exact = path / part
        if exact.exists():
            path = exact
            continue
        matches = [child for child in path.iterdir() if child.name.casefold() == part.casefold()]
        if len(matches) != 1:
            raise ValueError(f"Missing or ambiguous Windows path: {root / relative}")
        path = matches[0]
    return path


def version(path):
    """Read the string version resource without executing a Windows binary."""
    data = path.read_bytes().decode("utf-16-le", errors="ignore")
    match = re.search(r"FileVersion\x00+([0-9]+(?:\.[0-9]+){1,3})", data)
    if not match:
        raise ValueError(f"No FileVersion resource found: {path}")
    return match.group(1)


def newest(directory, required=None, major=None):
    candidates = []
    for child in directory.iterdir():
        if re.fullmatch(r"\d+(?:\.\d+)+", child.name):
            if major is not None and child.name.split(".")[0] != str(major):
                continue
            if child.is_dir() and not child.is_symlink():
                if required is None or (child / required).is_file():
                    candidates.append(child)
    if not candidates:
        raise ValueError(f"No suitable version directory in {directory}")
    return max(candidates, key=lambda p: tuple(int(n) for n in p.name.split(".")))


def inventory(root, content_center=False):
    selections = []

    def add(source, destination=None):
        source = Path(source)
        path = windows_path(root, source)
        if not path.exists():
            raise ValueError(f"Missing required input: {path}")
        # Check ancestors too: a selected path must not escape through a link.
        for ancestor in (path, *path.parents):
            if ancestor == root:
                break
            if ancestor.is_symlink():
                raise ValueError(f"Refusing symbolic link in source path: {ancestor}")
        selections.append((path, Path("drive_c") / (destination or source)))
        return path

    app = Path("Program Files/Autodesk/Inventor 2026")
    exe = root / app / "Bin/Inventor.exe"
    ogs = root / app / "Bin/OGSFactory.dll"
    regular_file(exe)
    regular_file(ogs)
    app_version = version(exe)
    if not app_version.startswith("30."):
        raise ValueError(f"Expected Inventor 2026 (30.x), found {app_version}")
    for directory in ("Bin", "Configuration", "Preferences"):
        add(app / directory)
    shared = Path("Program Files/Common Files/Autodesk Shared")
    components = newest(root / shared / "Components/2026")
    add(components.relative_to(root))
    add(shared / "RealDWG Shared 2026")
    add(shared / "Materials")
    identity = newest(root / "Program Files/Autodesk/AdskIdentityManager", "AdskIdentityManager.exe")
    add(identity.relative_to(root), Path("Program Files/Autodesk/AdskIdentityManager/Current"))
    licensing_root = Path("Program Files (x86)/Common Files/Autodesk Shared/AdskLicensing")
    licensing = newest(root / licensing_root, "AdskLicensingService/AdskLicensingService.exe")
    add(licensing.relative_to(root))
    dotnet = Path("Program Files/dotnet")
    for name in ("dotnet.exe", "LICENSE.txt", "ThirdPartyNotices.txt"):
        if (root / dotnet / name).is_file():
            add(dotnet / name)
    dotnet_versions = {}
    for framework in ("Microsoft.NETCore.App", "Microsoft.WindowsDesktop.App"):
        selected = newest(root / dotnet / "shared" / framework, major=8)
        add(selected.relative_to(root))
        dotnet_versions[framework] = selected.name
    fxr = newest(root / dotnet / "host/fxr", major=8)
    add(fxr.relative_to(root))
    webview_root = Path("Program Files (x86)/Microsoft/EdgeWebView/Application")
    webview = newest(root / webview_root, "msedgewebview2.exe")
    add(webview.relative_to(root))
    for name in RUNTIMES:
        add(Path("Windows/System32") / name, Path("windows/system32") / name)
    public = Path("Users/Public/Documents/Autodesk/Inventor 2026")
    for name in ("Design Data", "Templates", "Textures", "Backgrounds", "Default.ipj"):
        add(public / name, Path("users/Public/Documents/Autodesk/Inventor 2026") / name)
    if content_center:
        add(Path("ProgramData/Autodesk/Inventor 2026/Content Center"))
    manifest = {
        "schema": 1,
        "inventorVersion": app_version,
        "ogsVersion": version(ogs),
        "ogsSha256": hashlib.sha256(ogs.read_bytes()).hexdigest(),
        "componentsVersion": components.name,
        "identityVersion": identity.name,
        "licensingVersion": licensing.name,
        "dotnetVersions": dotnet_versions,
        "webviewVersion": webview.name,
        "contentCenter": content_center,
        "ogsPatched": False,
    }
    return manifest, selections


def collect_files(selections):
    files = {}
    for source, destination in selections:
        paths = [source]
        if source.is_dir():
            paths = sorted(source.rglob("*"))
        for path in paths:
            if path.is_symlink():
                raise ValueError(f"Refusing source link: {path}")
            if path.is_dir():
                continue
            regular_file(path)
            relative = path.relative_to(source) if source.is_dir() else Path()
            target = (destination / relative).as_posix()
            if target in files:
                raise ValueError(f"Duplicate archive destination: {target}")
            files[target] = path
    return files


def write_archive(path, files):
    entries = []
    with tarfile.open(path, "w", format=tarfile.PAX_FORMAT) as archive:
        for destination, source in sorted(files.items()):
            before = regular_file(source)
            digest = hashlib.sha256()
            with source.open("rb") as stream:
                # Hash and archive the same open file. Avoid a second full read.
                class Reader:
                    def read(self, size=-1):
                        data = stream.read(size)
                        digest.update(data)
                        return data
                info = tarfile.TarInfo(destination)
                info.size = before.st_size
                info.mode = 0o644
                info.uid = info.gid = info.mtime = 0
                archive.addfile(info, Reader())
                after = os.fstat(stream.fileno())
            if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                raise ValueError(f"Source changed during import: {source}")
            entries.append({"path": destination, "size": info.size, "sha256": digest.hexdigest()})
    return entries


def import_bundle(root, output, content_center=False):
    if output.exists():
        raise ValueError(f"Output already exists; choose a new directory: {output}")
    if output == root or output.is_relative_to(root):
        raise ValueError("Output must be outside the Windows volume")
    manifest, selections = inventory(root, content_center)
    files = collect_files(selections)
    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".inventor-import-", dir=output.parent))
    try:
        archive = staging / "inventor-2026-source.tar"
        manifest["files"] = write_archive(archive, files)
        with archive.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").digest()
        manifest["archiveHash"] = "sha256-" + base64.b64encode(digest).decode()
        package = staging / "package"
        package.mkdir()
        (package / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        (package / "flake.nix").write_text('''{
  description = "Private local Inventor snapshot; do not publish this directory";
  inputs.inventor-nix.url = "github:krokosik/inventor-nix";
  outputs = { self, inventor-nix }: {
    packages.x86_64-linux.default = inventor-nix.lib.x86_64-linux.mkInventor {
      manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
      src = inventor-nix.lib.x86_64-linux.requireFile {
        name = "inventor-2026-source.tar";
        hash = "''' + manifest["archiveHash"] + '''";
        message = "Run nix store add-file ../inventor-2026-source.tar before building.";
      };
    };
  };
}
''')
        staging.rename(output)
    except BaseException:
        shutil.rmtree(staging)
        raise
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--windows-root", type=Path, default=Path("/mnt/c"))
    parser.add_argument("--output", type=Path, help="New private output directory")
    parser.add_argument("--content-center", action="store_true", help="Include optional Content Center libraries")
    parser.add_argument("--inventory", action="store_true", help="Only print component versions; do not copy files")
    args = parser.parse_args()
    try:
        root = args.windows_root.resolve(strict=True)
        if args.inventory:
            result, _ = inventory(root, args.content_center)
        elif args.output is not None:
            result = import_bundle(root, args.output.resolve(), args.content_center)
        else:
            parser.error("--output is required unless --inventory is selected")
        print(json.dumps({key: value for key, value in result.items() if key != "files"}, indent=2))
    except (OSError, ValueError) as error:
        parser.exit(1, f"inventor-import: {error}\n")


if __name__ == "__main__":
    main()
