#!/usr/bin/env bash
# iBook G3 (M6497) emulator — QEMU mac99 + PowerPC 750cx (G3), NewWorld Open Firmware.
#
# RAM matches Perseverance rover's main computer: the RAD750 has 128 MB DRAM
# (per Wikipedia's Perseverance article; the same 750-family CPU the iBook uses).
# Override with e.g.  MEM=256 ./run-g3.sh
# AUDIO=none to run without PipeWire, DISPLAY_OPT=vnc=0.0.0.0:0 for a VNC screen.
#
# Modes:
#   ./run-g3.sh                 boot the disk image (disk/g3.qcow2) via Open Firmware
#   ./run-g3.sh -cdrom foo.iso  boot an installer CD
#   ./run-g3.sh -kernel vmlinux   direct-boot your own kernel/OS (OpenBIOS loads it)
#   ./run-g3.sh -of             drop to the Open Firmware prompt only
#   ./run-g3.sh -rtems app.exe  run an RTEMS program (ibookg3 BSP); console on this
#                               terminal, quit with Ctrl-A x
#   ./run-g3.sh -rtems-cd x.iso boot an RTEMS CD made by tools/make-boot-cd.sh through
#                               Open Firmware, the way the real iBook boots it
#   SCREENSHOT=x.png ./run-g3.sh -rtems ...  also save the emulated screen
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

MEM=${MEM:-128}                      # MB — RAD750 DRAM
CPU=${CPU:-750cx}                    # the iBook G3's exact core
DISK="$DIR/disk/g3.qcow2"

ARGS=(
  -machine mac99                     # NewWorld PowerMac: UniNorth, what NewWorld OF expects
  -cpu "$CPU"
  -m "$MEM"
  -prom-env 'auto-boot?=true'
  -audiodev "${AUDIO:-pipewire},id=snd0"   # AUDIO=none where there is no PipeWire
  -device es1370,audiodev=snd0       # no Screamer in mainline QEMU; ES1370 is driven by OS 9/X + Linux PPC
  -device usb-kbd -device usb-mouse   # on mac99's built-in Apple OHCI, like the real iBook
)
# the guest OS disk image is your own (none ships with this repository)
if [[ -f "$DISK" ]]; then
  ARGS+=(-drive file="$DISK",if=ide,format=qcow2)
fi

# Networking: the guest OSes boot off the RTL8139 QEMU exposes as a PCI
# add-on; the RTEMS drivers target the machine's real devices, so the
# -rtems mode attaches mac99's built-in Sun GEM GMAC instead, with the
# demo port forwards.
NET_BASE=(
  -netdev user,id=n0,hostfwd=tcp::2222-:22
  -device rtl8139,netdev=n0          # NewWorld Linux/macOS both drive this fine
)
NET_RTEMS=(
  -netdev user,id=n0,hostfwd=tcp::7007-:7007
  -device sungem,netdev=n0           # mac99's built-in GMAC, the iBook's real chip
)

# Run an RTEMS image with the console on this terminal. With SCREENSHOT=x.png
# the emulated screen is saved once the console shows SCREENSHOT_AFTER (an
# extended regex, by default the RTEMS shutdown report) and QEMU is stopped.
run_rtems() {
  if [[ -z "${SCREENSHOT:-}" ]]; then
    exec qemu-system-ppc "$@" -nographic
  fi

  local tmp mon log after pid
  tmp=$(mktemp -d)
  mon=$tmp/mon.sock
  log=$tmp/console.log
  after=${SCREENSHOT_AFTER:-executing thread name}
  qemu-system-ppc "$@" -display none -serial stdio \
    -monitor "unix:$mon,server,nowait" > >(tee "$log") 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    grep -qaE "$after" "$log" 2>/dev/null && break
    sleep 0.5
  done
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    python3 - "$mon" "$tmp/screen.png" <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
time.sleep(0.3)
s.recv(4096)
s.sendall(b"screendump " + sys.argv[2].encode() + b" -f png\n")
time.sleep(1.5)
s.close()
PY
    kill "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
  if [[ -s "$tmp/screen.png" ]]; then
    cp "$tmp/screen.png" "$SCREENSHOT"
    echo "run-g3: screen saved to $SCREENSHOT" >&2
  else
    echo "run-g3: no screenshot taken" >&2
  fi
  rm -rf "$tmp"
  exit 0
}

# pass through extra flags (-cdrom, -kernel, -initrd, -append, ...)
EXTRA=("$@")
if [[ "${EXTRA[0]:-}" == "-of" ]]; then
  EXTRA=("${EXTRA[@]:1}")
  exec qemu-system-ppc "${ARGS[@]}" "${NET_BASE[@]}" "${EXTRA[@]}" -nographic
fi
if [[ "${EXTRA[0]:-}" == "-rtems" ]]; then
  [[ -n "${EXTRA[1]:-}" ]] || { echo "usage: $0 -rtems app.exe" >&2; exit 2; }
  EXE=${EXTRA[1]}
  EXTRA=("${EXTRA[@]:2}")
  run_rtems "${ARGS[@]}" "${NET_RTEMS[@]}" -kernel "$EXE" "${EXTRA[@]}"
fi
if [[ "${EXTRA[0]:-}" == "-rtems-cd" ]]; then
  [[ -n "${EXTRA[1]:-}" ]] || { echo "usage: $0 -rtems-cd boot.iso" >&2; exit 2; }
  ISO=${EXTRA[1]}
  EXTRA=("${EXTRA[@]:2}")
  # QEMU's CD drive is the master of the second KeyLargo ATA bus; the
  # HFS+ volume is partition 3 of the CD's Apple partition map
  run_rtems "${ARGS[@]}" "${NET_RTEMS[@]}" -cdrom "$ISO" -boot d \
    -prom-env 'boot-device=/pci/mac-io/ata-3@21000/cdrom@0:3,\rtems.elf' \
    "${EXTRA[@]}"
fi

if [[ ${#EXTRA[@]} -eq 0 && ! -f "$DISK" ]]; then
  echo "run-g3: no disk image at $DISK; give -cdrom, -kernel, -of or -rtems" >&2
  exit 2
fi
# DISPLAY_OPT=vnc=0.0.0.0:0 shows the screen over VNC instead of in a local
# window (the Docker image has none); the other modes use the serial console
if [[ -n "${DISPLAY_OPT:-}" ]]; then
  EXTRA+=(-display "$DISPLAY_OPT")
fi
exec qemu-system-ppc "${ARGS[@]}" "${NET_BASE[@]}" "${EXTRA[@]}"
