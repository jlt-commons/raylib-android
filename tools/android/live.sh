#!/bin/sh
# live.sh: the gallery with an nREPL, on the phone.
#
#   sh tools/android/live.sh
#   CIDER=1 sh tools/android/live.sh
#
# Builds the debug variant of raylib.live, installs it, launches it and
# forwards the port. Debug only, and structurally so: the release variant's
# manifest has no INTERNET permission and main.c refuses to run a release image
# that carries the nREPL entry point at all.
set -eu

here=$(dirname "$0")
# shellcheck source=tools/android/common.sh
. "$here/common.sh"

LOCAL_PORT=${LOCAL_PORT:-7888}

# CIDER=1 swaps in the middleware build, which needs the :cider alias because
# that is where the dependency lives. The default has none.
if [ "${CIDER:-0}" = 1 ]; then
  NS=raylib.live-cider ALIAS=:cider sh "$here/build.sh" debug
else
  NS=raylib.live sh "$here/build.sh" debug
fi
sh "$here/deploy.sh" debug
LOCAL_PORT="$LOCAL_PORT" sh "$here/proxy.sh"

cat <<MSG

live: the gallery is running with an nREPL on the phone's 127.0.0.1:7888,
      forwarded to this machine's $LOCAL_PORT.

  1. prove it is the phone: tools/android/nrepl eval $LOCAL_PORT '(System/getProperty "os.arch")'
     the device answers aarch64; an x86_64 answer is a process on this machine
  2. a REPL prompt:         tools/android/nrepl repl $LOCAL_PORT
  3. everything it prints:  jolt log

Reads are free:

  tools/android/nrepl eval $LOCAL_PORT '(do (require (quote [raylib.host])) (pr-str (raylib.host/state)))'

Anything touching raylib must go through on-next-frame!, because an eval runs
on the nREPL thread while raylib belongs to the thread android_main handed the
loop:

  tools/android/nrepl eval $LOCAL_PORT '(do (require (quote [raylib.host])) (raylib.host/on-next-frame! (fn [] (raylib.host/set-target-fps 30))))'

And the app can be driven without a finger, which is how the scenes were
captured:

  tools/android/nrepl eval $LOCAL_PORT '(do (require (quote [raylib.gallery])) (raylib.gallery/tap! 300 900))'

LOCAL_PORT overrides the host side; the phone's port is fixed at 7888 (see
raylib.live/nrepl-port -- an Android app has no environment to read one from).

Built-in ops here: clone, describe, eval, load-file, close. For an editor,
CIDER=1 jolt live adds completions, info, eldoc, the namespace browser,
macroexpansion, apropos and the test ops.
MSG
