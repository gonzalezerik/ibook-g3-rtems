# Dev shell for building RTEMS tools with the RTEMS Source Builder on NixOS.
#   nix-shell ../../rsb-shell.nix --run '../source-builder/sb-set-builder ...'
{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  # GCC's own sources (libcpp) trip the cc-wrapper's -Werror=format-security
  hardeningDisable = [ "all" ];
  packages = with pkgs; [
    gcc binutils-unwrapped gnumake gnutar gzip bzip2 xz zstd unzip cpio patch
    git curl wget pkg-config
    (python3.withPackages (ps: [ ps.distro ps.pyparsing ]))
    bison flex texinfo perl gawk gnused gnugrep diffutils findutils coreutils
    file which util-linux autoconf automake libtool dtc
  ];
}
