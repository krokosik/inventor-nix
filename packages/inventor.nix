{
  lib,
  pkgs,
  wine,
  src,
  manifest,
}:
let
  overlayfsLib = pkgs.nix-overlayfs.lib;
  modules = pkgs.nix-overlayfs.moduleScopes.makeNativeModules {
    inherit wine;
    windowsArch = "wow64";
    id = "inventor-2026";
  };
  monoCompatibleBase = modules.base-env.overrideAttrs (old: {
    installPhase = old.installPhase + /* bash */ ''
      # Remove WPF stub files from the base itself, not from a delta layer.
      for assembly in PresentationCore PresentationFramework WindowsBase System.Xaml; do
        for gac in "$out/basePackage/drive_c/windows/mono"/mono-*/lib/mono/gac; do
          if [ -d "$gac/$assembly" ]; then
            find "$gac/$assembly" -type f -delete
          fi
        done
      done
    '';
  });
  runtime = modules.runtime // {
    baseEnvLayer = monoCompatibleBase;
    selectBaseEnvLayer = _: monoCompatibleBase;
  };
  dxvkSource = pkgs.fetchurl {
    url = "https://github.com/doitsujin/dxvk/releases/download/v2.7.1/dxvk-2.7.1.tar.gz";
    hash = "sha256-2Fznx59X7NdlqqG55wB8uHXm/en20zHfeZvOc9UTzoc=";
  };
  registry = pkgs.writeText "inventor-install.reg" /* reg */ ''
    Windows Registry Editor Version 5.00

    [HKEY_LOCAL_MACHINE\Software\Autodesk\Inventor\RegistryVersion30.0]
    "ProductVersionMajor"=dword:0000001e
    "BinPath"="C:\\Program Files\\Autodesk\\Inventor 2026\\Bin\\"
    "AppPath"="C:\\Program Files\\Autodesk\\Inventor 2026\\"
    "ClientVersion"="${manifest.inventorVersion}"
    "ProductEdition"="INVPROSA"

    [HKEY_LOCAL_MACHINE\Software\Autodesk\SharedComponents\2026]
    "InstallPath"="C:\\Program Files\\Common Files\\Autodesk Shared\\Components\\2026"
    "Version"="${manifest.componentsVersion}"

    [HKEY_LOCAL_MACHINE\Software\Autodesk\AdskLicensing]
    "Version"="${manifest.licensingVersion}"

    [HKEY_LOCAL_MACHINE\Software\Autodesk\AdskIdentityManager\${manifest.identityVersion}]
    "Location"="C:\\Program Files\\Autodesk\\AdskIdentityManager\\Current"

    [HKEY_LOCAL_MACHINE\Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C72DFB23D8}]
    "pv"="${manifest.webviewVersion}"

    [HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C72DFB23D8}]
    "pv"="${manifest.webviewVersion}"

    [HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment]
    "Path"="C:\\windows\\system32;C:\\windows;C:\\windows\\system32\\wbem;C:\\Program Files\\Common Files\\Autodesk Shared\\Components\\2026\\${manifest.componentsVersion};C:\\Program Files\\Autodesk\\Inventor 2026\\Bin;C:\\Program Files\\dotnet"

    [HKEY_CURRENT_USER\Software\Wine]
    "Version"="win10"

    [HKEY_CURRENT_USER\Control Panel\Desktop]
    "FontSmoothing"="2"
    "FontSmoothingType"=dword:00000002
  '';
  layer = overlayfsLib.mkWindowsPackage {
    inherit runtime src;
    pname = "inventor-2026-import";
    version = manifest.inventorVersion;
    packageName = "inventor-2026";
    extraPathsToInclude =
      map (name: "windows/system32/${name}") [
        "msvcp140.dll"
        "msvcp140_1.dll"
        "msvcp140_2.dll"
        "vcruntime140.dll"
        "vcruntime140_1.dll"
        "concrt140.dll"
        "vcomp140.dll"
        "mfc140u.dll"
        "mfc140.dll"
        "d3dcompiler_47.dll"
      ]
      ++
        lib.concatMap
          (
            directory:
            map (name: "windows/${directory}/${name}") [
              "d3d8.dll"
              "d3d9.dll"
              "d3d10core.dll"
              "d3d11.dll"
              "dxgi.dll"
            ]
          )
          [
            "system32"
            "syswow64"
          ];
    unshareInstall = { session, ... }: /* bash */ ''
      tar --extract --file "$src" --directory "$WINEPREFIX" --no-same-owner
      app="$WINEPREFIX/drive_c/Program Files/Autodesk/Inventor 2026/Bin"
      components="$WINEPREFIX/drive_c/Program Files/Common Files/Autodesk Shared/Components/2026/${manifest.componentsVersion}"
      for dll in "$components"/*.dll; do
        if [ ! -e "$app/$(basename "$dll")" ]; then
          cp "$dll" "$app/"
        fi
      done
      identity="$WINEPREFIX/drive_c/Program Files/Autodesk/AdskIdentityManager/Current"
      agent="$WINEPREFIX/drive_c/Program Files (x86)/Common Files/Autodesk Shared/AdskLicensing/${manifest.licensingVersion}/AdskLicensingAgent"
      mkdir --parents "$agent/SSOPlugin/Current"
      cp "$identity/SSOPlugin/Current/"*.dll "$agent/SSOPlugin/Current/"
      cat > "$agent/IDSDKVersionCompatibility.config" <<'EOF'
      {"ssoClientPlugin":[{"version":"0","module":"IdSDKPlugin.dll","modulePath":"C:\\Program Files (x86)\\Common Files\\Autodesk Shared\\AdskLicensing\\${manifest.licensingVersion}\\AdskLicensingAgent\\SSOPlugin\\Current","compatibleSsoServicesVersion":{"minVersion":"0.0"}}]}
      EOF
      mkdir --parents "$app/Addins/disabled/libs"
      for addin in Anark.Core Autodesk.Feedback.Inventor Autodesk.PerfFeedbackAddin.Inventor \
        Autodesk.SharedViews.Inventor Autodesk.InteractiveTutorial.Inventor Autodesk.Publisher.Inventor \
        autodesk.dynamicsimulation.inventor autodesk.frameanalysis.inventor \
        autodesk.simulationstressanalysis.inventor autodesk.translatorfusion.inventor autodesk.ilogic.inventor; do
        if [ -f "$app/Addins/$addin.addin" ]; then
          mv "$app/Addins/$addin.addin" "$app/Addins/disabled/"
        fi
      done
      for tutorial in "$app/InteractiveTutorial.dll" "$app/en-US/InteractiveTutorial.resources.dll"; do
        if [ -f "$tutorial" ]; then mv "$tutorial" "$app/Addins/disabled/libs/"; fi
      done
      if [ -f "$app/CER/senddmp.exe" ]; then
        mv "$app/CER/senddmp.exe" "$app/CER/senddmp.exe.disabled"
      fi
      tar --extract --file ${dxvkSource}
      cp dxvk-2.7.1/x64/*.dll "$WINEPREFIX/drive_c/windows/system32/"
      cp dxvk-2.7.1/x32/*.dll "$WINEPREFIX/drive_c/windows/syswow64/"
      ${session.commands.wine} reg import ${registry}
      ${session.commands.wineserver} --wait
    '';
  };
  preLaunch = pkgs.writeShellScript "inventor-prelaunch" /* bash */ ''
    set -euo pipefail
    export INVENTOR_LICENSING_VERSION=${lib.escapeShellArg manifest.licensingVersion}
    export INVENTOR_WINE=${runtime.toolsPackage}/bin/wine
    export INVENTOR_UNSHARE=${pkgs.util-linux}/bin/unshare
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnugrep
      ]
    }:"$PATH"
    ${pkgs.bash}/bin/bash ${../scripts/prelaunch.sh}
  '';
  callback = pkgs.writeShellScript "inventor-oauth" /* bash */ ''
    set -euo pipefail
    export INVENTOR_WINE=${runtime.toolsPackage}/bin/wine
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}:"$PATH"
    ${pkgs.bash}/bin/bash ${../scripts/oauth.sh}
  '';
  graphics = overlayfsLib.mkGraphicsBootstrap { inherit runtime; };
  composed = overlayfsLib.composeWindowsLayers {
    inherit runtime;
    packageName = "inventor-2026";
    baseLayer = layer;
    executableName = "inventor";
    executablePath = "/drive_c/Program Files/Autodesk/Inventor 2026/Bin/Inventor.exe";
    workingDirectory = "drive_c/Program Files/Autodesk/Inventor 2026/Bin";
    runtimeEnvVars = {
      WINEDLLOVERRIDES = "d3d8,d3d9,d3d10core,d3d11,dxgi=n;d3dcompiler_47,msvcp140,msvcp140_1,msvcp140_2,vcruntime140,vcruntime140_1,concrt140,vcomp140,mfc140,mfc140u=n,b;msquic=";
      WINE_LARGE_ADDRESS_AWARE = "1";
      DXVK_LOG_LEVEL = "warn";
    };
    urlSchemes = [ "adskidmgr" ];
    urlSchemeOpenCommands = /* bash */ ''
      exec ${callback}
    '';
    extraPreLaunchCommands = graphics.extraPreLaunchCommands + /* bash */ ''
      ${preLaunch} || exit $?
    '';
    entrypointWrapper = entrypoint: /* bash */ ''
      state="''${XDG_DATA_HOME:-$HOME/.local/share}/inventor-2026"
      mkdir --parents "$state"
      chmod 700 "$state"
      if [ "''${1:-}" = --nix-overlayfs-open-url ]; then
        exec ${entrypoint} "$@"
      fi
      exec ${pkgs.util-linux}/bin/flock --nonblock --conflict-exit-code 75 \
        "$state/.launch.lock" ${entrypoint} "$@"
    '';
    extraPostLaunchCommands = /* bash */ ''
      if [ "''${NIX_OVERLAYFS_DIRECT_MODE:-0}" = 1 ]; then
        ${runtime.toolsPackage}/bin/wineserver --kill || true
      else
        ${pkgs.util-linux}/bin/unshare --map-user="$originalUser" ${runtime.toolsPackage}/bin/wineserver --kill || true
      fi
    '';
  };
in
assert manifest.schema == 1;
assert lib.hasPrefix "30." manifest.inventorVersion;
assert lib.all (value: builtins.match "[0-9]+(\\.[0-9]+)+" value != null) [
  manifest.inventorVersion
  manifest.componentsVersion
  manifest.identityVersion
  manifest.licensingVersion
  manifest.webviewVersion
];
composed.overrideAttrs (old: {
  meta = (old.meta or { }) // {
    description = "Experimental Autodesk Inventor Professional 2026 under Wine";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "inventor";
    hydraPlatforms = [ ];
  };
  passthru = (old.passthru or { }) // {
    inherit manifest runtime;
  };
})
