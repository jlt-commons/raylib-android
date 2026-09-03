#!/bin/sh
# deploy.sh: install and launch the APK on a device.
#
#   sh tools/android/deploy.sh                    # the debug APK
#   MODE=release APK=app-release.apk sh tools/android/deploy.sh
#   LOG=1 sh tools/android/deploy.sh              # and tail its logcat
#
# Build first: sh tools/android/build.sh [debug|release]
set -eu

# shellcheck source=tools/android/common.sh
. "$(dirname "$0")/common.sh"

MODE=${1:-${MODE:-debug}}
case "$MODE" in
  debug)   default_apk="$GRADLE_PROJECT/app/build/outputs/apk/debug/app-debug.apk" ;;
  release) default_apk="$GRADLE_PROJECT/app/build/outputs/apk/release/app-release-unsigned.apk" ;;
  *) die "MODE must be debug or release, got '$MODE'" ;;
esac
APK=${APK:-$default_apk}

[ -s "$APK" ] || die "no APK at $APK -- run: sh tools/android/build.sh $MODE"

# An unsigned release APK installs with INSTALL_PARSE_FAILED_NO_CERTIFICATES,
# which reads like a corrupt file rather than a missing signature. Say so here
# instead.
case "$APK" in
  *-unsigned.apk) die "$APK is unsigned; adb will not install it. Sign it first
  (build.sh prints the two commands) and pass APK=<signed apk>." ;;
esac

adb=$(adb_bin)
serial=$(adb_serial)
pkg=$(app_id)

# arm64 only, by design: the APK carries one ABI and one cross-built Chez. An
# x86_64 emulator without ARM translation installs this happily and then fails
# to load libmain.so, so ask the device what it can run.
abis=$("$adb" -s "$serial" shell getprop ro.product.cpu.abilist | tr -d '\r')
case "$abis" in
  *arm64-v8a*) ;;
  *) echo "deploy.sh: $serial reports ABIs '$abis' and this APK is arm64-v8a only." >&2
     echo "deploy.sh: it will install and then fail to load libmain.so." >&2
     echo "deploy.sh: use an arm64 device, or an emulator image with ARM64 translation." >&2
     die "refusing to install onto an incompatible device" ;;
esac

"$adb" -s "$serial" install -r "$APK"
"$adb" -s "$serial" shell am force-stop "$pkg"
"$adb" -s "$serial" shell am start -W -n "$pkg/android.app.NativeActivity"

echo "deploy.sh: launched $pkg on $serial"
if [ "${LOG:-0}" = 1 ]; then
  exec "$(dirname "$0")/log.sh"
fi
echo "deploy.sh: its output is in logcat, not on a console -- an Android app's"
echo "deploy.sh: stdout goes nowhere. Watch it with: jolt log"
