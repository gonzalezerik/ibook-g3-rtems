# iBook G3 / RTEMS workbench

Emulated Apple iBook G3 (M6497, PowerPC 750CX) with 128 MB of RAM, the same
amount as the Perseverance rover's RAD750, plus an RTEMS 6.2 PowerPC
toolchain and an RTEMS BSP (`ibookg3`) for it, with disk, network and USB
support. It runs on QEMU's `mac99` machine; it has not run on a real iBook
yet.

![The emulated iBook's screen after the starter app ran: boot lines report
the CPU at 900 MHz, a 100 MHz bus, a 25 MHz timebase, 128 MiB of RAM and an
800x600 32-bit display, then "Hello from RTEMS on PowerPC", tick 0 to tick 2
and the RTEMS shutdown report.](docs/screenshots/starter.png)

## Set up

Needs Nix (developed on NixOS) and QEMU with `qemu-system-ppc`.

```sh
./setup.sh                 # clone RTEMS, rtems-libbsd, rtems-tools and the RSB
                           # into src/ at pinned commits and apply patches/
./build-toolchain.sh       # PowerPC toolchain into rtems/ (takes a while)
tools/rebuild-all.sh       # RTEMS (ibookg3 + psim BSPs) and rtems-libbsd
```

This repository holds only the changes, as `git format-patch` series in
`patches/`, plus the scripts and demo programs; `setup.sh` turns them back
into branches.

## Develop

```sh
cp -r apps/starter apps/myapp     # new program
apps/myapp/build.sh               # -> app-ibookg3.exe
apps/myapp/run.sh                 # run on the emulated iBook (Ctrl-A x quits)
apps/myapp/debug.sh               # same under GDB, stops at Init
BSP=psim apps/myapp/build.sh && BSP=psim apps/myapp/run.sh   # GDB's simulator
```

Console output goes to the serial port (this terminal) and is also drawn
on the iBook's screen, which is what the screenshots here show.
`SCREENSHOT=shot.png apps/myapp/run.sh` saves the screen once the program
has finished.

`apps/rad750-check` checks the 128 MB memory on both targets.

### Memory

