#!/bin/bash
#
# Restores FreeX's original rastertoFreeX binary.
#
# An earlier version of install.sh used the filename "rastertofreex", which on
# a case-insensitive filesystem is the SAME FILE as FreeX's "rastertoFreeX" -
# so installing it overwrote the vendor driver. This puts the original back,
# extracted from FreeX's own installer package.
#
# Usage:  sudo bash repair-vendor-driver.sh /path/to/"FreeX Driver for MacOS v1.3.pkg"
#
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo." >&2; exit 1; }
PKG="${1:-}"
[ -f "$PKG" ] || { echo "Usage: sudo bash repair-vendor-driver.sh <FreeX Driver .pkg>" >&2; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pkgutil --expand-full "$PKG" "$TMP/x" >/dev/null
SRC="$(find "$TMP/x" -name 'rastertoFreeX' -type f | head -1)"
[ -n "$SRC" ] || { echo "rastertoFreeX not found inside that package." >&2; exit 1; }

echo "Found original: $(file -b "$SRC")"
install -o root -g wheel -m 755 "$SRC" /usr/libexec/cups/filter/rastertoFreeX
echo "Restored /usr/libexec/cups/filter/rastertoFreeX"
file -b /usr/libexec/cups/filter/rastertoFreeX
echo
echo "Your original FreeX queues should work again (Rosetta 2 is already installed)."
