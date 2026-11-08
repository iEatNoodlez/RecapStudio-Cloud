#!/bin/sh
# Recap Studio Server on a QNAP NAS: App Center starts and stops it with this script (/etc/init.d/RecapStudio.sh).
#   RecapStudio.sh start | stop | restart
#   RecapStudio.sh status        whether it runs, its port, and the setup code while there's no login
#   RecapStudio.sh reset-login   forget the login: the next visit sets it up again (a forgotten password)
# Its options (--allow-plugins, --port 9000...) go in a file named options in the package's folder, on one line.
#
# QTS 5's C library (glibc 2.21, from 2015) is older than Recap Studio's Python and libraries need, so the server
# AppImage brings its own (as MyQNAP's Sonarr does): each of its programs starts through that glibc's loader, by a
# small start script in its place. QTS's own programs keep QTS's glibc. The package holds the AppImage as it is.
#
# The package holds the server AppImage, the same file RecapStudio-Cloud releases for other Linux machines. It's
# unpacked into app/ on the first start, and again whenever the file changes: the app updates itself by putting a
# newer AppImage in its place and closing, and this script starts it again (QTS has no systemd).
#
# In the package's folder (QPKG_ROOT: /share/CACHEDEV1_DATA/.qpkg/RecapStudio, say):
#   data/recap-studio/   settings, the login, logs, add-ons (Recap Studio's data folder)
#   Recap Studio/        the projects, until Settings → Projects folder moves them (to a shared folder, say)
#   logs/recap-studio.log  what the app prints: where it listens, its setup code
#   home/, tmp/, cache/  its home and temporary folders (QTS keeps /root and /tmp in memory)
# Removing the package in App Center deletes this folder, projects included if they're still in it.
#
# Written for BusyBox's sh, as QTS has.

QPKG_NAME=RecapStudio
CONF=/etc/config/qpkg.conf
QPKG_ROOT=
if [ -x /sbin/getcfg ] && [ -f "$CONF" ]; then
  QPKG_ROOT=$(/sbin/getcfg "$QPKG_NAME" Install_Path -f "$CONF")
fi
if [ -z "$QPKG_ROOT" ] || [ ! -d "$QPKG_ROOT" ]; then  # (not installed by App Center: wherever this script is)
  QPKG_ROOT=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
fi

APPIMAGE_FILE=$QPKG_ROOT/recap-studio.AppImage
APP=$QPKG_ROOT/app
LOGS=$QPKG_ROOT/logs
LOG=$LOGS/recap-studio.log
RUN=$QPKG_ROOT/run
WORK=$QPKG_ROOT/.unpack
DATA=$QPKG_ROOT/data/recap-studio
SELF=$QPKG_ROOT/RecapStudio.sh

say() { echo "$(date '+%Y-%m-%d %H:%M:%S') RecapStudio.sh: $*"; }

qts_log() {  # level (0 information, 1 warning, 2 error) message: into QTS's event log (QuLog Center)
  [ -x /sbin/log_tool ] && /sbin/log_tool -t"$1" -uSystem -p127.0.0.1 -mlocalhost -a "[Recap Studio Server] $2"
  return 0
}

ours() {  # pid what: that process is running, and its command line has this in it
  [ -n "$1" ] && [ -r "/proc/$1/cmdline" ] && tr '\000' ' ' < "/proc/$1/cmdline" 2>/dev/null | grep -qF -- "$2"
}

pid_of() { cat "$RUN/$1.pid" 2>/dev/null; }

running() { ours "$(pid_of supervisor)" "$SELF run"; }

# ---- unpacking the AppImage ----

stamp() {  # what tells this AppImage file from another: size, time and inode, or its checksum
  stat -c '%s %Y %i' "$1" 2>/dev/null || cksum < "$1"
}

link_ffmpeg() {  # folder final: the app prefers an ffmpeg on the PATH, so its own goes first on it (QTS's, if there
  d=$1              # is one, may not do all it needs), from where the folder will be
  final=$2
  mkdir -p "$d/bin" || return 1
  for f in "$d"/python/lib/python3*/site-packages/imageio_ffmpeg/binaries/ffmpeg-linux-*; do
    case $f in *.real) continue ;; esac  # (the program itself: its start script is what runs it)
    [ -f "$f" ] && ln -sf "$final${f#"$d"}" "$d/bin/ffmpeg"
  done
  return 0
}

