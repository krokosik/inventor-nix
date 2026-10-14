{
  writeShellApplication,
  coreutils,
  xvfb-run,
  wine,
}:
writeShellApplication {
  name = "inventor-wine-probe";
  runtimeInputs = [ coreutils ];
  text = /* bash */ ''
    temp=$(mktemp --directory)
    export WINEPREFIX="$temp/prefix"
    export WINEARCH=wow64
    export WINEDEBUG=-all
    export WINEDLLOVERRIDES="mscoree,mshtml=d"
    cleanup() {
      ${wine}/bin/wineserver --kill || true
      timeout 10s ${wine}/bin/wineserver --wait || true
      rm --recursive --force "$temp"
    }
    trap cleanup EXIT
    timeout 120s ${xvfb-run}/bin/xvfb-run --auto-servernum ${wine}/bin/wineboot --init
    cp ${../checks/wmi.vbs} "$WINEPREFIX/drive_c/probe.vbs"
    timeout 60s ${xvfb-run}/bin/xvfb-run --auto-servernum \
      ${wine}/bin/wine cscript //NoLogo //B 'C:\probe.vbs'
  '';
}
