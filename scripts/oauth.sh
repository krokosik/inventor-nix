# Executed by nix-overlayfs in the active Wine session, never a second prefix.
set -euo pipefail
case "${callback_url:-}" in
  adskidmgr://*) ;;
  *) printf 'Invalid Autodesk callback scheme\n' >&2; exit 2 ;;
esac

hex_user=$(printf '%s' "${originalUser:-$USER}" | od --address-radix=n --format=x1 | tr --delete ' \n' | tr '[:lower:]' '[:upper:]')
ipc="$WINEPREFIX/drive_c/ProgramData/Autodesk/IDSDK/$hex_user/interprocess/01000000"
for event in "$ipc"/IDSDKQuit-v2-*; do
  [ -f "$event" ] || continue
  pid="${event##*v2-}"
  case "$pid" in ''|*[!0-9]*) continue ;; esac
  if [ ! -f "$ipc/AdOAuth2Code-$pid" ]; then
    printf '\001\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000' > "$ipc/AdOAuth2Code-$pid"
  fi
done
exec "$INVENTOR_WINE" 'C:\Program Files\Autodesk\AdskIdentityManager\Current\AdskIdentityManager.exe' "$callback_url"
