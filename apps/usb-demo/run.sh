#!/usr/bin/env bash
# Run the USB demo on the emulated iBook.
#
# run-g3.sh already attaches a USB keyboard and mouse to the machine's
# built-in KeyLargo OHCI.  This script adds a USB mass storage device
# (a FAT-partitioned image) and a QEMU monitor on a unix socket, waits for the
# guest to open /dev/ukbd0, then types "hello" through the monitor's
# sendkey commands.  The guest must print the same five characters
# back, proving the round trip through ohci0 -> usbus0 -> ukbd0 ->
# /dev/ukbd0.
#
# The transcript lands in run.log and the expected markers are checked
# at the end.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)

LOG=run.log
MON=qemu-monitor.sock
DISK=usbdisk.img

rm -f "$LOG" "$MON"

# A 16 MiB USB stick: an MBR with one FAT partition starting at 1 MiB,
# like a stick formatted on a PC, holding a file for the guest to read.
PART_OFFSET=$((1024 * 1024))
rm -f "$DISK"
truncate -s 16M "$DISK"
"$ROOT/tools/with.sh" util-linux dosfstools mtools -- bash -c "
  set -euo pipefail
  echo 'start=2048, type=0c' | sfdisk -q $DISK
  mkfs.fat -n USBDEMO --offset 2048 $DISK \$(( (16 * 1024 - 1024) )) >/dev/null
  echo 'hello from host' > hostfile.txt
  mcopy -i $DISK@@$PART_OFFSET hostfile.txt ::hostfile.txt
  rm -f hostfile.txt"

# The machine's OHCI root hub has three ports; the keyboard and mouse
# from run-g3.sh take ports 1 and 2, so pin the storage device to
# port 3.  Without it QEMU auto-placement parks it behind an extra
# emulated hub the guest takes much longer to enumerate.
timeout -s KILL 150 "$ROOT/run-g3.sh" -rtems app-ibookg3.exe \
  -monitor "unix:$MON,server,nowait" \
  -drive "file=$DISK,if=none,format=raw,id=usbdisk" \
  -device usb-storage,drive=usbdisk,port=3 \
  > "$LOG" 2>&1 &
QEMU=$!

# Type "hello" once the guest has the keyboard open, so no keystroke
# is lost before ukbd is attached and polling.
TYPED=no
for i in $(seq 1 120); do
  kill -0 $QEMU 2>/dev/null || break
  if grep -q "usb-demo: keyboard open" "$LOG" 2>/dev/null; then
    python3 -c '
import socket, sys, time
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
s.settimeout(2)
try:
    s.recv(4096)          # monitor greeting banner
except socket.timeout:
    pass
for key in "hello":
    s.sendall(b"sendkey " + key.encode() + b"\n")
    time.sleep(0.3)
s.close()
' "$MON" && TYPED=yes && break
  fi
  sleep 1
done
echo "host: typed hello over the monitor: $TYPED"

# Let the guest finish and shut down.
for i in $(seq 1 60); do
  grep -q "=== done ===" "$LOG" 2>/dev/null && break
  sleep 1
done

# With SCREENSHOT set, run-g3.sh saves the screen and stops QEMU itself
if [ -z "${SCREENSHOT:-}" ]; then
  kill -0 $QEMU 2>/dev/null && kill $QEMU 2>/dev/null || true
fi
wait $QEMU 2>/dev/null || true
rm -f "$MON"

# What the guest wrote, read back on the host, and a check of the volume.
WROTE=$("$ROOT/tools/with.sh" mtools -- mtype -i "$DISK@@$PART_OFFSET" ::usb-wrote.txt 2>/dev/null || true)
FSCK=$("$ROOT/tools/with.sh" dosfstools -- bash -c "
  dev=\$(mktemp); dd if=$DISK of=\$dev bs=1M skip=1 status=none
  fsck.fat -n \$dev >/dev/null 2>&1 && echo clean || echo dirty; rm -f \$dev")
echo "host: usb-wrote.txt contains: ${WROTE:-<missing>}"
echo "host: fsck.fat on the partition: $FSCK"
rm -f "$DISK"

echo "--- guest transcript ---"
cat "$LOG"
echo "------------------------"

fail=0
grep -q "ohci0: <Apple" "$LOG" || { echo "MISSING: OHCI controller attach"; fail=1; }
grep -q "usbus0 on ohci0" "$LOG" || { echo "MISSING: USB bus on OHCI"; fail=1; }
grep -q "ukbd0: " "$LOG" || { echo "MISSING: USB keyboard driver attach"; fail=1; }
grep -q "umass0: " "$LOG" || { echo "MISSING: USB mass storage attach"; fail=1; }
grep -q "usb-demo: received 5 bytes: hello" "$LOG" || { echo "MISSING: keystroke round trip"; fail=1; }
grep -q "usb-demo: USB stick mounted at" "$LOG" || { echo "MISSING: USB stick mount"; fail=1; }
grep -q "usb-demo: read 16 bytes from USB: hello from host" "$LOG" || { echo "MISSING: USB stick read"; fail=1; }
grep -q "usb-demo: unmounted" "$LOG" || { echo "MISSING: USB stick unmount"; fail=1; }
[ "$WROTE" = "written by RTEMS over USB" ] || { echo "MISSING: guest file on the host side"; fail=1; }
[ "$FSCK" = clean ] || { echo "MISSING: clean FAT volume after the guest wrote"; fail=1; }
grep -q "=== done ===" "$LOG" || { echo "MISSING: guest completed"; fail=1; }

if [ $fail -eq 0 ]; then
  echo "usb-demo: PASS (OHCI, keyboard round trip, USB stick mount + read + write)"
else
  echo "usb-demo: FAIL"
  exit 1
fi