unpack() {  # the AppImage into app/, when app/ isn't from this very file
  [ -f "$APPIMAGE_FILE" ] || { say "$APPIMAGE_FILE is missing: install the package again"; return 1; }
  want=$(stamp "$APPIMAGE_FILE")
  if [ -d "$APP" ] && [ "$(cat "$APP/.from" 2>/dev/null)" = "$want" ]; then
    return 0
  fi
  say "Unpacking $(basename "$APPIMAGE_FILE") into app/ (a minute or two)"
  chmod 755 "$APPIMAGE_FILE"
  rm -rf "$WORK"
  mkdir -p "$WORK" || return 1
  # (the AppImage's runtime is a static program: it runs on QTS as it is, and unpacks itself without FUSE)
  if ! (cd "$WORK" && "$APPIMAGE_FILE" --appimage-extract > /dev/null); then
    say "The AppImage didn't unpack (is the volume full?)"
    rm -rf "$WORK"
    return 1
  fi
  new=$WORK/squashfs-root
  if [ ! -f "$new/SERVER" ] || [ ! -e "$new/python/bin/python3" ] || [ ! -d "$new/glibc" ]; then
    say "$(basename "$APPIMAGE_FILE") isn't Recap Studio's server AppImage (0.4.1 or later, with its own glibc)"
    rm -rf "$WORK"
    return 1
  fi
  link_ffmpeg "$new" "$APP" || { say "Couldn't set up the unpacked app"; rm -rf "$WORK"; return 1; }
  printf '%s\n' "$want" > "$new/.from"
  rm -rf "$APP.old"
  [ -d "$APP" ] && mv "$APP" "$APP.old"
  mv "$new" "$APP" || return 1
  rm -rf "$APP.old" "$WORK"
  say "Unpacked Recap Studio $(cat "$APP/VERSION" 2>/dev/null)"
}

# ---- running it ----

app_env() {  # (in a subshell) the app's folders and settings: in the package's folder, apart from QTS's own
  cd "$APP" || return 1
  unset PYTHONHOME PYTHONPATH PYTHONSTARTUP VIRTUAL_ENV LD_LIBRARY_PATH LD_PRELOAD
  export PYTHONNOUSERSITE=1
  export APPDIR="$APP" APPIMAGE="$APPIMAGE_FILE"  # (how the app finds the file it updates)
  export RECAP_CODE_PLACE="QTS's event log (QuLog Center), or $LOG"
  export HOME="$QPKG_ROOT/home" TMPDIR="$QPKG_ROOT/tmp"
  export XDG_DATA_HOME="$QPKG_ROOT/data" XDG_CACHE_HOME="$QPKG_ROOT/cache"
  export XDG_CONFIG_HOME="$QPKG_ROOT/home/.config" XDG_DOCUMENTS_DIR="$QPKG_ROOT"
  export LANG=C.UTF-8 LC_ALL=C.UTF-8
  export PATH="$APP/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
  certs=$(ls "$APP"/python/lib/python3*/site-packages/certifi/cacert.pem 2>/dev/null | head -n 1)
  [ -n "$certs" ] && export SSL_CERT_FILE="$certs"  # (Python's own certificates: QTS keeps its elsewhere)
  return 0
}

reset_login() {  # --reset-login: the next visit sets the login up again, with a new setup code
  [ -d "$APP" ] || { echo "Recap Studio hasn't started yet: start it first."; return 1; }
  (app_env && exec "$APP/python/bin/python3" -m recap --reset-login) || return 1
  # started again, so the new code goes to QTS's event log too
  if running; then stop > /dev/null; start; fi
}

watch_code() {  # log-offset app-pid: the setup code the app prints goes to QTS's event log as well
  n=0
  while [ $n -lt 300 ]; do
    code=$(tail -c +$(($1 + 1)) "$LOG" 2>/dev/null |
      sed -n 's/.*setup code[^A-Z0-9]*\([A-Z0-9]\{4\}-[A-Z0-9]\{4\}-[A-Z0-9]\{4\}\).*/\1/p' | tail -n 1)
    if [ -n "$code" ]; then
      qts_log 0 "The setup code for its first visit: $code"
      return 0
    fi
    kill -0 "$2" 2>/dev/null || return 0
    sleep 2
    n=$((n + 2))
  done
}

run() {  # the loop that keeps the app running (start puts it in the background)
  apppid=
  trap 'touch "$RUN/stop"; [ -n "$apppid" ] && kill -TERM "$apppid" 2>/dev/null' TERM INT
  trap '' HUP
  while [ ! -f "$RUN/stop" ]; do
    if ! unpack; then
      qts_log 2 "It couldn't be unpacked: see $LOG"
      sleep 60
      continue
    fi
    link_ffmpeg "$APP" "$APP"  # (again each time: the package may have been moved to another volume)
    started=$(date +%s)
    from=$(wc -c < "$LOG" 2>/dev/null || echo 0)
    # (options: a file of that name in the package's folder, on one line: --allow-plugins, --port 9000...)
    opts=$(head -n 1 "$QPKG_ROOT/options" 2>/dev/null)
    (
      app_env || exit 1
      export RECAP_SUPERVISED=1  # (a restart only closes it: this loop starts it again)
      # shellcheck disable=SC2086
      exec "$APP/python/bin/python3" -m recap --server $opts
    ) < /dev/null &
    apppid=$!
    printf '%s\n' "$apppid" > "$RUN/app.pid"
    watch_code "$from" "$apppid" &
    wait "$apppid"
    status=$?
    while kill -0 "$apppid" 2>/dev/null; do  # (a signal came in while waiting: wait for the app itself)
      wait "$apppid"
      status=$?
    done
    apppid=
    rm -f "$RUN/app.pid"
    stop_leftovers
    [ -f "$RUN/stop" ] && break
    say "Recap Studio closed ($status): starting it again"
    # (not right away when it failed soon after starting, so a start that fails doesn't go round and round; a
    # restart it asked for, after an update say, ends with 0)
    [ "$status" != 0 ] && [ $(($(date +%s) - started)) -lt 30 ] && sleep 10
  done
  rm -f "$RUN/supervisor.pid"
}

