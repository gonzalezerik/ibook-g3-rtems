#!/usr/bin/env bash
# Run the network demo on the emulated iBook.
#
# run-g3.sh -rtems attaches the guest (modeled as the iBook's Sun GEM
# GMAC) to QEMU user networking with hostfwd port 7007.  This script
# drives the host side of both TCP directions:
#
#   up:    host -> guest   connect to 127.0.0.1:7007 (hostfwd), send a
#                          line, expect the greeting back.
#   down:  guest -> host   a listener on 127.0.0.1:7008 answers the
#                          guest's connect to 10.0.2.2:7008 (the user
#                          networking alias) with a line.
#
# The transcript lands in run.log and the expected markers are checked
# at the end.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)

LOG=run.log

# Host side of the down direction, armed before the guest boots.
python3 -c '
import socket
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 7008))
s.listen(1)
c, _ = s.accept()
c.sendall(b"hello from host\n")
c.close()
' &
LISTENER=$!

rm -f "$LOG"
timeout -s KILL 150 "$ROOT/run-g3.sh" -rtems app-ibookg3.exe \
  > "$LOG" 2>&1 &
QEMU=$!

# Up direction: QEMU's forwarder accepts a host connect even while
# the guest is not listening yet, so wait for the guest to report its
# listen socket before sending, and retry the exchange each second in
# the meantime.
EXCHANGED=no
for i in $(seq 1 120); do
  kill -0 $QEMU 2>/dev/null || break
  grep -q "listening on port 7007" "$LOG" 2>/dev/null || { sleep 1; continue; }
  if python3 -c '
import socket, sys
s = socket.create_connection(("127.0.0.1", 7007), timeout=15)
s.sendall(b"hello from host\n")
sys.stdout.write(s.recv(100).decode())
' > serve.out 2>/dev/null; then
    if grep -q "hello from rtems" serve.out; then
      EXCHANGED=yes
      echo "host: serve exchange ok: $(cat serve.out)"
      break
    fi
  fi
  sleep 1
done

# Let the guest finish the fetch direction and shut down.
for i in $(seq 1 60); do
  grep -q "=== done ===" "$LOG" 2>/dev/null && break
  sleep 1
done

# With SCREENSHOT set, run-g3.sh saves the screen and stops QEMU itself
if [ -z "${SCREENSHOT:-}" ]; then
  kill -0 $QEMU 2>/dev/null && kill $QEMU 2>/dev/null || true
fi
wait $QEMU 2>/dev/null || true
kill $LISTENER 2>/dev/null || true
rm -f serve.out

echo "--- guest transcript ---"
cat "$LOG"
echo "------------------------"

fail=0
grep -q "reason=BOUND" "$LOG" || { echo "MISSING: DHCP lease (reason=BOUND)"; fail=1; }
grep -q "ip_address=10\.0\.2\." "$LOG" || { echo "MISSING: DHCP lease address"; fail=1; }
grep -q "ping 10.0.2.2 exit 0" "$LOG" || { echo "MISSING: ping success"; fail=1; }
grep -q "got .*hello from host" "$LOG" || { echo "MISSING: serve direction payload"; fail=1; }
grep -q "fetched .*hello from host" "$LOG" || { echo "MISSING: fetch direction payload"; fail=1; }
grep -q "sent 17 bytes" "$LOG" || { echo "MISSING: serve reply"; fail=1; }
[ "$EXCHANGED" = yes ] || { echo "MISSING: host side of serve exchange"; fail=1; }
grep -q "=== done ===" "$LOG" || { echo "MISSING: guest completed"; fail=1; }

if [ $fail -eq 0 ]; then
  echo "net-demo: PASS (DHCP lease, ping, TCP both directions)"
else
  echo "net-demo: FAIL"
  exit 1
fi
