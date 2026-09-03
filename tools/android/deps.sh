#!/bin/sh
# deps.sh: fetch the pinned raylib source tree.
#
#   sh tools/android/deps.sh
#
# That is all this does. Unlike the iOS recipe, nothing is cross-built here:
# raylib has a first-class Android backend (src/platforms/rcore_android.c), and
# the APK's own CMake build compiles it from these sources straight into
# libmain.so along with main.c. So there is no static archive to keep in step
# with an SDK, and no second copy of raylib for a simulator.
#
# The tree is pinned by full revision, not by tag, and lands in
# ~/dev/raylib-<revision> so a raylib checkout you already have is left alone.
set -eu

# shellcheck source=tools/android/common.sh
. "$(dirname "$0")/common.sh"

if [ -f "$RAYLIB_SRC/src/platforms/rcore_android.c" ]; then
  echo "deps.sh: raylib $RAYLIB_REVISION already at $RAYLIB_SRC"
else
  echo "deps.sh: fetching raylib $RAYLIB_REVISION"
  mkdir -p "$DEV"
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/raylib-src.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT INT TERM
  curl -sfL "https://github.com/raysan5/raylib/archive/$RAYLIB_REVISION.tar.gz" \
    | tar xz -C "$tmp"
  # The archive unpacks to raylib-<revision>; move it into place atomically
  # enough that an interrupted download cannot leave a half tree that the next
  # run would accept.
  mv "$tmp/raylib-$RAYLIB_REVISION" "$RAYLIB_SRC"
fi

# Verify rather than assume. A truncated or wrong-revision tree fails much
# later, inside CMake, with an error about a missing platform file.
for f in src/rcore.c src/platforms/rcore_android.c src/raylib.h cmake/LibraryConfigurations.cmake; do
  [ -f "$RAYLIB_SRC/$f" ] || die "$RAYLIB_SRC is not a complete raylib tree (no $f)"
done

version=$(sed -n 's/^#define RAYLIB_VERSION  *"\([^"]*\)".*/\1/p' "$RAYLIB_SRC/src/raylib.h")
echo "deps.sh: raylib $version at $RAYLIB_SRC"
case "$version" in
  6.*) ;;
  *) die "this port is written against raylib 6.x; that tree says '$version'" ;;
esac

# The one line the rest of the tooling needs, asserted here so a mismatch
# shows up now rather than as an unexplained black screen: raylib's Android
# entry contract is a plain main(), which tools/android/app/src/main/cpp/main.c
# implements.
grep -q 'extern int main(int argc, char \*argv\[\])' "$RAYLIB_SRC/src/platforms/rcore_android.c" \
  || die "rcore_android.c no longer declares 'extern int main': re-read the entry contract before building"

echo "deps.sh: ok. RAYLIB_SOURCE=$RAYLIB_SRC (build.sh exports this for you)"