128 MB is a choice, not a limit: it matches the RAD750. The BSP takes the
RAM size from Open Firmware, so `MEM=256 apps/myapp/run.sh` (or any size up
to the iBook's maximum of 640 MB, and beyond in QEMU) just works.
`apps/rad750-check` fills and verifies memory to prove it.

## Hardware demos

The `run.sh` of `net-demo` and `usb-demo` drives the host side of the test
and prints PASS or FAIL; `disk-demo` prints what it read and wrote.

| App | What it proves |
|---|---|
| `apps/disk-demo` | KeyLargo ATA: `/dev/hdX` block read/write round trip through libblock + DOSFS |
| `apps/net-demo` | UniNorth GMAC via rtems-libbsd `gem`: DHCP lease, ping of the gateway, one TCP connection in each direction |
| `apps/usb-demo` | KeyLargo OHCI via rtems-libbsd: `ukbd` keystroke round trip through the QEMU monitor `sendkey`; a USB stick (MBR + FAT) mounted by the media server, a host file read and a file written, checked on the host |

### Disk

![disk-demo on the iBook's screen: "Disk demo: KeyLargo ATA", "mounted
/dev/hdb at /mnt", "read 16 bytes from /mnt/hostfile.txt: hello from host",
"wrote 37 bytes to /mnt/rtems-wrote.txt", "=== done ===".](docs/screenshots/disk-demo.png)

### Network

![net-demo on the iBook's screen: the DHCP lease (10.0.2.15, router
10.0.2.2), the gem0 interface up, three ping replies from 10.0.2.2 with 0%
packet loss, "got 16 bytes: hello from host" on port 7007, "sent 17 bytes",
"fetched 16 bytes: hello from host" from 10.0.2.2:7008, "=== done
===".](docs/screenshots/net-demo.png)

### USB

![usb-demo on the iBook's screen: the OHCI root hub with the QEMU USB
keyboard, mouse and hard drive attached, the media server mounting the
stick's partition at /media/umass-sim-0-0, "received 5 bytes: hello" from
the keyboard, "read 16 bytes from USB: hello from host", "wrote 26 bytes to
USB", "unmounted /media/umass-sim-0-0", "=== done ===".](docs/screenshots/usb-demo.png)

`run-g3.sh -rtems` attaches the machine's real Sun GEM (not the RTL8139
the disk-image OSes use) with the port forwards the net-demo needs.

## Booting like the real iBook

QEMU's `-kernel` option needs images linked with load address zero; Open
Firmware on a real Mac loads an ELF where its load addresses say. Build with
`HW=1` for Open Firmware, put the image on a Mac CD (Apple partition map +
HFS+), and boot it through Open Firmware's own loader:

```sh
HW=1 apps/myapp/build.sh                             # -> app-ibookg3-hw.elf
tools/make-boot-cd.sh apps/myapp/app-ibookg3-hw.elf boot.iso
./run-g3.sh -rtems-cd boot.iso                       # same path in QEMU
```

On the iBook: hold Cmd-Option-O-F at power on, then `boot cd:3,\rtems.elf`.
This path works with QEMU's OpenBIOS; Apple's Open Firmware has not been
tested.

## Emulator

`run-g3.sh` (QEMU `mac99`, `-cpu 750cx`, `MEM=128` default):
`-rtems app.exe`, `-rtems-cd boot.iso`, `-of` (Open Firmware prompt),
`-cdrom x.iso`, `-kernel x`, or no argument to boot `disk/g3.qcow2` (a
Mac OS or Linux disk image of your own; none is included).

![The Open Firmware prompt of the emulated iBook: "Welcome to OpenBIOS
v1.1" and the "0 >" prompt, black text on a pale yellow
background.](docs/screenshots/open-firmware.png)

## Layout

| Path | What |
|---|---|
| `patches/rtems/` | on RTEMS 6.2: the `ibookg3` BSP, the exception wrapper change, fixes backported from RTEMS `main` and the `dl06` change |
| `patches/rtems-libbsd/` | on `6-freebsd-14`: gem, ohci/usb for this BSP, gem reset fix |
| `patches/rtems-tools-tester/` | on rtems-tools `main`: the `ibookg3-qemu` configuration for `rtems-test` |
| `patches/rtems-tools/` | on rtems-tools `6` (the version RSB installs): the `rtems-ld` fix |
| `patches/rtems-source-builder/` | on RSB `6`: building on NixOS |
| `setup.sh` | clones the upstream repositories into `src/` and applies the patches |
| `build-toolchain.sh`, `rsb-shell.nix` | native toolchain build on NixOS into `rtems/` |
| `tools/rebuild-all.sh` | clean rebuild and install of RTEMS and rtems-libbsd |
| `tools/run-testsuite.py` | run RTEMS tests on the emulated iBook (`--icount`) |
| `tools/make-boot-cd.sh` | Mac-bootable CD image from an `HW=1` ELF |
| `tester/psim-device-tree-128m` | psim device tree with 128 MB, for `apps/rad750-check` |
| `results/` | test-suite results at 128 and 512 MB |
| `docs/screenshots/` | the screenshots in this file |
| `UPSTREAM-FINDINGS.md` | upstream bugs found or backported here (nothing reported upstream yet) |

## Test-suite status

Full RTEMS test suite on the emulated iBook (`tools/run-testsuite.py
--icount`), 677 tests:

| Result | 512 MB (`results/testsuite-512m.txt`) | 128 MB (`results/testsuite-128m.txt`) |
|---|---|---|
| Passed | 651 | 650 |
| Failed | 0 | 1 (`dl09`, which needs more than 128 MB) |
| Expected to fail | 22 | 22 |
| Benchmark | 3 | 3 |
| Unexpected pass | 1 (`psxfenv01`, expected to fail on every BSP) | 1 |
| Timeout | 0 | 0 |

Getting there took fixes outside the BSP; see `UPSTREAM-FINDINGS.md`:

- `spintrcritical24`, `spfatal31`, `spinternalerror02` and `psx09` pass with
  fixes RTEMS made after 6.2, backported with their authors.
- `dl06` passes with a fix to `rtems-ld` (`patches/rtems-tools/`,
  installed into `rtems/` by `build-toolchain.sh`) and a change to the test.

## Rebuild RTEMS after BSP changes

```sh
cd src/rtems
export PATH=$PWD/../../rtems/bin:$PATH
nix shell nixpkgs#python3 -c ./waf && nix shell nixpkgs#python3 -c ./waf install
```

Use `nix shell`, not `nix-shell`: `nix-shell` sets `CC=gcc`, which waf would
use instead of the cross compiler. `tools/rebuild-all.sh` does a clean
rebuild of RTEMS and rtems-libbsd.

## Rebuild rtems-libbsd after changes

```sh
cd src/rtems-libbsd
export PATH=$PWD/../../rtems/bin:$PATH
python3 ./waf build -j 8 && python3 ./waf install
```

Gotcha: the build tracks header dependencies with gccdeps, which ignores
`-isystem` include paths. Changing an installed BSP header (under
`rtems/powerpc-rtems6/ibookg3/lib/include`) does **not** trigger
recompiles, and neither `waf build -f` nor `touch` helps. To force a full
rebuild of the variant, delete its objects first:

```sh
find build/powerpc-rtems6-ibookg3-ibookg3 -name '*.o' -delete
```

## Not yet

- Running on a real iBook (see "Booting like the real iBook").
- PMU support: power off, battery, real-time clock, and the built-in
  keyboard and trackpad (an external USB keyboard works).
- Graphics beyond the text console; audio, modem, AirPort.
- DMA for the KeyLargo ATA controller (PIO only).

## License

The scripts, demo programs and documents here are under the BSD 2-Clause
license (`LICENSE`). Each patch in `patches/` is a change to its upstream
project and is under that project's license, as stated in the files it
touches; the backported RTEMS commits keep their original authors.
