#!/usr/bin/env bash
# Debug app-ibookg3.exe with GDB: QEMU waits at reset, GDB attaches, breaks at Init.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)
qemu-system-ppc -M mac99 -cpu 750cx -m 128 -nographic -net none \
  -S -gdb tcp::1234 -kernel app-ibookg3.exe > qemu-console.log 2>&1 &
QPID=$!
trap 'kill $QPID 2>/dev/null' EXIT
echo "QEMU running (console output -> qemu-console.log)"
"$ROOT/rtems/bin/powerpc-rtems6-gdb" -q \
  -ex 'target remote :1234' -ex 'break Init' -ex 'continue' app-ibookg3.exe
