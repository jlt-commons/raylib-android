#!/bin/sh
# devices.sh: what deploy.sh could talk to, and whether it should.
#
#   sh tools/android/devices.sh
#
# `adb devices` alone answers a serial and a state, which is not enough to know
# whether an APK will run: this project builds arm64-v8a only, so the column
# that matters is the ABI list. An x86_64 emulator without ARM64 translation
# accepts the install and then cannot load libmain.so, which looks like a bug
# in the app.
set -eu

# shellcheck source=tools/android/common.sh
. "$(dirname "$0")/common.sh"

adb=$(adb_bin)
"$adb" start-server >/dev/null 2>&1 || true

prop() {                          # $1 = serial, $2 = property
  "$adb" -s "$1" shell getprop "$2" 2>/dev/null | tr -d '\r'
}

# Collected before the loop rather than piped into it: a `while read` in a
# pipeline runs in a subshell, so anything it counted is gone by the time the
# "none found" line would be printed.
devices=$("$adb" devices | awk 'NR > 1 && NF >= 2 { print $1, $2 }')

echo "# devices (export SERIAL=<serial> to pick one)"
if [ -z "$devices" ]; then
  echo "  (none) plug in a phone, unlock it and accept the USB debugging prompt,"
  echo "         or start an emulator with an arm64-v8a or translating image"
else
  printf '%s\n' "$devices" | while read -r serial state; do
    if [ "$state" != device ]; then
      printf '  %-22s %s\n' "$serial" "$state -- unlock it, and accept the USB debugging prompt"
      continue
    fi
    abis=$(prop "$serial" ro.product.cpu.abilist)
    case "$abis" in
      *arm64-v8a*) verdict="arm64-v8a: ok" ;;
      *)           verdict="NO arm64-v8a: this APK would install and not load" ;;
    esac
    printf '  %-22s %s  Android %s (API %s)  %s\n' \
      "$serial" "$(prop "$serial" ro.product.model)" \
      "$(prop "$serial" ro.build.version.release)" \
      "$(prop "$serial" ro.build.version.sdk)" "$verdict"
    printf '  %-22s   ABIs: %s\n' "" "$abis"
  done
fi

echo "# this project builds arm64-v8a only, minSdk $(android_api)"
