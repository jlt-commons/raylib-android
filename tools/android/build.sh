#!/bin/sh
# build.sh: cross-compile NS into libjoltraylib.so and assemble the APK.
#
#   sh tools/android/build.sh                              # debug, raylib.live
#   NS=raylib.gallery sh tools/android/build.sh release
#   NS=raylib.touch   sh tools/android/build.sh            # a smoke entry
#   NS=raylib.live-cider ALIAS=:cider sh tools/android/build.sh
#
# Two artifacts, in this order. The Jolt half is `jolt build --library`
# cross-compiled to tarm64le with the NDK's clang: a shared object exporting
# jolt_library_init, jolt_lookup and jolt_library_shutdown, whose Clojure entry
# published one C-callable name with ffi/export!. The native half is Gradle's,
# and is libmain.so: main.c plus raylib compiled from pinned source, which is
# what the NativeActivity loads and what dlopens the first.
#
# The target is NATIVE arm64 code (tarm64le), not the threaded bytecode the iOS
# build had to use. That restriction was Apple's -- executable pages must come
# from a signed, immutable source, so a native Chez died on launch with
# `mprotect failed`. Android has no such rule, so the phone runs real compiled
# code here.
set -eu

# shellcheck source=tools/android/common.sh
. "$(dirname "$0")/common.sh"

MODE=${1:-${MODE:-debug}}
ALIAS=${ALIAS:-}
API=$(android_api)

case "$MODE" in
  debug)
    # raylib.live by default: the debug APK is the one with the nREPL, and its
    # manifest is the only one that asks for INTERNET.
    NS=${NS:-raylib.live}
    GRADLE_TASK=:app:assembleDebug
    APK="$GRADLE_PROJECT/app/build/outputs/apk/debug/app-debug.apk"
    # --dev rather than the default release image. A release build inlines
    # across call sites, so a var redefined over the nREPL does not reach code
    # that was already compiled: the REPL sees the new value and the running
    # loop keeps calling the old one. --dev is what makes redefinition take
    # effect, which is the whole point of the debug variant.
    DEV_FLAG=--dev
    ;;
  release)
    NS=${NS:-raylib.gallery}
    GRADLE_TASK=:app:assembleRelease
    APK="$GRADLE_PROJECT/app/build/outputs/apk/release/app-release-unsigned.apk"
    DEV_FLAG=
    ;;
  *) die "MODE must be debug or release, got '$MODE'" ;;
esac

# ---- the inputs
if [ ! -f "$RAYLIB_SRC/src/platforms/rcore_android.c" ]; then
  die "no raylib source at $RAYLIB_SRC -- run: sh tools/android/deps.sh"
fi
PACK=${PACK:-$WORK/pack/$TARGET_MACHINE-api$API}
if [ ! -f "$PACK/link-libs" ]; then
  die "no Chez target pack at $PACK -- run: sh tools/android/pack.sh"
fi

NDK=$(android_ndk)
NDK_VERSION=${NDK##*/}
CC=$(ndk_bin "$NDK" "aarch64-linux-android$API-clang")
NM=$(ndk_bin "$NDK" llvm-nm)
READELF=$(ndk_bin "$NDK" llvm-readelf)
GRADLE=${GRADLE:-gradle}
if ! command -v "$GRADLE" >/dev/null 2>&1; then
  die "no '$GRADLE' on PATH: install Gradle 8.9 or newer (AGP 8.7 needs it), or set GRADLE=/path/to/gradle"
fi

# ---- 1. the Jolt library
lib="$WORK/libjoltraylib-$MODE.so"
mkdir -p "$WORK"
echo "build.sh: $NS -> $lib ($MODE, $TARGET_MACHINE, API $API)"

# -A must precede the `build` subcommand: `jolt build -A:alias ...` silently
# drops the alias's extra-paths.
JOLT_TARGET_CC="$CC" \
JOLT_TARGET_LINK_LIBS="-L$PACK/lib -llz4 -lz -lm -ldl" \
  jolt ${ALIAS:+-A$ALIAS} build --library -m "$NS" -o "$lib" ${DEV_FLAG:+$DEV_FLAG} \
    --target "$TARGET_MACHINE" --target-pack "$PACK"
rm -rf "$lib.build"

# ---- 2. verify it, do not assume
# The soname of Bionic's libc is libc.so; glibc's is libc.so.6. So this one
# line is what proves the target pack was Android's rather than a Linux one
# that happened to be lying around -- a mistake that links cleanly and then
# dies inside the linker on the device.
if ! "$READELF" -d "$lib" | grep -q 'Shared library: \[libc\.so\]'; then
  echo "build.sh: $lib does not depend on Bionic's libc.so:" >&2
  "$READELF" -d "$lib" | grep 'Shared library' >&2 || true
  die "the target pack at $PACK was not built for Android -- rebuild it with tools/android/pack.sh"
fi
for symbol in jolt_library_init jolt_lookup jolt_library_shutdown; do
  if ! "$NM" --dynamic --defined-only "$lib" | grep -q " $symbol\$"; then
    die "$lib does not export $symbol -- is this jolt $(jolt --version) too old for --library?"
  fi
done
# The entry name itself (raylib_main / raylib_main_debug) is NOT an ELF symbol:
# ffi/export! puts it in the jolt ABI table that jolt_lookup reads, so there is
# nothing here to grep for. main.c logs what it found, which is why
# `jolt log` is the first place to look at a blank screen.
echo "build.sh: $(du -h "$lib" | cut -f1) library, Bionic-linked, jolt ABI present"

# ---- 3. stage it where Gradle will pick it up
# Per build type, in AGP's own default jniLibs location. Debug and release are
# kept apart deliberately: one shared staging directory lets a release APK
# quietly pick up a debug library that is still lying there.
stage="$GRADLE_PROJECT/app/src/$MODE/jniLibs/arm64-v8a"
rm -rf "$GRADLE_PROJECT/app/src/$MODE/jniLibs"
mkdir -p "$stage"
cp "$lib" "$stage/libjoltraylib.so"
chmod 755 "$stage/libjoltraylib.so"

# ---- 4. the APK
# ANDROID_HOME is exported rather than assumed: android_sdk() will happily find
# ~/Android/Sdk with no environment set, and AGP will then not, because it looks
# only at the environment or at a local.properties this project does not carry.
echo "build.sh: gradle $GRADLE_TASK"
ANDROID_HOME="$(android_sdk)" \
ANDROID_SDK_ROOT="$(android_sdk)" \
RAYLIB_SOURCE="$RAYLIB_SRC" "$GRADLE" --no-daemon -p "$GRADLE_PROJECT" "$GRADLE_TASK" \
  "-Praylib.source=$RAYLIB_SRC" \
  "-Praylib.ndkVersion=$NDK_VERSION" \
  "-Praylib.apiLevel=$API"

[ -s "$APK" ] || die "gradle did not produce $APK" 1
echo "build.sh: wrote $APK ($NS, $MODE, arm64-v8a, $(du -h "$APK" | cut -f1))"
if [ "$MODE" = release ]; then
  cat <<MSG
build.sh: that APK is UNSIGNED, so adb will refuse to install it. Sign it with
build.sh: your own key, out of tree:
build.sh:
build.sh:   zipalign -f -p 4 $APK app-release.apk
build.sh:   apksigner sign --ks <keystore> --ks-key-alias <alias> app-release.apk
MSG
fi
