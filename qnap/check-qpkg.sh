#!/bin/sh
# Check a built .qpkg by its bytes, cut at the offsets its header gives: its control files, its data whole, the
# service script and the AppImage in it, the AppImage the same as the one it was built from. Exits 1 if anything is
# off. (Running the header's own unpacking lines isn't a check off QTS: their last dd reads a pipe and counts a short
# read as a whole block, so the data can come out short here though it's whole on the NAS.)
#   qnap/check-qpkg.sh <.qpkg> <the AppImage it was built from>
Q=$1; AI=$2
X=$(mktemp -d)
trap 'rm -rf "$X"' EXIT
bad() { echo "$(basename "$Q"): $*"; exit 1; }
sl=$(grep -a -m1 '^script_len=' "$Q" | cut -d= -f2)
want=$(grep -a -m1 '^offset=$(/usr/bin/expr $offset + ' "$Q" | sed 's/.*+ \([0-9]*\)).*/\1/')
[ -n "$sl" ] && [ -n "$want" ] || bad "no unpacking lines in its header"
off=$((sl + 20480))
mkdir "$X/c" "$X/d"
tail -c +$((sl + 1)) "$Q" | head -c 20480 | tar -xO | tar -xz -C "$X/c" || bad "its control files don't unpack"
for f in qinstall.sh qpkg.cfg package_routines; do [ -f "$X/c/$f" ] || bad "no $f"; done
tail -c +$((off + 1)) "$Q" | head -c "$want" > "$X/data.tar.gz"
[ "$(wc -c < "$X/data.tar.gz")" -eq "$want" ] || bad "its data is shorter than its header says"
gzip -t "$X/data.tar.gz" || bad "its data isn't whole"
tar xzf "$X/data.tar.gz" -C "$X/d" || bad "its data doesn't unpack"
[ -x "$X/d/RecapStudio.sh" ] || bad "no RecapStudio.sh"
[ "$(md5sum < "$X/d/recap-studio.AppImage")" = "$(md5sum < "$AI")" ] || bad "the AppImage in it isn't $(basename "$AI")"
echo "$(basename "$Q"): whole ($(wc -c < "$Q") bytes); $(grep -E '^QPKG_(NAME|VER|DISPLAY_NAME)=' "$X/c/qpkg.cfg" | tr '\n' ' ')"
