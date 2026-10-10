#!/usr/bin/env bash
# Clone the upstream RTEMS repositories into src/ at the commits the patches
# in patches/ are based on, and apply them on local branches:
#
#   src/rtems           RTEMS 6.2, branch bsp-ibookg3
#   src/rtems-libbsd    rtems-libbsd 6-freebsd-14, branch bsp-ibookg3
#   src/rtems-tools     rtems-tools main, branch tester-ibookg3 (rtems-test)
#   src/rtems-tools-6   rtems-tools 6 (the version RSB installs), branch
#                       rap-relocs-6 (rtems-ld fix), a worktree of the above
#   src/rsb             RTEMS Source Builder 6, branch 6-nixos
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
GL=https://gitlab.rtems.org/rtems
mkdir -p "$ROOT/src"
cd "$ROOT/src"

# apply patches/$2/*.patch to $1 on a new branch $3 starting at $4
apply() {
  local dir=$1 series=$2 branch=$3 base=$4
  git -C "$dir" switch -q -c "$branch" "$base"
  # git am records a committer; give the clone one if none is configured
  git -C "$dir" config user.email >/dev/null ||
    git -C "$dir" config user.email "setup@localhost"
  git -C "$dir" config user.name >/dev/null ||
    git -C "$dir" config user.name "ibook-g3-rtems setup"
  git -C "$dir" am -q "$ROOT"/patches/"$series"/*.patch
  echo "$dir: $branch ($(ls "$ROOT/patches/$series" | wc -l) patches on ${base:0:12})"
}

[ -d rtems ] || git clone -q "$GL/rtos/rtems.git" rtems
apply rtems rtems bsp-ibookg3 be446b02d091a2a745e03405eaab4de078571532
cp "$ROOT/tools/rtems-config.ini" rtems/config.ini

[ -d rtems-libbsd ] || git clone -q "$GL/pkg/rtems-libbsd.git" rtems-libbsd
apply rtems-libbsd rtems-libbsd bsp-ibookg3 86102312403dca2087e3d565aaa99a519ba1d301
git -C rtems-libbsd submodule update -q --init rtems_waf

[ -d rtems-tools ] || git clone -q "$GL/tools/rtems-tools.git" rtems-tools
apply rtems-tools rtems-tools-tester tester-ibookg3 69ad12c299b0fa57d8fc5744faff3d681ef0e4d3
git -C rtems-tools worktree add -q --detach ../rtems-tools-6 adf3e254d08f678d3625a4edccb2ac3485d96519
apply rtems-tools-6 rtems-tools rap-relocs-6 adf3e254d08f678d3625a4edccb2ac3485d96519

[ -d rsb ] || git clone -q "$GL/tools/rtems-source-builder.git" rsb
apply rsb rtems-source-builder 6-nixos 84b3f5660ebaa96e1e405ca12f67b538b48636d6

echo "done; next: ./build-toolchain.sh, then tools/rebuild-all.sh"
