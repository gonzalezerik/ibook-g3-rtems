#!/usr/bin/env bash
# Build rad750-check for 128 MB (RAD750 DRAM).
#   BSP=psim    (default) GDB's PowerPC simulator; linked with linkcmds-128m
#   BSP=ibookg3           emulated iBook G3; RAM size comes from Open Firmware
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)
BSP=${BSP:-psim}
P=$ROOT/rtems
BSPLIB=$P/powerpc-rtems6/$BSP/lib
export PATH=$P/bin:$PATH
export PKG_CONFIG_PATH=$P/lib/pkgconfig
pkg-config() { "$ROOT/tools/with.sh" pkg-config -- pkg-config "$@"; }
CFLAGS=$(pkg-config --cflags powerpc-rtems6-$BSP)
LDFLAGS=$(pkg-config --libs powerpc-rtems6-$BSP)
OUT=rad750-check-$BSP.exe
powerpc-rtems6-gcc $CFLAGS "-DBSP_${BSP^^}" -O2 -Wall -c init.c -o init-$BSP.o
if [ "$BSP" = psim ]; then
  # swap the BSP's 256 MB linkcmds for ours; linkcmds.base comes from the BSP
  powerpc-rtems6-gcc $CFLAGS init-$BSP.o $LDFLAGS -qnolinkcmds -L"$BSPLIB" -T linkcmds-128m -o $OUT
else
  powerpc-rtems6-gcc $CFLAGS init-$BSP.o $LDFLAGS -o $OUT
fi
echo "built $(pwd)/$OUT"
