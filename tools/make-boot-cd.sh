#!/usr/bin/env bash
# Make a Mac-bootable CD image (Apple partition map + HFS+, ISO9660 hybrid)
# holding an RTEMS ELF as \rtems.elf, for Open Firmware to boot.
#
#   tools/make-boot-cd.sh app-ibookg3-hw.elf boot.iso
#
# The ELF must be linked for real Open Firmware (build.sh with HW=1), so
# that its load addresses equal its run addresses (0x01000000).
# Boot it from the Open Firmware prompt (Cmd-Option-O-F) with
#   boot cd:3,\rtems.elf
# (the HFS+ volume is partition 3 of the partition map), or in QEMU with
# run-g3.sh -rtems-cd boot.iso.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ELF=${1:?usage: make-boot-cd.sh app.elf out.iso}
ISO=${2:?usage: make-boot-cd.sh app.elf out.iso}
ENTRY=$("$ROOT/rtems/bin/powerpc-rtems6-readelf" -h "$ELF" | awk '/Entry point/ {print $4}')
PADDR=$("$ROOT/rtems/bin/powerpc-rtems6-readelf" -lW "$ELF" | awk '$1 == "LOAD" {print $4; exit}')
if [ "$PADDR" != "0x01000000" ]; then
  echo "make-boot-cd: $ELF loads at $PADDR, not 0x01000000; build it with HW=1" >&2
  exit 1
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$ELF" "$TMP/rtems.elf"
nix shell nixpkgs#xorriso -c xorriso -as mkisofs -quiet -r -hfsplus \
  -apm-block-size 2048 -V RTEMS -o "$ISO" "$TMP"
echo "made $ISO (entry $ENTRY): at the Open Firmware prompt, boot cd:3,\\rtems.elf"
