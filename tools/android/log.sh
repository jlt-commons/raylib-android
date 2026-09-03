#!/bin/sh
# log.sh: the app's own logcat.
#
#   sh tools/android/log.sh              # follow
#   CLEAR=1 sh tools/android/log.sh      # ...from empty
#   sh tools/android/log.sh -d           # dump what is there and exit
#
# This is the console this project does not otherwise have. An Android app's
# stdout is discarded, so raylib.host/log writes to the system log instead and
# every diagnostic -- frame timings, touch presses, the nREPL's port, a scene's
# events -- arrives here under the raylib-android tag.
#
# The tags, and why each one is worth having:
#   raylib-android   main.c's bootstrap and everything raylib.host/log writes
#   raylib           raylib's own TRACELOG, including the display sizes it
#                    chose and any GL failure during InitWindow
#   DEBUG, libc      a native crash: the tombstone and the abort message
#   ActivityManager  the launch, and the death, of the process
set -eu

# shellcheck source=tools/android/common.sh
. "$(dirname "$0")/common.sh"

adb=$(adb_bin)
serial=$(adb_serial)

if [ "${CLEAR:-0}" = 1 ]; then
  "$adb" -s "$serial" logcat -c
fi

exec "$adb" -s "$serial" logcat "$@" \
  -s "$LOG_TAG:V" raylib:V DEBUG:V libc:V ActivityManager:I
