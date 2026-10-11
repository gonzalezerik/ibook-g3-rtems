#!/usr/bin/env bash
# Build the RTEMS 6 PowerPC toolchain into rtems/ (or PREFIX) with src/rsb
# (the RSB 6 branch plus NixOS support). Run setup.sh first. On NixOS the
# build runs in the dev shell of rsb-shell.nix, no FHS sandbox needed; on
# other systems the RSB's usual host packages must be installed (see the
# Dockerfile for a Debian list).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$ROOT/rtems}
JOBS=${JOBS:-$(nproc)}
in_env() {
  if [ -e /etc/NIXOS ]; then
    nix-shell "$ROOT/rsb-shell.nix" --run "$1"
  else
    bash -c "$1"
  fi
}
cd "$ROOT/src/rsb/rtems"
in_env "../source-builder/sb-set-builder --jobs=$JOBS \
  --prefix=$PREFIX --log=$ROOT/rsb-toolchain-build.log 6/rtems-powerpc"

# RSB installs rtems-tools as released; reinstall the same version with the
# rtems-ld RAP relocation fix (see UPSTREAM-FINDINGS.md)
cd "$ROOT/src/rtems-tools-6"
in_env "./waf distclean configure --prefix=$PREFIX && ./waf && ./waf install"
