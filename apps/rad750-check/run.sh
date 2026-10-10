#!/usr/bin/env bash
# Run rad750-check on GDB's PowerPC simulator (psim) with 128 MB of RAM.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)
# -m 603e: psim has no 750 model; the 750/G3 core is a 603e derivative
exec timeout 300 "$ROOT/rtems/bin/powerpc-rtems6-run" -m 603e \
  -f "$ROOT/tester/psim-device-tree-128m" rad750-check-psim.exe
