#!/bin/sh
# pack.sh: build the Chez target pack that `jolt build --target tarm64le` needs.
#
#   sh tools/android/pack.sh
#
# Roughly fifteen minutes, almost all of it Chez, and cached in
# ~/.cache/raylib-android afterwards. What comes out is one directory holding
# the target's boot files, its C kernel, the cross xpatch that retargets the
# host compiler, static lz4 and zlib, and a link-libs line -- the layout jolt's
# tools/cross-compile/make-pack.sh documents. That script is not used here
# because it is the only thing this project would need a jolt CHECKOUT for, and
# because its Linux link-libs line is wrong for Android (see below).
#
# Two things make this pack Android's rather than glibc Linux's, since Chez has
# no Android machine type -- jolt's cross-compile README says as much:
#
#   1. the kernel is compiled by the NDK's API-level clang wrapper, so it links
#      against Bionic and carries that minimum version, and
#   2. link-libs names only -llz4 -lz -lm -ldl. jolt's own *le default adds
#      -lrt and -lpthread, which glibc has and Bionic folds into libc: naming
#      them fails the link.
#
# -fPIC is not optional. `--library` folds libkernel.a, lz4 and zlib into a
# shared object, so all three have to be position-independent.
set -eu

# shellcheck source=tools/android/common.sh
. "$(dirname "$0")/common.sh"

API=$(android_api)
NDK=$(android_ndk)
PACK=${PACK:-$WORK/pack/$TARGET_MACHINE-api$API}

# Gate on link-libs rather than the directory: the pack directory exists from
# the first cp, long before the pack is usable, and a half-built one would sail
# past a -d test and fail twenty minutes later at the app link.
if [ -f "$PACK/link-libs" ]; then
  echo "pack.sh: target pack already built: $PACK"
  exit 0
fi

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  HOST_MACHINE=ta6le ;;
  Darwin-arm64)  HOST_MACHINE=tarm64osx ;;
  Darwin-x86_64) HOST_MACHINE=ta6osx ;;
  Linux-aarch64)
    die "an arm64 Linux host cannot build this pack: Chez has one machine type
  for both sides (tarm64le), so the host build and the Android cross-build
  would share a directory and overwrite each other. Build the pack on an
  x86_64 Linux machine or an Apple Silicon Mac and copy it to $PACK." ;;
  *) die "unsupported build host: $(uname -s)-$(uname -m)" ;;
esac

CC=$(ndk_bin "$NDK" "aarch64-linux-android$API-clang")
AR=$(ndk_bin "$NDK" llvm-ar)
RANLIB=$(ndk_bin "$NDK" llvm-ranlib)
STRIP=$(ndk_bin "$NDK" llvm-strip)
READELF=$(ndk_bin "$NDK" llvm-readelf)
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)

echo "pack.sh: host $HOST_MACHINE -> target $TARGET_MACHINE, API $API"
echo "pack.sh: NDK  $NDK"
echo "pack.sh: cc   $CC"

# ---------------------------------------------------------------- 1. ChezScheme
if [ ! -d "$CHEZ_SRC/.git" ]; then
  echo "pack.sh: cloning ChezScheme $CHEZ_VERSION"
  mkdir -p "$(dirname "$CHEZ_SRC")"
  git clone --depth 1 --branch "$CHEZ_VERSION" --recurse-submodules \
    https://github.com/cisco/ChezScheme.git "$CHEZ_SRC"
fi
have=$(git -C "$CHEZ_SRC" rev-parse HEAD)
if [ "$have" != "$CHEZ_REVISION" ]; then
  die "$CHEZ_SRC is at $have, not the pinned $CHEZ_REVISION"
fi

cd "$CHEZ_SRC"

# ------------------------------------------------------- 2. the host compiler
# --disable-x11: a cross sysroot has no X11 headers and the expeditor wants
# them. jolt's own CI builds Chez the same way, and nothing in an app uses the
# expeditor.
echo "pack.sh: building the $HOST_MACHINE host compiler"
./configure "-m=$HOST_MACHINE" --disable-x11
make "-j$JOBS" >/dev/null

# ---------------------------------------------- 3. target boots and the xpatch
# bootquick emits the target's boot files AND xc-<target>/s/xpatch, which is
# the only artifact that retargets the host's compile-file and make-boot-file.
# Boot files describe the machine, not the OS, so these say nothing of Android.
echo "pack.sh: bootquick for $TARGET_MACHINE"
make bootquick "XM=$TARGET_MACHINE" >/dev/null

# --------------------------------------------------------- 4. the Bionic kernel
# This is the step that makes the pack Android's. --disable-iconv matters:
# Chez's kernel is the one place that reaches for iconv, and Bionic has none.
echo "pack.sh: cross-building the C kernel against Bionic (API $API)"
rm -rf "$TARGET_MACHINE"
./configure --cross --force "-m=$TARGET_MACHINE" \
  --disable-auto-flags --disable-curses --disable-x11 --disable-iconv \
  CFLAGS="-fPIC -O2" \
  CC="$CC" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP" \
  LIBS="-lm -ldl" CC_FOR_BUILD=cc
make "-j$JOBS" >/dev/null

# ------------------------------------------------------------- 5. the pack
boot="$TARGET_MACHINE/boot/$TARGET_MACHINE"
xpatch="xc-$TARGET_MACHINE/s/xpatch"
for f in "$boot/petite.boot" "$boot/scheme.boot" "$boot/libkernel.a" "$boot/scheme.h" "$xpatch"; do
  [ -e "$f" ] || die "the Chez build did not produce $CHEZ_SRC/$f"
done

rm -rf "$PACK"
mkdir -p "$PACK/lib"
cp "$boot/petite.boot" "$boot/scheme.boot" "$boot/libkernel.a" "$boot/scheme.h" "$PACK/"
cp "$xpatch" "$PACK/xpatch"
cp "$TARGET_MACHINE/lz4/lib/liblz4.a" "$PACK/lib/"
cp "$TARGET_MACHINE/zlib/libz.a" "$PACK/lib/"
printf '%s\n' '-llz4 -lz -lm -ldl' > "$PACK/link-libs"

# ---------------------------------------------------- 6. verify, do not assume
# A pack built by the host compiler by mistake links and then fails on the
# device, so read the machine out of the kernel rather than trusting the flags.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/raylib-pack.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
member=$("$AR" t "$PACK/libkernel.a" | grep -m1 '\.o$')
(cd "$tmp" && "$AR" x "$PACK/libkernel.a" "$member")
if ! "$READELF" -h "$tmp/$member" | grep -q 'AArch64'; then
  die "$PACK/libkernel.a ($member) is not AArch64"
fi
echo "pack.sh: libkernel.a ($member) is AArch64, API $API, -fPIC"
echo "pack.sh: wrote $PACK"
echo "pack.sh:   jolt build --library --target $TARGET_MACHINE --target-pack $PACK"