stop_leftovers() {  # anything still running from app/ (a video it was making, a plugin's process), or unpacking
  for p in /proc/[0-9]*; do
    p=${p#/proc/}
    [ "$p" = "$$" ] && continue
    { ours "$p" "$APP/" || ours "$p" "$APPIMAGE_FILE --appimage-extract"; } && kill -TERM "$p" 2>/dev/null
  done
  sleep 1
  for p in /proc/[0-9]*; do
    p=${p#/proc/}
    [ "$p" = "$$" ] && continue
    { ours "$p" "$APP/" || ours "$p" "$APPIMAGE_FILE --appimage-extract"; } && kill -KILL "$p" 2>/dev/null
  done
  return 0
}

port_of() {  # the port the app listens on, for App Center's Open button: the options' --port, else Settings → Server's
  p=$(sed -n 's/.*--port[ =]*\([0-9][0-9]*\).*/\1/p' "$QPKG_ROOT/options" 2>/dev/null | head -n 1)
  [ -n "$p" ] || p=$(sed -n 's/.*"port"[^0-9]*\([0-9][0-9]*\).*/\1/p' "$DATA/server.json" 2>/dev/null | head -n 1)
  echo "${p:-8780}"
}

start() {
  if [ -x /sbin/getcfg ] && [ -f "$CONF" ] &&
     [ "$(/sbin/getcfg "$QPKG_NAME" Enable -u -d FALSE -f "$CONF")" != TRUE ]; then
    echo "$QPKG_NAME is disabled."
    exit 1
  fi
  if running; then
    echo "Recap Studio Server is running already."
    return 0
  fi
  mkdir -p "$LOGS" "$RUN" "$QPKG_ROOT/data" "$QPKG_ROOT/home" "$QPKG_ROOT/tmp" "$QPKG_ROOT/cache" || exit 1
  chmod 700 "$QPKG_ROOT/data" "$QPKG_ROOT/home"
  rm -f "$RUN/stop"
  if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 5000000 ]; then
    mv -f "$LOG" "$LOG.1"
  fi
  port=$(port_of)
  [ -x /sbin/setcfg ] && [ -f "$CONF" ] && /sbin/setcfg "$QPKG_NAME" Web_Port "${port:-8780}" -f "$CONF"
  say "Starting" >> "$LOG"
  # the loop, in a session of its own so it outlives App Center's call
  if command -v setsid > /dev/null; then
    setsid /bin/sh "$SELF" run < /dev/null >> "$LOG" 2>&1 &
  else
    /bin/sh "$SELF" run < /dev/null >> "$LOG" 2>&1 &
  fi
  printf '%s\n' "$!" > "$RUN/supervisor.pid"
  echo "Recap Studio Server is starting (its log: $LOG)."
}

stop() {
  mkdir -p "$RUN"
  touch "$RUN/stop"
  app=$(pid_of app)
  if ours "$app" "$APP/"; then
    kill -TERM "$app" 2>/dev/null
    n=0
    while ours "$app" "$APP/" && [ $n -lt 30 ]; do sleep 1; n=$((n + 1)); done
    ours "$app" "$APP/" && kill -KILL "$app" 2>/dev/null
  fi
  sup=$(pid_of supervisor)
  n=0
  while ours "$sup" "$SELF run" && [ $n -lt 10 ]; do sleep 1; n=$((n + 1)); done
  ours "$sup" "$SELF run" && kill -KILL "$sup" 2>/dev/null
  stop_leftovers
  rm -f "$RUN/supervisor.pid" "$RUN/app.pid"
  say "Stopped" >> "$LOG" 2>/dev/null
  echo "Recap Studio Server is stopped."
}

status() {
  if ! running; then
    echo "Recap Studio Server isn't running."
    return 1
  fi
  port=$(port_of)
  echo "Recap Studio Server is running, on port ${port:-8780} (its log: $LOG)."
  if ! grep -q '"password"' "$DATA/server.json" 2>/dev/null; then
    code=$(sed -n 's/.*setup code[^A-Z0-9]*\([A-Z0-9]\{4\}-[A-Z0-9]\{4\}-[A-Z0-9]\{4\}\).*/\1/p' "$LOG" | tail -n 1)
    [ -n "$code" ] && echo "Its login isn't set up yet. The setup code for the first visit: $code"
  fi
  return 0
}

case "$1" in
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  status) status ;;
  reset-login) reset_login ;;
  run) run ;;
  remove) stop ;;
  *) echo "Usage: $0 {start|stop|restart|status|reset-login}"; exit 1 ;;
esac
exit $?
