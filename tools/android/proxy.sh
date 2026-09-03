#!/bin/sh
# proxy.sh: forward the device's nREPL port to this machine, over adb.
#
#   sh tools/android/proxy.sh
#   LOCAL_PORT=17888 DEVICE_PORT=7888 sh tools/android/proxy.sh
#   sh tools/android/proxy.sh remove
#
# jolt.nrepl binds loopback only, so the device's listener is unreachable
# without this. Unlike the iOS iproxy this replaces, `adb forward` installs a
# rule in the adb server and RETURNS: there is no process to leave running in
# another terminal, and the rule outlives this script until the device
# disconnects or `remove` takes it away.
set -eu

# shellcheck source=tools/android/common.sh
. "$(dirname "$0")/common.sh"

LOCAL_PORT=${LOCAL_PORT:-7888}
DEVICE_PORT=${DEVICE_PORT:-7888}
adb=$(adb_bin)
serial=$(adb_serial)

if [ "${1:-}" = remove ]; then
  "$adb" -s "$serial" forward --remove "tcp:$LOCAL_PORT"
  echo "proxy.sh: removed the forward on $LOCAL_PORT"
  exit 0
fi

# REFUSE to forward onto a port something else already holds, rather than
# hoping.
#
# This is not hypothetical. On the iOS side of this project a stray JVM nREPL
# held 127.0.0.1:7889 while the forwarder bound the IPv6 wildcard; connections
# went to the JVM, and an eval answered with plausible values that were simply
# the desktop's. Nothing failed, and the wrong answers looked exactly like
# right ones. An existing adb rule for the same port is fine -- adb replaces
# its own -- so that case is allowed through.
holder=
if command -v lsof >/dev/null 2>&1; then
  holder=$(lsof -nP -iTCP:"$LOCAL_PORT" -sTCP:LISTEN 2>/dev/null | tail -n +2 || true)
elif command -v ss >/dev/null 2>&1; then
  holder=$(ss -ltnp 2>/dev/null | grep ":$LOCAL_PORT " || true)
fi
if [ -n "$holder" ]; then
  ours=$("$adb" -s "$serial" forward --list | grep " tcp:$LOCAL_PORT " || true)
  if [ -z "$ours" ]; then
    echo "proxy.sh: something is already listening on $LOCAL_PORT:" >&2
    printf '%s\n' "$holder" | sed 's/^/  /' >&2
    echo "proxy.sh: forwarding onto it would send your evals to THAT process, and" >&2
    echo "proxy.sh: its answers would look perfectly reasonable. Pick another:" >&2
    echo "proxy.sh:   LOCAL_PORT=17888 sh tools/android/proxy.sh" >&2
    exit 2
  fi
  echo "proxy.sh: replacing this adb forward on $LOCAL_PORT:"
  printf '%s\n' "$ours" | sed 's/^/  /'
fi

"$adb" -s "$serial" forward "tcp:$LOCAL_PORT" "tcp:$DEVICE_PORT"
echo "proxy.sh: localhost:$LOCAL_PORT -> $serial 127.0.0.1:$DEVICE_PORT"
echo "proxy.sh: prove it is the phone:  tools/android/nrepl eval $LOCAL_PORT '(System/getProperty \"os.arch\")'"
echo "proxy.sh: the device answers aarch64; an x86_64 answer is a process on this machine"
echo "proxy.sh: take it away again with: sh tools/android/proxy.sh remove"
