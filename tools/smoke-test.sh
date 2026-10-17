#!/usr/bin/env bash
# Build and run every demo program and check its output: the starter on
# both BSPs, rad750-check, and the disk, network and USB demos. CI runs it
# in the Docker image; it works the same in a native setup.
#
#   tools/smoke-test.sh [output-dir]     # logs and screenshots, default a temp dir
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
export AUDIO=${AUDIO:-none}
failed=()

# check NAME LOG PATTERN...: every extended regex PATTERN must be in LOG
check() {
  local name=$1 log=$2 p ok=1
  shift 2
  for p in "$@"; do
    grep -qaE -- "$p" "$log" || { echo "$name: missing \"$p\""; ok=0; }
  done
  if [ $ok = 1 ]; then
    echo "$name: PASS"
  else
    echo "--- $log ---"; cat "$log"; echo "---"
    failed+=("$name")
  fi
}

# a PNG of the iBook's screen, saved by run-g3.sh SCREENSHOT=
is_png() { [ "$(head -c 8 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = 89504e470d0a1a0a ]; }

cd "$ROOT"

# On the emulated iBook; run-g3.sh stops QEMU once the screen is saved
apps/starter/build.sh >/dev/null
SCREENSHOT=$OUT/starter.png timeout 180 apps/starter/run.sh </dev/null >"$OUT/starter.log" 2>&1 || true
check starter "$OUT/starter.log" "Hello from RTEMS on PowerPC" "tick 2" "RTEMS shutdown"
is_png "$OUT/starter.png" || { echo "starter: no screenshot"; failed+=(starter-screenshot); }

# On GDB's simulator, which exits with the program's status
BSP=psim apps/starter/build.sh >/dev/null
BSP=psim timeout 180 apps/starter/run.sh </dev/null >"$OUT/starter-psim.log" 2>&1 || true
check starter-psim "$OUT/starter-psim.log" "tick 2" "RTEMS shutdown"

apps/rad750-check/build.sh >/dev/null
timeout 300 apps/rad750-check/run.sh </dev/null >"$OUT/rad750-check.log" 2>&1 || true
check rad750-check "$OUT/rad750-check.log" "RAM size: +128 MB" "Memory fill/verify: OK"

apps/disk-demo/build.sh >/dev/null
SCREENSHOT=$OUT/disk-demo.png timeout 180 apps/disk-demo/run.sh </dev/null >"$OUT/disk-demo.log" 2>&1 || true
check disk-demo "$OUT/disk-demo.log" "read 16 bytes from /mnt/hostfile.txt" \
  "^ +hello from host" "wrote 37 bytes" "=== done ==="

# These two drive the host side themselves and print PASS or FAIL
for demo in net-demo usb-demo; do
  apps/$demo/build.sh >/dev/null
  apps/$demo/run.sh </dev/null >"$OUT/$demo.log" 2>&1 || true
  check $demo "$OUT/$demo.log" "$demo: PASS"
done

echo "logs and screenshots in $OUT"
if [ ${#failed[@]} -gt 0 ]; then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "all demos passed"
