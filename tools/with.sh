#!/usr/bin/env bash
# Run a command with the tools it needs, taking any that are not installed
# from nixpkgs:
#
#   tools/with.sh mtools dosfstools -- cmd args...
#
# Each package is checked by a program it provides, so on a system that
# already has them (the Docker image, most Linux distributions) the
# command runs as it is, and Nix is needed only for what is missing.
set -euo pipefail
program() {
  case $1 in
    dosfstools) echo mkfs.fat ;;
    mtools) echo mcopy ;;
    util-linux) echo sfdisk ;;
    *) echo "$1" ;;
  esac
}
missing=()
while [ "$1" != -- ]; do
  command -v "$(program "$1")" >/dev/null || missing+=("nixpkgs#$1")
  shift
done
shift
[ ${#missing[@]} -eq 0 ] && exec "$@"
command -v nix >/dev/null || {
  echo "with.sh: missing ${missing[*]#nixpkgs#}; install it or Nix" >&2
  exit 127
}
exec nix shell "${missing[@]}" -c "$@"
