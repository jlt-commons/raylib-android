# shellcheck shell=sh
# shellcheck disable=SC2034  # these constants are read by the scripts that source this
# common.sh: what every script under tools/android needs. Sourced, not run.
#
# Nothing here has side effects beyond setting variables and defining
# functions, so sourcing it twice is harmless. Every check is an if-block
# rather than an && chain, because under `set -e` a failing AND-list is exactly
# the kind of thing that exits a script for a reason nobody can see.

# The repository root, from this file's own location, so every script works
# whatever directory it is called from.
CDPATH=''
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
GRADLE_PROJECT="$ROOT/tools/android"

# The pinned raylib revision. Not a tag: this is the exact tree the host in
# src/raylib/host.clj was written against, and the one the Android experiment
# at jasalt/jolt-android-experiment proved. rcore_android.c at this revision is
# what the comments cite -- the entry contract at lines 318-331, the eaten Back
# key, GetMonitorPhysicalWidth's density arithmetic.
RAYLIB_REVISION=9f3cadf1e618f125bd9b282c7759f8cb26ce17fc

# ChezScheme, pinned by tag AND revision because a tag can move.
CHEZ_VERSION=v10.4.1
CHEZ_REVISION=e95a7efbafa2cf3bd5343ea542e6bc909a7ab2c4

# Chez's machine string for arm64 Android. Bionic is not a machine type of its
# own -- jolt's cross-compile README says so in as many words -- so the target
# pack's link-libs and the NDK compiler are what make a tarm64le pack Android's
# rather than glibc's.
TARGET_MACHINE=tarm64le

# Where downloads and the fifteen-minute Chez cross-build land. Under ~/.cache
# rather than /tmp on purpose: a target pack is expensive to rebuild and
# nothing in it is source.
WORK=${WORK:-$HOME/.cache/raylib-android}
DEV=${DEV:-$HOME/dev}
RAYLIB_SRC=${RAYLIB_SRC:-$DEV/raylib-$RAYLIB_REVISION}
CHEZ_SRC=${CHEZ_SRC:-$WORK/chez-$CHEZ_VERSION}

# The logcat tag src/raylib/host.clj and main.c both write under.
LOG_TAG=raylib-android

die() { echo "${0##*/}: $1" >&2; exit "${2:-2}"; }

# The API level the NDK compiles against, the APK's minSdk and the Chez
# cross-build's Bionic, all from one line in gradle.properties so they cannot
# drift apart. API=NN overrides for a one-off.
android_api() {
  if [ -n "${API:-}" ]; then
    echo "$API"
    return 0
  fi
  api=$(sed -n 's/^raylib\.apiLevel=\([0-9]*\).*/\1/p' "$GRADLE_PROJECT/gradle.properties")
  if [ -z "$api" ]; then
    die "no raylib.apiLevel in $GRADLE_PROJECT/gradle.properties"
  fi
  echo "$api"
}

# The Android SDK, from the usual variables or the usual place.
android_sdk() {
  for d in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk"; do
    if [ -n "$d" ] && [ -d "$d/platform-tools" ]; then
      echo "$d"
      return 0
    fi
  done
  die "no Android SDK: set ANDROID_HOME (looked there, in ANDROID_SDK_ROOT and in ~/Android/Sdk)"
}

# The NDK. An explicit ANDROID_NDK_ROOT wins; otherwise the newest one the SDK
# has, by version sort. The Chez cross-build and Gradle are both pinned to
# whatever this answers, so they cannot end up using different toolchains.
android_ndk() {
  for d in "${ANDROID_NDK_ROOT:-}" "${ANDROID_NDK_HOME:-}"; do
    if [ -n "$d" ] && [ -d "$d/toolchains/llvm/prebuilt" ]; then
      echo "$d"
      return 0
    fi
  done
  sdk=$(android_sdk)
  ndk=$(find "$sdk/ndk" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -V | tail -1)
  if [ -z "$ndk" ]; then
    die "no NDK: set ANDROID_NDK_ROOT, or install one under $sdk/ndk"
  fi
  echo "$ndk"
}

# A program from the NDK's clang toolchain: the API-level clang wrapper bakes
# the target triple and the platform level into itself, which is why no
# separate arch flag is ever passed to jolt build.
ndk_bin() {                       # $1 = ndk, $2 = program name
  p=$(find "$1/toolchains/llvm/prebuilt" -name "$2" -type f -print 2>/dev/null | head -1)
  if [ -z "$p" ]; then
    die "no $2 in $1 (is this NDK complete, and does it have API $(android_api)?)"
  fi
  echo "$p"
}

adb_bin() {
  sdk=$(android_sdk)
  if [ ! -x "$sdk/platform-tools/adb" ]; then
    die "no adb at $sdk/platform-tools/adb"
  fi
  echo "$sdk/platform-tools/adb"
}

# One device, named or inferred. Refuses to guess between two, because
# installing a debug build on the wrong phone is quiet and confusing.
adb_serial() {
  adb=$(adb_bin)
  if [ -n "${SERIAL:-}" ]; then
    state=$("$adb" -s "$SERIAL" get-state 2>/dev/null || true)
    if [ "$state" != device ]; then
      die "device $SERIAL is '${state:-absent}', not 'device'"
    fi
    echo "$SERIAL"
    return 0
  fi
  found=$("$adb" devices | awk '$2 == "device" { print $1 }')
  count=$(printf '%s' "$found" | grep -c . || true)
  if [ "$count" = 0 ]; then
    die "no authorised device: plug one in, unlock it, accept the USB debugging prompt, then: jolt devices"
  fi
  if [ "$count" != 1 ]; then
    echo "${0##*/}: more than one device is connected:" >&2
    printf '%s\n' "$found" | sed 's/^/  /' >&2
    die "pick one with SERIAL=<serial>"
  fi
  printf '%s\n' "$found"
}

# The application id, read from the Gradle file rather than repeated here.
app_id() {
  id=$(sed -n 's/^ *applicationId *= *"\([^"]*\)".*/\1/p' "$GRADLE_PROJECT/app/build.gradle.kts")
  if [ -z "$id" ]; then
    die "no applicationId in $GRADLE_PROJECT/app/build.gradle.kts"
  fi
  echo "$id"
}
