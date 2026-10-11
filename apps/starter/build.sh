#!/usr/bin/env bash
# Build for BSP=ibookg3 (default, emulated iBook) or BSP=psim.
#   HW=1   link for a real iBook booted by Open Firmware (load address equal
#          to the run address); makes app-ibookg3-hw.elf, which
#          tools/make-boot-cd.sh turns into a bootable CD image
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)
BSP=${BSP:-ibookg3}
P=$ROOT/rtems
OUT=app-$BSP.exe
EXTRA=
if [ "${HW:-0}" = 1 ]; then
  OUT=app-$BSP-hw.elf
  EXTRA=-Wl,--defsym=IBOOKG3_LOAD_BASE=0x01000000
fi
exec "$ROOT/tools/with.sh" pkg-config -- bash -c "
  export PATH=$P/bin:\$PATH PKG_CONFIG_PATH=$P/lib/pkgconfig
  powerpc-rtems6-gcc \$(pkg-config --cflags powerpc-rtems6-$BSP) -O2 -g -Wall \
    *.c \$(pkg-config --libs powerpc-rtems6-$BSP) $EXTRA -o $OUT
  echo built \$(pwd)/$OUT"
