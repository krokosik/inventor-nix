# Compatibility record

## INITIAL LOCAL INPUT

Read-only inventory from a Windows installation, 2026-10-14:

| Component | Version |
| --- | --- |
| Inventor and OGSFactory.dll | 30.20.29800.0000 |
| Shared Components | 1.9.0 |
| Identity Manager | 1.16.5.1 |
| Licensing Service | 16.0.3.14414 |
| .NET Core / Windows Desktop | 8.0.31 |
| WebView2 | 153.0.4234.48 |

OGSFactory.dll SHA-256:

```text
121075f369dcb78e38f76e8fa5974cbf0c905d55ac1520b9c9b0b3e02a90a3a9
```

Upstream's OGS patch is incompatible with this input. At `0x56e5b` the
bytes begin `16 4a 8b 8c fd b0 00 00`; at `0x56ea8` they begin
`d2 bf 08 00 00 00 85 c0`. Its intended code cave at `0x110a60` contains
instructions rather than padding. The package leaves this DLL unmodified.

## VALIDATION

- Public repository and pinned overlay-library fork created.
- Source inventory succeeds for the input above.
- Local source archive generated without Windows account or licensing state.
- Importer contract tests pass: normalized deterministic archive, source-link
  rejection, numeric version selection, refusal to overwrite or write to Windows.
- Nix flake evaluation and importer derivation build pass.
- Overlay fork's Wine 11.4 Mono-selection regression check passes.
- Patched Wine 11.4 builds successfully.
- Headless disposable-prefix WMI probe succeeds:
  `Win32_TimeZone: 1`, `Win32_VideoController: 2`, `Win32_BIOS: 1`.
  The video-controller count is enumeration evidence, not a GPU-rendering test.
- Complete application overlay builds in the Nix sandbox, using the original
  OGS DLL. The kernel-overlay build initially failed when nix-overlayfs tried
  to chmod private workdir entries; the fork limits this to the output delta.
- Identity Manager reaches `SSO Server is ready` in an isolated runtime.
- Licensing Service starts with fresh state and listens on loopback.
- Inventor registers its COM components and enters the licensing workflow.
- Licensing reports `unable to find feature: prodKey: 797R1, version: 2026.0.0.F`.
  This is the immediate blocker: product registration has not been recreated.
- The service orchestration test verifies ordering and expansion of the
  licensing executable's versioned path. OAuth tests verify IPC event creation,
  existing-event preservation, active-prefix targeting and URI-scheme rejection.
- Native Inventor processes were exercised in the desktop session with private
  XDG state and a time limit. The test session was then terminated and reaped.
  No authentication was completed; no successful modelling session is claimed.

## CURRENT LICENSING BLOCKER

The service starts and creates its own runtime state without copied Windows
account/activation caches. Inventor's SDK successfully connects to it and asks
for the correct product key/version. The service lacks the corresponding
installed-product registration and sends the generic licensing error workflow.
This is distinct from a successful registration followed by a login request.

Next investigate the supported `AdskLicensingInstHelper` registration flow and
the required product-information metadata. No standalone `.pit` file was found
under the installed Inventor directory or the retained `C:\Autodesk\WI` cache.
Do not solve this by putting the machine-wide licensing database or activation
cache in a Nix derivation. Installer-supplied metadata, a narrow export, or
private runtime initialization need to be evaluated.

Some runtime temporary paths still refer to the base prefix's `nixbld` user.
Most application and licensing logs correctly use the actual Linux user.
Prefix personalization should be checked before calling this multi-user ready.

## OPEN WORK

1. Determine required Autodesk product-registration metadata.
2. Verify Mono WPF-stub removal survives runtime prefix initialization.
3. Complete browser SSO callback and fresh license initialization.
4. Open the UI and create/save/reopen a part using the original OGS DLL.
5. If necessary, port the null-check workaround with a supported DLL hash and
   checked original instructions; prefer fixing Wine's WMI implementation.
6. Check assemblies, drawings, Content Center, graphics and restart persistence.
7. Compare clean builds and test a second Linux user and host.

The original project's reported limitations include iLogic, Realistic Visual
Style, GPU ray tracing and material brightness. Those features have not yet
been independently tested here.
