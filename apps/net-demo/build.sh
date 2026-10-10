#!/usr/bin/env bash
# Build app.exe for the ibookg3 BSP (network demo, UniNorth GMAC).
# The demo links rtems-libbsd, so -lbsd and its dependencies go after
# the RTEMS library set.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)
BSP=${BSP:-ibookg3}
P=$ROOT/rtems
exec nix shell nixpkgs#pkg-config -c bash -c "
  set -euo pipefail
  export PATH=$P/bin:\$PATH PKG_CONFIG_PATH=$P/lib/pkgconfig
  powerpc-rtems6-gcc \$(pkg-config --cflags powerpc-rtems6-$BSP) -O2 -g -Wall \
    *.c \$(pkg-config --libs powerpc-rtems6-$BSP) -lbsd -lz -lm \
    -o app-$BSP.exe
  echo built \$(pwd)/app-$BSP.exe"
