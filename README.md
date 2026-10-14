# inventor-nix

**Experimental packaging of Autodesk Inventor Professional 2026 for Linux.**

Uses [nix-overlayfs](https://github.com/conroy-cheers/nix-overlayfs) to compose
an immutable Wine environment and application layers with persistent per-user
state. Each user supplies files from their own licensed Windows installation.
No Autodesk binaries, Windows registry hives, login tokens or licensing
databases are distributed here.

## STATUS

This is a development prototype, not a confirmed working Inventor release.
The importer, patched Wine and complete overlay package build successfully.
Identity Manager and Licensing Service start, and Inventor enters its licensing
workflow. The current blocker is missing product-registration metadata; account
authentication and modelling remain unverified. See
[docs/compatibility.md](docs/compatibility.md) for the actual validation record.

The baseline is Wine 11.4 with a `Win32_TimeZone` WMI patch and DXVK 2.7.1.
We deliberately do **not** apply the fixed-offset OGSFactory.dll binary patch
from [inventor-on-linux](https://github.com/cakelesscoder/inventor-on-linux):
it does not match the initially imported build, and would overwrite code.

Initially targets `x86_64-linux`. The packaging flake has no dependency on a
particular NixOS configuration, username, Windows mount point or secrets repo.

## IMPORT A WINDOWS INSTALLATION

Inventory versions without copying files:

```bash
nix run github:krokosik/inventor-nix -- --windows-root /mnt/c --inventory
```

Create a **new private directory outside your Git checkout**:

```bash
nix run github:krokosik/inventor-nix -- \
  --windows-root /mnt/c \
  --output "$HOME/.local/share/inventor-nix-imports/my-2026-install"
```

Add `--content-center` to include the optional hardware libraries. The importer
selects the newest installed numeric Identity Manager, Licensing Service,
2026 Shared Components and WebView2 directories. .NET selection is restricted
to version 8. It uses case-insensitive Windows path lookup where needed.

The output contains:

```text
my-2026-install/
├── inventor-2026-source.tar  # Normalized, deterministic local source archive
└── package/
    ├── manifest.json       # Component versions and per-file hashes
    └── flake.nix           # Private consumer flake using requireFile
```

The importer does not execute Windows binaries or write to Windows. It copies
an explicit list of program and shared-data directories, selected runtime
DLLs and .NET 8 frameworks. It refuses symlinks and special files in selected
trees, existing output directories and destinations on the Windows volume.
It does not import personal Windows profiles, registry hives, `Adlm` caches,
`AdskLicensingService` databases or Identity Manager account state.

Windows should be shut down before importing; component updates during an
import can invalidate a snapshot. Keep enough space for the archive, its
store copy, application layers and build work directories (tens of GB).

## BUILD AND EXPERIMENT

First add the archive to the local Nix store:

```bash
nix store add-file "$HOME/.local/share/inventor-nix-imports/my-2026-install/inventor-2026-source.tar"
```

Then build the generated private flake:

```bash
nix build "$HOME/.local/share/inventor-nix-imports/my-2026-install/package"
```

`requireFile` verifies the archive hash. Commit or retain the generated
`package/flake.lock` **privately** to pin the packaging recipe as well as the
Windows input. The public flake lock pins Wine's build environment and the
overlay library. Wine and DXVK source hashes are explicit.

After a successful build, launch the experimental environment:

```bash
nix run "$HOME/.local/share/inventor-nix-imports/my-2026-install/package"
```

On NixOS, if driver discovery needs an explicit host graphics selection:

```bash
NIX_OVERLAYFS_GRAPHICS_STACK=system \
  nix run "$HOME/.local/share/inventor-nix-imports/my-2026-install/package"
```

First launch is intended to use a fresh Autodesk login. The currently tested
snapshot stops at licensing because the service has no registered feature for
product `797R1`, version `2026.0.0.F`. Reconstructing that product registration
from appropriate installation metadata is the next milestone. No cached
activation is assumed or imported.

Runtime files live under `$XDG_DATA_HOME/inventor-2026` (default
`~/.local/share/inventor-2026`), with logs under `.nix-overlayfs/logs`.
The application wrapper serializes normal launches. The `adskidmgr://`
callback is forwarded to the already-active session without taking that
launch lock. The overlay library registers the URI handler at runtime.
An overlay namespace is not a complete security sandbox; Wine can access
host files through its drive mappings.

## DEVELOPMENT

Use sibling checkouts of `inventor-nix` and `nix-overlayfs`. No submodules
are needed. For a private imported package, from its `package/` directory:

```bash
nix build . \
  --override-input inventor-nix path:/absolute/path/to/inventor-nix \
  --override-input inventor-nix/nix-overlayfs path:/absolute/path/to/nix-overlayfs \
  --no-write-lock-file
```

The public input currently pins [our fork](https://github.com/krokosik/nix-overlayfs),
which adds Wine 11.4's missing Mono bootstrap selection and a regression check,
and fixes permission normalization walking kernel overlayfs' private workdir.

```bash
nix fmt .
nix flake check
nix develop --command shellcheck --shell=bash scripts/prelaunch.sh scripts/oauth.sh
nix run .#wine-probe
```

`nix flake check` validates the importer, service orchestration and OAuth
callback with synthetic inputs. `wine-probe` checks three WMI classes in a
disposable Wine prefix without proprietary files. Neither command establishes
successful Autodesk authentication or application operation.
Bit-for-bit reproducibility of Wine-generated layers also remains to be
checked with independent clean builds.

## CREDITS AND LICENSE

The compatibility approach and Wine patch come from
[cakelesscoder/inventor-on-linux](https://github.com/cakelesscoder/inventor-on-linux/tree/286a454f2d4aa8715ba1ae6146802a8b2ee71588).
The service order and OAuth IPC workaround are adapted from its scripts.
The overlay implementation is Conroy Cheers' nix-overlayfs, based on work by
Libor Stepanek. See [LICENSE](LICENSE) for the packaging code and exceptions.

Autodesk Inventor requires a valid license. This project uses Autodesk's
authentication flow and does not provide activation credentials or bypasses.
