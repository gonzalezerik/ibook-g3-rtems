#!/usr/bin/env python3
"""Run RTEMS test executables on the emulated iBook G3 (QEMU mac99, 750cx).

Each test boots under QEMU with the console on stdout. A test ends at
"*** END OF TEST", at RTEMS shutdown/fatal output, or at the timeout; QEMU is
then stopped (the BSP idles after shutdown instead of powering off).

usage: run-testsuite.py [-j N] [-t SECONDS] [-m MB] [--icount] TESTDIR OUTDIR
"""

import argparse
import concurrent.futures
import os
import re
import subprocess
import sys
import time

STATE_RE = re.compile(r"\*\*\* TEST STATE: (\S+)")
END = "*** END OF TEST"
SHUTDOWN = "[ RTEMS shutdown ]"
FATAL = re.compile(r"\*\*\* FATAL|RTEMS_FATAL|fatal source")


def run_one(exe, outdir, timeout, mem, icount):
    name = os.path.relpath(exe)
    log_path = os.path.join(outdir, os.path.basename(exe) + ".log")
    cmd = [
        "qemu-system-ppc", "-M", "mac99", "-cpu", "750cx", "-m", str(mem),
        "-nographic", "-no-reboot", "-net", "none", "-kernel", exe
    ]
    if icount:
        # virtual time from the instruction count: deterministic timers
        cmd[1:1] = ["-icount", "shift=4,align=off"]
    start = time.monotonic()
    proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    os.set_blocking(proc.stdout.fileno(), False)
    out = b""
    result = "timeout"
    while time.monotonic() - start < timeout:
        chunk = proc.stdout.read()
        if chunk:
            out += chunk
            text = out.decode("latin-1")
            if END in text:
                result = "passed"
                break
            if SHUTDOWN in text or FATAL.search(text):
                # Let the shutdown report finish printing.  Some tests
                # cause a fatal error on purpose and still end normally,
                # so look for the end marker once more.
                time.sleep(2)
                out += proc.stdout.read() or b""
                result = "passed" if END in out.decode("latin-1") else "failed"
                break
        elif proc.poll() is not None:
            result = "failed"
            break
        else:
            time.sleep(0.05)
    proc.kill()
    proc.wait()
    rest = proc.stdout.read()
    if rest:
        out += rest
    text = out.decode("latin-1").replace("\r", "")
    m = STATE_RE.search(text)
    state = m.group(1) if m else "EXPECTED_PASS"
    if state == "USER_INPUT" and result == "timeout":
        result = "user-input"
    elif state == "EXPECTED_FAIL":
        result = "expected-fail" if result != "passed" else "unexpected-pass"
    elif state == "INDETERMINATE" and result != "passed":
        result = "indeterminate"
    elif state == "BENCHMARK" and result == "passed":
        result = "benchmark"
    with open(log_path, "w") as f:
        f.write(text)
    return name, result, time.monotonic() - start


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-j", type=int, default=16)
    ap.add_argument("-t", type=float, default=180)
    ap.add_argument("-m", type=int, default=128)
    ap.add_argument("--icount", action="store_true",
                    help="run QEMU with -icount shift=4,align=off (as rtems-test does)")
    ap.add_argument("testdir")
    ap.add_argument("outdir")
    args = ap.parse_args()

    exes = sorted(
        os.path.join(root, f)
        for root, _, files in os.walk(args.testdir)
        for f in files
        if f.endswith(".exe") and not f.endswith(".norun.exe"))
    os.makedirs(args.outdir, exist_ok=True)

    counts = {}
    results = []
    with concurrent.futures.ThreadPoolExecutor(args.j) as pool:
        futures = [pool.submit(run_one, e, args.outdir, args.t, args.m,
                               args.icount)
                   for e in exes]
        for i, fut in enumerate(concurrent.futures.as_completed(futures), 1):
            name, result, secs = fut.result()
            counts[result] = counts.get(result, 0) + 1
            results.append((name, result, secs))
            print(f"[{i:3}/{len(exes)}] {result:15} {secs:6.1f}s {name}",
                  flush=True)

    with open(os.path.join(args.outdir, "summary.txt"), "w") as f:
        for name, result, secs in sorted(results):
            f.write(f"{result:15} {secs:6.1f}s {name}\n")
        f.write("\n")
        for k in sorted(counts):
            f.write(f"{k}: {counts[k]}\n")
    print()
    for k in sorted(counts):
        print(f"{k}: {counts[k]}")
    return 0 if counts.get("failed", 0) + counts.get("timeout", 0) == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
