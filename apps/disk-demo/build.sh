#!/usr/bin/env bash
# Build app.exe for the ibookg3 BSP (disk demo, KeyLargo ATA).
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)
BSP=${BSP:-ibookg3}
P=$ROOT/rtems
exec nix shell nixpkgs#pkg-config -c bash -c "
  export PATH=$P/bin:\$PATH PKG_CONFIG_PATH=$P/lib/pkgconfig
  powerpc-rtems6-gcc \$(pkg-config --cflags powerpc-rtems6-$BSP) -O2 -g -Wall \
    *.c \$(pkg-config --libs powerpc-rtems6-$BSP) -o app-$BSP.exe
  echo built \$(pwd)/app-$BSP.exe"
