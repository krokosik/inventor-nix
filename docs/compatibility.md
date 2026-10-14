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
- Patched Wine build and application runtime validation are in progress.

## OPEN WORK

1. Verify WMI enumeration for TimeZone, VideoController and BIOS.
2. Verify Mono WPF-stub removal survives runtime prefix initialization.
3. Start Identity Manager and Licensing Service with no imported account state.
4. Determine required Autodesk product-registration metadata.
5. Complete browser SSO callback and fresh license initialization.
6. Open the UI and create/save/reopen a part using the original OGS DLL.
7. If necessary, port the null-check workaround with a supported DLL hash and
   checked original instructions; prefer fixing Wine's WMI implementation.
8. Check assemblies, drawings, Content Center, graphics and restart persistence.
9. Compare clean builds and test a second Linux user and host.

The original project's reported limitations include iLogic, Realistic Visual
Style, GPU ray tracing and material brightness. Those features have not yet
been independently tested here.
