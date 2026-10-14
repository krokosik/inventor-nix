# Executed inside the mounted overlay. All Wine commands use the launch UID.
set -euo pipefail
: "${originalUser:?nix-overlayfs must provide originalUser}"
: "${appdir:?nix-overlayfs must provide appdir}"

wine_command() {
  if [ "${NIX_OVERLAYFS_DIRECT_MODE:-0}" = 1 ]; then
    "$INVENTOR_WINE" "$@"
  else
    "$INVENTOR_UNSHARE" --map-user="$originalUser" "$INVENTOR_WINE" "$@"
  fi
}

hex_user=$(printf '%s' "$originalUser" | od --address-radix=n --format=x1 | tr --delete ' \n' | tr '[:lower:]' '[:upper:]')
ipc="$WINEPREFIX/drive_c/ProgramData/Autodesk/IDSDK/$hex_user/interprocess"
rm --recursive --force "$ipc"
mkdir --parents "$ipc"

logs="$appdir/.nix-overlayfs/logs"
mkdir --parents "$logs"
chmod 700 "$appdir/.nix-overlayfs" "$logs"
service_log="$WINEPREFIX/drive_c/users/$originalUser/AppData/Local/Autodesk/Identity Services/Log/IdServices.log"
if [ -f "$service_log" ]; then
  mv "$service_log" "$logs/identity-previous.log"
fi
wine_command 'C:\Program Files\Autodesk\AdskIdentityManager\Current\AdskIdentityManager.exe' > "$logs/identity-wine.log" 2>&1 &
identity_pid=$!
ready=0
for ((attempt = 0; attempt < 60; attempt++)); do
  if grep --quiet 'SSO Server is ready' "$service_log" 2>/dev/null; then
    ready=1
    break
  fi
  if ! kill -0 "$identity_pid" 2>/dev/null; then
    break
  fi
  sleep 1
done
if [ "$ready" != 1 ]; then
  printf 'Identity Manager failed readiness check; see %s\n' "$logs" >&2
  exit 1
fi

licensing_executable="C:\\Program Files (x86)\\Common Files\\Autodesk Shared\\AdskLicensing\\$INVENTOR_LICENSING_VERSION\\AdskLicensingService\\AdskLicensingService.exe"
wine_command "$licensing_executable" > "$logs/licensing-wine.log" 2>&1 &
licensing_pid=$!
sleep 5
if ! kill -0 "$licensing_pid" 2>/dev/null; then
  printf 'Licensing service exited during startup; see %s\n' "$logs" >&2
  exit 1
fi
