#!/usr/bin/env bash
# Build Recap Studio Server's QNAP package from the server AppImage:
#   qnap/build-qpkg.sh dist/Recap-Studio-Server-Lite-0.4.1-x86_64.AppImage [out-folder]
#     → Recap-Studio-Server-Lite-0.4.1-x86_64.qpkg (beside the AppImage, or in out-folder)
# The package is for the AppImage's architecture: x86_64, or aarch64 for QNAP's 64-bit ARM models (QDK's arm_64).
# An AppImage of this machine's kind is unpacked by running it; one of another kind with unsquashfs (squashfs-tools),
# so the workflow builds both on its x86_64 runner.
#
# The package holds the AppImage as it is. QTS 5's glibc (2.21) is too old for the app, but the server AppImage
# brings its own (RecapStudio's packaging/linux/own_glibc.sh, from 0.4.1), so the package needs nothing more: on
# the NAS, RecapStudio.sh unpacks it and keeps the app running.
#
# Needs: bash and QNAP's QDK for qbuild (github.com/qnap-dev/QDK: its .deb, as the workflow installs it).
#
#   qnap/build-qpkg.sh <AppImage> --folder <folder>   QDK's build folder (what qbuild builds from) in that folder,
#                                                      without building: for qbuild elsewhere, such as on the NAS
#                                                      with QDK installed there, where the folder has to sit inside
#                                                      QDK's own folder (qbuild finds its files through the working
#                                                      directory's path): App/qnap-dev's build_on_nas.sh does that
#   qnap/build-qpkg.sh <AppImage> --tree <folder>     (for testing) only the files the package installs on the NAS,
#                                                      in that folder, as App Center puts them: no QDK needed
set -euo pipefail

TREE=""
FOLDER=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --tree) TREE="$(realpath -m "$2")"; shift 2 ;;
    --folder) FOLDER="$(realpath -m "$2")"; shift 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
APPIMAGE="$(readlink -f "${ARGS[0]:?Usage: build-qpkg.sh <server AppImage> [out-folder]}")"
OUT_DIR="$(realpath -m "${ARGS[1]:-$(dirname "$APPIMAGE")}")"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -n "$TREE$FOLDER" ] || command -v qbuild > /dev/null ||
  { echo "qbuild isn't installed: QNAP's QDK (github.com/qnap-dev/QDK)"; exit 1; }
# the AppImage's architecture, from its ELF header (e_machine), and QDK's name for it
case "$(od -An -tx1 -j18 -N2 "$APPIMAGE" | tr -d ' \n')" in
  3e00) ARCH=x86_64; QARCH=x86_64 ;;
  b700) ARCH=aarch64; QARCH=arm_64 ;;
  *) echo "$(basename "$APPIMAGE") is for neither x86_64 nor aarch64"; exit 1 ;;
esac

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
echo "== The AppImage"
D="$W/squashfs-root"
if [ "$ARCH" = "$(uname -m)" ]; then
  run="$APPIMAGE"
  if [ ! -x "$run" ]; then  # (a download, such as a workflow's artifact, can lose its execute bit)
    run="$W/recap-studio.AppImage"; cp "$APPIMAGE" "$run"; chmod 755 "$run"
  fi
  (cd "$W" && "$run" --appimage-extract > /dev/null)
else
  # its squashfs starts where the runtime's ELF ends: after the section headers, which come last
  command -v unsquashfs > /dev/null || { echo "unsquashfs (squashfs-tools) unpacks an $ARCH AppImage here"; exit 1; }
  u() { od -An -tu"$1" -j"$2" -N"$1" "$APPIMAGE" | tr -d ' \n'; }
  off=$(( $(u 8 40) + $(u 2 58) * $(u 2 60) ))
  [ "$(dd if="$APPIMAGE" bs=1 skip="$off" count=4 2> /dev/null)" = hsqs ] ||
    { echo "No squashfs at $off in $(basename "$APPIMAGE")"; exit 1; }
  unsquashfs -no-progress -quiet -o "$off" -d "$D" "$APPIMAGE" > /dev/null
