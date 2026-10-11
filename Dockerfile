# syntax=docker/dockerfile:1
#
# iBook G3 / RTEMS workbench in a container: the RTEMS 6 PowerPC toolchain,
# the ibookg3 and psim BSPs, rtems-libbsd and QEMU, built from the pinned
# upstream sources plus patches/. Runs anywhere Docker does (Linux, and
# Windows and macOS through Docker Desktop), on x86-64 and ARM64 hosts;
# QEMU emulates the iBook in software, so no KVM or other device is needed.
#
#   docker build -t ibook-g3-rtems .                     # takes about an hour
#   docker run --rm -it ibook-g3-rtems bash -c "apps/starter/build.sh && apps/starter/run.sh"
#   docker build --target testsuite -t ibook-g3-rtems:testsuite .

ARG DEBIAN=debian:trixie-slim

# --- build the toolchain, RTEMS and rtems-libbsd -----------------------------
FROM ${DEBIAN} AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential bison flex texinfo pax unzip bzip2 xz-utils zstd \
      python3 python3-dev python-is-python3 libncurses-dev zlib1g-dev \
      libexpat1-dev git ca-certificates curl pkg-config file \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /ibook
COPY setup.sh ./
COPY patches patches
COPY tools/rtems-config.ini tools/
RUN ./setup.sh
COPY build-toolchain.sh ./
RUN ./build-toolchain.sh \
    && rm -rf src/rsb/rtems/build src/rsb/rtems/sources src/rsb/rtems/patches \
              rtems/share/doc rtems/share/info rtems/share/man
COPY tools tools
RUN tools/rebuild-all.sh

# --- the workbench: toolchain, BSPs, QEMU, scripts and demos ---------------
FROM ${DEBIAN} AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
      qemu-system-ppc seabios ipxe-qemu qemu-utils python3 libpython3-dev libncurses6 libexpat1 \
      pkg-config mtools dosfstools fdisk xorriso procps \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /ibook
COPY --from=build /ibook/rtems rtems
# psim's device tree, from the rtems-tools clone (apps/starter BSP=psim)
COPY --from=build /ibook/src/rtems-tools/tester/rtems/testing/bsps/psim-device-tree \
     src/rtems-tools/tester/rtems/testing/bsps/
COPY . .
# writable for any user, so `docker run --user` can build and run the apps
RUN chmod -R a+rwX /ibook/apps && chmod a+rwX /ibook
ENV PATH=/ibook/rtems/bin:$PATH \
    AUDIO=none \
    DISPLAY_OPT=vnc=0.0.0.0:0
# VNC, for the graphical mode of run-g3.sh (guest OS images)
EXPOSE 5900
CMD ["bash"]

# --- the runtime plus the built RTEMS test suite (about 1.6 GB more) ---------
FROM runtime AS testsuite
COPY --from=build /ibook/src/rtems/build/powerpc/ibookg3/testsuites \
     /ibook/build/powerpc/ibookg3/testsuites

FROM runtime
