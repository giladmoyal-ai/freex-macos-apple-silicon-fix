#!/bin/bash
#
# Installs the architecture-independent FreeX CUPS filter.
#
# Safety notes learned the hard way:
#
#  * macOS APFS is case-INSENSITIVE by default, so a filter named
#    "rastertofreex" is the SAME FILE as FreeX's "rastertoFreeX" and would
#    silently destroy the vendor driver. This installs "rastertofreex-native",
#    and refuses to run if any case variant of the target already exists.
#
#  * /usr/bin/python3 is a shim that asks xcode-select where the real Python
#    lives. CUPS runs filters in a sandbox that cannot read
#    /var/select/developer_dir, so the shim fails with "Operation not
#    permitted". This bakes an absolute interpreter path into the shebang.
#
# Usage:  sudo bash install.sh
#
set -euo pipefail

FILTER_NAME="rastertofreex-native"
FILTER_DIR="/usr/libexec/cups/filter"
PPD_DIR="/Library/Printers/PPDs/Contents/Resources"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$(uname -s)" = "Darwin" ] || { echo "macOS only." >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo:  sudo bash install.sh" >&2; exit 1; }
for f in "$FILTER_NAME" FreeXNative.ppd; do
    [ -f "$HERE/$f" ] || { echo "Missing $f next to this script." >&2; exit 1; }
done

# --- refuse to clobber anything that differs only by case -------------------
existing="$(ls "$FILTER_DIR" | grep -ix "$FILTER_NAME" || true)"
if [ -n "$existing" ] && [ "$existing" != "$FILTER_NAME" ]; then
    echo "Refusing to install: '$FILTER_DIR/$existing' already exists and this" >&2
    echo "filesystem is case-insensitive, so writing '$FILTER_NAME' would" >&2
    echo "overwrite it. Rename this filter and try again." >&2
    exit 1
fi

# --- find a real Python, not the xcode-select shim --------------------------
PYTHON=""
for cand in /Library/Developer/CommandLineTools/usr/bin/python3 \
            /opt/homebrew/bin/python3 \
            /usr/local/bin/python3; do
    if [ -x "$cand" ] && "$cand" -c 'import sys' >/dev/null 2>&1; then
        PYTHON="$cand"; break
    fi
done
if [ -z "$PYTHON" ] && XR="$(xcrun -f python3 2>/dev/null)" && [ -x "$XR" ]; then
    PYTHON="$XR"
fi
if [ -z "$PYTHON" ]; then
    echo "No usable python3 found." >&2
    echo "Install the Command Line Tools, then re-run:" >&2
    echo "    xcode-select --install" >&2
    exit 1
fi
# Resolve symlinks so the shebang points at a real binary.
PYTHON="$(cd "$(dirname "$PYTHON")" && pwd -P)/$(basename "$PYTHON")"
while [ -L "$PYTHON" ]; do
    PYTHON="$(cd "$(dirname "$PYTHON")" && pwd -P)/$(readlink "$PYTHON")"
    PYTHON="$(cd "$(dirname "$PYTHON")" && pwd -P)/$(basename "$PYTHON")"
done
echo "Using interpreter: $PYTHON"

# --- install with the shebang rewritten -------------------------------------
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
{
    printf '#!%s\n' "$PYTHON"
    tail -n +2 "$HERE/$FILTER_NAME"
} > "$TMP"
"$PYTHON" -c "import py_compile,sys; py_compile.compile(sys.argv[1], doraise=True)" "$TMP"

echo "Installing filter -> $FILTER_DIR/$FILTER_NAME"
install -o root -g wheel -m 755 "$TMP" "$FILTER_DIR/$FILTER_NAME"

echo "Installing PPD    -> $PPD_DIR/FreeXNative.ppd"
install -d -o root -g wheel -m 755 "$PPD_DIR"
install -o root -g wheel -m 644 "$HERE/FreeXNative.ppd" "$PPD_DIR/FreeXNative.ppd"

echo
echo "Installed. FreeX's own driver was NOT touched."
echo
echo "  1. System Settings > Printers & Scanners > Add Printer..."
echo "  2. Select your FreeX (USB tab, or IP tab with HP Jetdirect - Socket)"
echo "  3. Use > Select Software... > 'FreeX WiFi Thermal Printer (Native)'"
echo "  4. Add, then print a test label."
echo
echo "To remove:  sudo bash uninstall.sh"
