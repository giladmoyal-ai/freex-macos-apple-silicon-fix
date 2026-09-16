#!/bin/bash
# Removes the architecture-independent FreeX filter and its PPD.
# FreeX's own driver is never touched by these scripts.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo:  sudo bash uninstall.sh" >&2; exit 1; }
removed=0
for p in /usr/libexec/cups/filter/rastertofreex-native \
         /Library/Printers/PPDs/Contents/Resources/FreeXNative.ppd; do
    [ -e "$p" ] && { rm -f "$p"; echo "Removed $p"; removed=1; }
done
[ "$removed" -eq 1 ] || echo "Nothing to remove."
echo
echo "Any queue using the (Native) driver will stop working; remove and re-add"
echo "it choosing the original 'FreeX WiFi Thermal Printer' driver."
