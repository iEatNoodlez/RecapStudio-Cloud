#!/usr/bin/env bash
# Install Recap Studio's server on this Linux machine, as a systemd service that starts at boot.
#
#   curl -fsSLO https://raw.githubusercontent.com/iEatNoodlez/RecapStudio-Cloud/main/install.sh
#   less install.sh                       # read it first: it runs as root
#   sudo bash install.sh                  # Full Suite (the app with Recap Studio's plugins), on port 8780
#   sudo bash install.sh lite --port 9000
#   sudo bash install.sh --uninstall      # the service and the app; your projects and settings stay
#   sudo bash install.sh --uninstall --purge   # those too
#
# What it does:
#   - makes a system user, recap-studio, that the server runs as (its home: /var/lib/recap-studio);
#   - downloads the latest server AppImage from RecapStudio-Cloud's releases, checks it against the SHA-256 GitHub
#     lists for it, and puts it in /opt/recap-studio (the server's own user may change it: it updates itself there);
#   - writes /etc/systemd/system/recap-studio.service and starts it;
#   - prints the address and the setup code the first visit asks for.
# Settings, API keys and the voice model go in /var/lib/recap-studio/recap-studio, projects in
# /var/lib/recap-studio/Recap Studio (Settings → Projects folder moves them).
set -euo pipefail

REPO="iEatNoodlez/RecapStudio-Cloud"
API="${RECAP_RELEASE_API:-https://api.github.com/repos/$REPO/releases/latest}"  # (another address: testing)
APP_USER="recap-studio"
APP_DIR="/opt/recap-studio"
DATA_DIR="/var/lib/recap-studio"
APPIMAGE="$APP_DIR/recap-studio.AppImage"
SERVICE="/etc/systemd/system/recap-studio.service"

EDITION="full"
PORT="8780"
UNINSTALL=""
PURGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    full|lite) EDITION="$1"; shift ;;
    --port) PORT="$2"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    --purge) PURGE=1; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (see sudo bash $0 --help)"; exit 2 ;;
  esac
done

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf 'Not installed: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run it as root: sudo bash $0"
if [ -f /etc/config/uLinux.conf ] && [ -x /sbin/getcfg ]; then  # (QTS: no systemd, and App Center keeps its packages)
  die "this is a QNAP NAS: install the .qpkg from the releases with App Center instead (the README's On a QNAP NAS)"
fi
command -v systemctl > /dev/null || die "this machine doesn't use systemd: run it with Docker (the README's With Docker), or start the AppImage with --server from a service of your own"

if [ -n "$UNINSTALL" ]; then
  say "Removing Recap Studio's server"
  systemctl disable --now recap-studio.service 2> /dev/null || true
  rm -f "$SERVICE"
  systemctl daemon-reload
  rm -rf "$APP_DIR"
  if [ -n "$PURGE" ]; then
    rm -rf "$DATA_DIR"
    userdel "$APP_USER" 2> /dev/null || true
    say "Removed, with its projects and settings."
  else
    say "Removed. Your projects and settings are still in $DATA_DIR (--purge removes them too)."
  fi
  exit 0
fi

ARCH="$(uname -m)"  # (the release's file names use the same words)
case "$ARCH" in
  x86_64|aarch64) ;;
  *) die "the server is built for 64-bit PCs (x86_64) and 64-bit ARM (aarch64), and this is $ARCH" ;;
