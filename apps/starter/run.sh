#!/usr/bin/env bash
# Run on the emulated iBook (Ctrl-A x quits), or BSP=psim on GDB's simulator.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)
if [ "${BSP:-ibookg3}" = psim ]; then
  exec "$ROOT/rtems/bin/powerpc-rtems6-run" -m 603e \
    -f "$ROOT/src/rtems-tools/tester/rtems/testing/bsps/psim-device-tree" app-psim.exe
fi
exec "$ROOT/run-g3.sh" -rtems app-ibookg3.exe "$@"
