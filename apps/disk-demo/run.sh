#!/usr/bin/env bash
# Run the disk demo on the emulated iBook. The 16 MiB FAT image at
# disk-data.img is attached as the slave of the first KeyLargo IDE
# bus (index 1), which is /dev/hdb in the guest. mtools is used to
# place a file on the image before the guest boots.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)

IMG=disk-data.img
if [ ! -f "$IMG" ]; then
  echo "creating $IMG"
  dd if=/dev/zero of="$IMG" bs=1M count=16 status=none
  "$ROOT/tools/with.sh" dosfstools -- mkfs.fat -n RTEMSTEST "$IMG"
fi

# Fresh host file every run so the guest always has something to read
# and the leftover guest file from the previous run disappears.
"$ROOT/tools/with.sh" mtools -- bash -c "
  echo 'hello from host' > hostfile.txt
  mdel -i $IMG ::hostfile.txt 2>/dev/null || true
  mdel -i $IMG ::rtems-wrote.txt 2>/dev/null || true
  mcopy -i $IMG hostfile.txt ::hostfile.txt
  rm -f hostfile.txt"

exec "$ROOT/run-g3.sh" -rtems app-ibookg3.exe \
  -drive "file=$PWD/$IMG",if=ide,index=1,format=raw "$@"