esac
[[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die "$PORT isn't a port"
for tool in curl sha256sum python3; do
  command -v "$tool" > /dev/null || die "it needs $tool (install it with your package manager first)"
done

say "Finding the latest release"
case "$EDITION" in full) NAME=Full ;; lite) NAME=Lite ;; esac
release="$(curl -fsSL -H "Accept: application/vnd.github+json" "$API")" || die "GitHub didn't answer"
read -r VERSION URL SHA256 < <(printf '%s' "$release" | NAME="$NAME" ARCH="$ARCH" python3 -c '
import json, os, re, sys
r = json.load(sys.stdin)
for a in r.get("assets", []):
    if re.fullmatch(r"Recap-Studio-Server-%s-.+-%s\.AppImage" % (os.environ["NAME"], os.environ["ARCH"]), a["name"]):
        print(r["tag_name"].lstrip("v"), a["browser_download_url"], (a.get("digest") or "").removeprefix("sha256:"))
        break
') || true
[ -n "${URL:-}" ] || die "the latest release has no $NAME server AppImage for $ARCH"
[ -n "${SHA256:-}" ] || die "GitHub lists no checksum for it, so it can't be checked"

say "Downloading Recap Studio Server $NAME $VERSION"
mkdir -p "$APP_DIR"
curl -fL --retry 3 --progress-bar -o "$APP_DIR/.download" "$URL" || die "the download failed"
echo "$SHA256  $APP_DIR/.download" | sha256sum -c --status || { rm -f "$APP_DIR/.download"; die "the download doesn't match its SHA-256"; }
chmod 755 "$APP_DIR/.download"
mv -f "$APP_DIR/.download" "$APPIMAGE"

say "Its user, $APP_USER"
if ! id "$APP_USER" > /dev/null 2>&1; then
  useradd --system --home-dir "$DATA_DIR" --create-home --shell /usr/sbin/nologin "$APP_USER" \
    || useradd --system --home-dir "$DATA_DIR" --create-home --shell /sbin/nologin "$APP_USER"
fi
mkdir -p "$DATA_DIR"
chown "$APP_USER:" "$DATA_DIR"
chmod 750 "$DATA_DIR"
chown -R "$APP_USER:" "$APP_DIR"  # (it updates itself there)

# An AppImage mounts itself with FUSE; without it, it unpacks itself to start (slower, the same otherwise)
EXTRACT=""
if [ ! -e /dev/fuse ] || ! { command -v fusermount3 || command -v fusermount; } > /dev/null; then
  EXTRACT="Environment=APPIMAGE_EXTRACT_AND_RUN=1"
  say "No FUSE here: the AppImage unpacks itself each time it starts"
fi

say "The service"
cat > "$SERVICE" <<EOF
# Recap Studio's server (RecapStudio-Cloud's install.sh). Its settings, API keys and projects are in $DATA_DIR.
[Unit]
Description=Recap Studio server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$DATA_DIR
Environment=HOME=$DATA_DIR
Environment=XDG_DATA_HOME=$DATA_DIR
Environment=XDG_DOCUMENTS_DIR=$DATA_DIR
$EXTRACT
ExecStart=$APPIMAGE --server --port $PORT
# (Restart and updates end the app; systemd starts it again, from the new AppImage after an update)
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable recap-studio.service > /dev/null
systemctl restart recap-studio.service

say "Starting"
code=""
for _ in $(seq 1 60); do
  sleep 1
  code="$(journalctl -u recap-studio.service --since "-2min" --no-pager -o cat 2> /dev/null \
    | grep -oE 'setup code[^A-Z0-9]*[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}' | tail -1 | grep -oE '[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}' || true)"
  if [ -n "$code" ] || journalctl -u recap-studio.service --since "-2min" --no-pager -o cat 2> /dev/null | grep -q "running as a server"; then
    break
  fi
done
host="$(hostname -I 2> /dev/null | awk '{print $1}')"
echo
say "Recap Studio Server $NAME $VERSION is installed."
echo "  Open:        http://${host:-this-machine}:$PORT/"
if [ -n "$code" ]; then
  echo "  Setup code:  $code   (the first visit asks for it, then for a username and password)"
else
  echo "  It's already set up, or still starting: journalctl -u recap-studio shows its setup code if it asks."
fi
echo "  Its log:     journalctl -u recap-studio -f"
echo "  Stop/start:  sudo systemctl stop recap-studio / sudo systemctl start recap-studio"
echo "Reach it from outside your home network through Tailscale or a reverse proxy with HTTPS, never an open port."
