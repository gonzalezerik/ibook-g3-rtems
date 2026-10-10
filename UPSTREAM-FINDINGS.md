# Upstream bugs found while porting RTEMS to the iBook G3

Findings 1 and 2 are new (one confirmed, one unproven). 3 to 5 are known
upstream bugs with fixes implemented or backported here, and 6 lists fixes
backported from RTEMS. **Nothing has been reported or submitted upstream
yet**: the plan is to confirm them on a real iBook G3 first.

## 1. FreeBSD gem(4): software reset writes the interrupt mask

**Where:** `sys/dev/gem/if_gemreg.h` in FreeBSD 14.0 and later, including
`main` as of 2026-10-09. rtems-libbsd `6-freebsd-14` inherits it.

**What:** the Sun GEM / Apple GMAC software reset register is at offset
`0x1010` of the PCI BAR. FreeBSD used to reach it as offset `0x0010` of a
second register bank mapped at `BAR + 0x1000` (`GEM_PCI_BANK2_OFFSET`).
Commit `8defc88c1345` (2023-04-18, "gem(4): Remove onboard-only Sun ERI and
remnants of SBus support") merged the banks and moved the other bank-two
registers to `0x10xx` (`GEM_PCI_ERROR_STATUS` 0x0000 → 0x1000, …), but left
`GEM_RESET` at `0x0010`. That offset is `GEM_INTMASK`.

**Effect:** every reset since FreeBSD 14.0 writes the interrupt mask
instead, and the controller is never reset. The driver prints
`cannot reset receiver`, `cannot reset transmitter` and `cannot reset device`
on every PCI GEM/GMAC, on real hardware as well as in QEMU. The interface
may still pass traffic, as it does in QEMU, but it is never put into a known
state.

**Fix:** `#define GEM_RESET 0x1010`, in
`patches/rtems-libbsd/0007-gem-Fix-the-software-reset-register-offset.patch`.

**Evidence (QEMU, `apps/net-demo`):** with the fix, `cannot reset device`
(the full RX+TX reset) no longer appears. QEMU's model resets at `0x1010`
(`GREG_SWRST`), as Sun's documentation describes. `cannot reset receiver`
and `cannot reset transmitter` still appear on QEMU, for a different reason:
QEMU's sungem performs a receiver-only or transmitter-only reset but never
clears that bit (it does clear both bits after a full reset). Real hardware
clears the bits, so on the iBook none of the messages should appear with the
fix.

**To confirm on hardware:** boot net-demo on the real iBook with and without
the fix, and compare the boot messages and link behaviour.

## 2. RTEMS PowerPC: classic exception return keeps the `lwarx` reservation (unproven)

**Where:** `bsps/powerpc/shared/exceptions/ppc_exc_asm_macros.h`, the `WRAP`
macro used by every classic 603/604/750/74xx BSP (psim, motorola_powerpc,
mvme*, beatnik, …). Unchanged on RTEMS `main` as of 2026-10-08.

**What:** PowerPC exceptions do not clear the `lwarx` reservation. RTEMS
commit `5c7bfcf82e1c` (2015) clears it in the fast asynchronous exit
(`ppc_exc_async_normal.S`) and explains why: a compare-and-swap interrupted
before its `stwcx.` can otherwise succeed using a reservation the handler
took, after the handler changed the value. The classic `WRAP` exit never
got the same treatment.

**Status: a hypothesis, not a demonstrated bug.** An earlier version of
this file claimed it caused the `spintrcritical24` hang. That was wrong:
- The hang is RTEMS issue #5411, a race in the file descriptor free path
  (see 3).
- Uniprocessor RTEMS builds implement their atomic operations by disabling
  interrupts, so the RTEMS core does not use `lwarx`/`stwcx.` there at all.
- The test only appeared fixed because the extra instructions shifted the
  timing under `-icount`.

Only code using `lwarx`/`stwcx.` directly or through compiler builtins (some
library or application code, SMP builds) could be affected. The change stays
in `patches/rtems/` (0001, "bsps/powerpc: Clear reservation in exception
wrapper") because it mirrors the fast path and costs three instructions,
but nothing has been shown to need it.

**Before ever submitting:** find code on a classic PowerPC that actually
uses a reservation across an interrupt, and show a failure without the
change.

## 3. Known RTEMS bug, fixed upstream after 6.2: file descriptor free race

Not a new finding, recorded because it affects this workbench.

**What:** RTEMS issue #5411. `rtems_libio_free_iop()` could append the same
iop to the free list twice when a file descriptor is released from
interrupt context while a task is in the free/allocate path, making the
list a cycle. Fixed on RTEMS `main` by commit `9ff62c34f7d2` (2026-02-12,
Aaron Nyholm), after the 6.2 release.

**Effect here:** `spintrcritical24` hung in about 1 of 4 runs under
`-icount`, spinning in `T_count_open_fds()`.

**Fix:** the upstream commit cherry-picked into `patches/rtems/` (0008),
keeping its author. After that, 40 of 40 runs under `-icount` pass, against
13 to 15 of 20 before.

## 4. rtems-ld writes RAP files the loader cannot read (known bug, new fix)

**Where:** `rtemstoolkit/rld-rap.cpp` in rtems-tools, since commit
`0ad4aaaf` (2020, "linker/rap: Ignore relocation records with no section").
Still in rtems-tools `main` as of 2026-10-05. Known: rtems-tools issue #1
(2023, open) describes the count mismatch, but no fix has landed.

**What:** when writing relocations, rtems-ld skips every record whose
symbol has section index 0, but still counts it in the section's
relocation header. A symbol undefined in its object, meaning defined in
another object of the module or in the base image, also has section index
0. So every call from a module into the base image (`rtems_printf`,
`dlsym`, …) or between the module's objects is dropped, and the loader
reads the following data as relocation records. For `dl06` the header
said 302 relocations for `.text`, 269 were written, and the load failed at
record 269 with "global symbol not found:" and an empty name.

**Fix:** skip only records without any symbol, write those against
undefined symbols by name (the loader resolves names in the module first,
then in the base image), and count what is written. `patches/rtems-tools/`,
on the rtems-tools version RSB installs; `build-toolchain.sh` installs it
into `rtems/`. `dl06` passes with it. Verified on
PowerPC only. Issue #1 reports that writing these records "crashed" on
ARM, and rtems-tools #44 describes a separate RAP layout bug seen on i386,
so other architectures need their own check.

## 5. dl06 pulls thread-local storage into a module (known, fix implemented)

RTEMS issue #5802 (open): the module calls `lcong48()`, whose object file
in a Newlib with thread-local reentrancy defines thread-local state, which
a loaded module cannot have. The issue suggests linking `lcong48()` into
the base image. Implemented in `patches/rtems/` (0014,
"testsuites/libtests/dl06: Link lcong48() into the base image". `dl06`
needs both this and fix 4.

## 6. Fixes backported from RTEMS main (not new)

Cherry-picked into `patches/rtems/` with their original authors:

| Test | Upstream commit | Author |
|---|---|---|
| `spintrcritical24` | `9ff62c34` cpukit/libio: Fix race condition in iop free (#5411) | Aaron Nyholm |
| `spinternalerror02` | `5efed522` cpukit/sapi/src/interrtext.c: Add missing definition | Kinsey Moore |
| `spfatal31` | `3f419911` testsuites/sptests: Fix spfatal31 for PowerPC | Sebastian Huber |
| `psx09` | `c0ccc65b` psxtests/psx09: Use a scheduler which exists (#5788) | Sebastian Huber |
| `psx09` | `0e1a26fc` score: Inhibit a scheduler change without SMP (#5745) | Sebastian Huber |

The last one is a core fix: without it, the `psx09` test fix ran into a
corrupted priority tree and hung, on psim as well as on the iBook BSP.