fi
[ -f "$D/SERVER" ] || { echo "$(basename "$APPIMAGE") isn't the server AppImage (build.sh --server)"; exit 1; }
VERSION="$(cat "$D/VERSION")"
EDITION="$(cat "$D/EDITION")"
case "$EDITION" in
  full) NAME=Full; DISPLAY="Recap Studio Server (Full Suite)" ;;
  *) NAME=Lite; DISPLAY="Recap Studio Server" ;;
esac
# QTS and App Center take a version of digits and dots
QPKG_VER="$(printf '%s' "$VERSION" | sed 's/[^0-9.].*//')"
echo "Recap Studio $VERSION, $NAME, $ARCH"

[ -d "$D/glibc" ] ||
  { echo "$(basename "$APPIMAGE") doesn't bring its own glibc: one built with RecapStudio's packaging from 0.4.1 on"; exit 1; }
if [ "$ARCH" = "$(uname -m)" ]; then
  "$D/python/bin/python3" --version > /dev/null || { echo "Its Python doesn't start here"; exit 1; }
fi
echo "It brings its own $(cat "$D/glibc/VERSION")"
Q="$W/qpkg"
mkdir -p "$Q/$QARCH"

echo "== The package"
cp "$HERE/qpkg.cfg" "$HERE/package_routines" "$Q/"
sed -i -e "s/^QPKG_VER=.*/QPKG_VER=\"$QPKG_VER\"/" -e "s/^QPKG_DISPLAY_NAME=.*/QPKG_DISPLAY_NAME=\"$DISPLAY\"/" \
  "$Q/qpkg.cfg"
mkdir -p "$Q/shared" "$Q/icons"
cp "$HERE/shared/RecapStudio.sh" "$Q/shared/"
chmod 755 "$Q/shared/RecapStudio.sh"
cp "$HERE"/icons/RecapStudio*.gif "$Q/icons/"
cp "$APPIMAGE" "$Q/$QARCH/recap-studio.AppImage"
chmod 755 "$Q/$QARCH/recap-studio.AppImage"
if [ -n "$TREE" ]; then  # (App Center puts shared/ and the NAS's own architecture's folder together)
  mkdir -p "$TREE"
  cp -a "$Q/shared/." "$Q/$QARCH/." "$TREE/"
  echo "Done: the package's files in $TREE"
  exit 0
fi
if [ -n "$FOLDER" ]; then
  [ ! -e "$FOLDER" ] || [ -z "$(ls -A "$FOLDER")" ] || { echo "$FOLDER exists and isn't empty"; exit 1; }
  mkdir -p "$FOLDER"
  cp -a "$Q/." "$FOLDER/"
  echo "Done: QDK's build folder in $FOLDER. In it, qbuild builds the package into build/."
  exit 0
fi
(cd "$Q" && qbuild --build-arch "$QARCH" --build-dir "$W/build" > "$W/qbuild.log" 2>&1) ||
  { cat "$W/qbuild.log"; exit 1; }
BUILT="$(ls "$W"/build/*.qpkg | head -n 1)"

# The header qbuild writes stays as it is: two packages with its lines changed failed in App Center ("data file
# error"). Its data copy, "dd | cat | dd bs=1024 count=N" from a pipe, came out exact on the NAS, but off it (GNU's
# dd or BusyBox's, in Docker) it can come out short: dd counts a short read from a pipe as a whole block. So check a
# package by its bytes, cut at the offsets the header gives (App/qnap-dev's check_qpkg.sh), not by running its lines.
OUT="$OUT_DIR/Recap-Studio-Server-$NAME-$VERSION-$ARCH.qpkg"
mkdir -p "$OUT_DIR"
mv -f "$BUILT" "$OUT"
echo "Done: $OUT ($(du -h "$OUT" | cut -f1))"
