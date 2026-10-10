#!/usr/bin/env bash
# Clean rebuild + install of RTEMS (psim, ibookg3) and rtems-libbsd (ibookg3)
# into rtems/ in the repository with the installed toolchain.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
P=$ROOT/rtems
export PATH=$P/bin:$PATH
cd "$ROOT/src/rtems"
cp "$ROOT/tools/rtems-config.ini" config.ini
rm -rf build
nix shell nixpkgs#python3 -c bash -c \
  "./waf configure --prefix=$P --rtems-tools=$P && ./waf && ./waf install"
cd "$ROOT/src/rtems-libbsd"
# its dependency tracking ignores the installed RTEMS headers: start clean
rm -rf build
nix shell nixpkgs#python3 -c bash -c \
  "./waf configure --prefix=$P --rtems=$P --rtems-tools=$P --rtems-arch=powerpc \
     --rtems-bsps=powerpc/ibookg3 --buildset=buildset/ibookg3.ini && ./waf && ./waf install"
echo REBUILD-OK
