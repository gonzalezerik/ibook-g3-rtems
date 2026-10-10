#!/usr/bin/env bash
# Build the RTEMS 6 PowerPC toolchain natively on NixOS into rtems/.
# Uses src/rsb (the RSB 6 branch plus the NixOS support patches) and the dev
# shell in rsb-shell.nix. No FHS sandbox needed. Run setup.sh first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT/src/rsb/rtems"
nix-shell "$ROOT/rsb-shell.nix" --run "../source-builder/sb-set-builder \
  --prefix=$ROOT/rtems --log=$ROOT/rsb-toolchain-build.log 6/rtems-powerpc"

# RSB installs rtems-tools as released; reinstall the same version with the
# rtems-ld RAP relocation fix (see UPSTREAM-FINDINGS.md)
cd "$ROOT/src/rtems-tools-6"
nix-shell "$ROOT/rsb-shell.nix" --run \
  "./waf distclean configure --prefix=$ROOT/rtems && ./waf && ./waf install"
