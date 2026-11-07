#!/bin/sh
# Recap Studio Server's container: runs the app (its arguments) as PUID:PGID, 1000:1000 unless they're set, with its
# data in /data. Started as root (the default), it makes /data that user's first: a folder Docker makes for a volume
# is root's. Started as another user already (compose's user:), it runs as that user.
set -e
PUID=${PUID:-1000}
PGID=${PGID:-1000}
case "$PUID$PGID" in *[!0-9]*) echo "PUID and PGID are numbers, not $PUID and $PGID" >&2; exit 2 ;; esac
if [ "$(id -u)" = 0 ] && [ "$PUID" != 0 ]; then
  mkdir -p /data
  # (some volumes can't change owner, a Windows folder's say: then it's used as it is)
  [ "$(stat -c %u:%g /data)" = "$PUID:$PGID" ] || chown "$PUID:$PGID" /data ||
    echo "Couldn't make /data $PUID:$PGID's: if Recap Studio can't write there, change its owner, or PUID and PGID" >&2
  exec setpriv --reuid="$PUID" --regid="$PGID" --clear-groups -- "$@"
fi
exec "$@"
