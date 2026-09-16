#!/bin/bash
#
# diagnose_freex_macos.sh
#
# Read-only diagnostic for printer drivers that fail on Apple Silicon Macs with
# "Filter failed" or "The printer software is not compatible with this device".
#
# Works for ANY printer, not just FreeX. It scans every installed CUPS filter and
# reports which ones are Intel-only (x86_64) binaries that cannot run on Apple
# Silicon without Rosetta 2.
#
# THIS SCRIPT IS READ-ONLY.
#   - It installs nothing.
#   - It modifies no printer, queue, or system setting.
#   - It does not enable CUPS debug logging.
#   - It only reads files and runs file/lpstat/sw_vers, then prints a report.
#
# Usage:
#   bash diagnose_freex_macos.sh           # standard report
#   bash diagnose_freex_macos.sh --log     # also show recent CUPS filter errors
#   bash diagnose_freex_macos.sh --all     # list every filter, not just problems
#   bash diagnose_freex_macos.sh --help
#
# Exit codes:
#   0  no architecture problem detected
#   1  problem found, or required driver files missing
#   2  bad usage
#
# Project: https://github.com/giladmoyal-AI/freex-macos-apple-silicon-fix
# License: MIT

set -u

FILTER_DIRS="/usr/libexec/cups/filter /Library/Printers"
PPD_DIR="/Library/Printers/PPDs/Contents/Resources"
CUPS_LOG="/var/log/cups/error_log"

SHOW_LOG=0
SHOW_ALL=0

for arg in "$@"; do
    case "$arg" in
        --log|-l) SHOW_LOG=1 ;;
        --all|-a) SHOW_ALL=1 ;;
        --help|-h)
            sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

# --- formatting (no external dependencies) ----------------------------------
if [ -t 1 ]; then
    BOLD=$'\033[1m'; RESET=$'\033[0m'
    RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'
else
    BOLD=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""
fi

header() { printf '\n%s== %s ==%s\n' "$BOLD" "$1" "$RESET"; }
ok()     { printf '  %s[ OK ]%s %s\n' "$GREEN"  "$RESET" "$1"; }
warn()   { printf '  %s[WARN]%s %s\n' "$YELLOW" "$RESET" "$1"; }
bad()    { printf '  %s[FAIL]%s %s\n' "$RED"    "$RESET" "$1"; }
info()   { printf '  %s[INFO]%s %s\n' "$BLUE"   "$RESET" "$1"; }
plain()  { printf '         %s\n' "$1"; }

printf '%s' "$BOLD"
printf 'Printer Driver Architecture Diagnostic for macOS (read-only)\n'
printf '%s' "$RESET"
printf 'https://github.com/giladmoyal-AI/freex-macos-apple-silicon-fix\n'

# --- 1. system --------------------------------------------------------------
header "System"

OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
OS_MAJOR="${OS_VERSION%%.*}"
ARCH="$(uname -m 2>/dev/null || echo 'unknown')"

info "macOS      : $OS_VERSION (build $(sw_vers -buildVersion 2>/dev/null || echo '?'))"
info "Architecture: $ARCH"

APPLE_SILICON=0
case "$ARCH" in
    arm64)
        APPLE_SILICON=1
        info "Chip       : $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Apple Silicon')"
        plain "Apple Silicon Mac - Intel-only drivers require Rosetta 2."
        ;;
    x86_64)
        plain "Intel Mac. The Rosetta issue this script looks for does not apply;"
        plain "Intel binaries run natively here. A printing failure has another cause."
        ;;
    *)  warn "Unrecognized architecture." ;;
esac

# --- 2. rosetta -------------------------------------------------------------
header "Rosetta 2"

ROSETTA_PRESENT=0
if [ "$APPLE_SILICON" -eq 1 ]; then
    # Two independent read-only signals: the translation daemon, and the support dir.
    ROSETTA_DAEMON=0; ROSETTA_DIR=0
    /usr/bin/pgrep -q oahd 2>/dev/null && ROSETTA_DAEMON=1
    [ -d /Library/Apple/usr/share/rosetta ] && ROSETTA_DIR=1

    if [ "$ROSETTA_DAEMON" -eq 1 ] || [ "$ROSETTA_DIR" -eq 1 ]; then
        ROSETTA_PRESENT=1
        ok "Rosetta 2 appears to be installed."
        [ "$ROSETTA_DAEMON" -eq 1 ] && plain "translation daemon 'oahd' is running"
        [ "$ROSETTA_DIR" -eq 1 ]    && plain "/Library/Apple/usr/share/rosetta exists"
    else
        bad "Rosetta 2 does NOT appear to be installed."
        plain "Intel-only programs - including vendor print filters - cannot run."
    fi

    # Rosetta 2 is fully supported only through macOS 27.
    if [ "$OS_MAJOR" -ge 28 ] 2>/dev/null; then
        warn "macOS $OS_MAJOR: Rosetta 2 no longer covers general-purpose Intel binaries."
        plain "Rosetta cannot rescue an Intel-only printer driver on this release."
        plain "Use the native replacement filter shipped with this project instead:"
        plain "  https://github.com/giladmoyal-AI/freex-macos-apple-silicon-fix/tree/main/native-filter"
        plain "It is a script, so it has no CPU architecture and needs no Rosetta."
    elif [ "$OS_MAJOR" -ge 26 ] 2>/dev/null; then
        info "Note: macOS 27 is the last release with full Rosetta 2 support."
        plain "From macOS 28, Intel-only printer drivers stop running. This project"
        plain "ships a native replacement filter that has no CPU architecture:"
        plain "  https://github.com/giladmoyal-AI/freex-macos-apple-silicon-fix/tree/main/native-filter"
    fi
else
    info "Not applicable on this architecture."
fi

# --- 3. CUPS filters --------------------------------------------------------
header "Installed CUPS print filters"

INTEL_ONLY_LIST=""
INTEL_ONLY_COUNT=0
FILTER_TOTAL=0

# Collect candidate filter binaries. -perm +111 keeps it to executables.
FILTER_FILES="$(find $FILTER_DIRS -type f -perm +111 2>/dev/null | sort)"

if [ -z "$FILTER_FILES" ]; then
    warn "No CUPS filters found in: $FILTER_DIRS"
    plain "No printer drivers appear to be installed."
else
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        FILE_OUT="$(file -b "$f" 2>/dev/null)"

        # Skip scripts and non-Mach-O files; only compiled binaries have this problem.
        case "$FILE_OUT" in
            *Mach-O*) ;;
            *) continue ;;
        esac

        FILTER_TOTAL=$((FILTER_TOTAL + 1))
        HAS_X86=0; HAS_ARM=0
        case "$FILE_OUT" in *x86_64*) HAS_X86=1 ;; esac
        case "$FILE_OUT" in *arm64*)  HAS_ARM=1 ;; esac

        if [ "$HAS_X86" -eq 1 ] && [ "$HAS_ARM" -eq 0 ]; then
            INTEL_ONLY_COUNT=$((INTEL_ONLY_COUNT + 1))
            INTEL_ONLY_LIST="${INTEL_ONLY_LIST}${f}"$'\n'
            bad "Intel-only : $f"
            plain "$FILE_OUT"
        elif [ "$SHOW_ALL" -eq 1 ]; then
            if [ "$HAS_ARM" -eq 1 ] && [ "$HAS_X86" -eq 1 ]; then
                ok "Universal  : $f"
            elif [ "$HAS_ARM" -eq 1 ]; then
                ok "Native arm64: $f"
            else
                info "Other      : $f"
                plain "$FILE_OUT"
            fi
        fi
    done <<< "$FILTER_FILES"

    if [ "$INTEL_ONLY_COUNT" -eq 0 ]; then
        ok "No Intel-only filters found (scanned $FILTER_TOTAL Mach-O filters)."
    else
        printf '\n'
        warn "$INTEL_ONLY_COUNT of $FILTER_TOTAL filters are Intel-only (x86_64, no arm64 slice)."
    fi
    [ "$SHOW_ALL" -eq 0 ] && [ "$FILTER_TOTAL" -gt 0 ] && \
        plain "(re-run with --all to list every filter)"
fi

# --- 4. PPDs and which filter they call -------------------------------------
header "Vendor printer descriptions (PPDs)"

if [ -d "$PPD_DIR" ]; then
    PPD_FILES="$(find "$PPD_DIR" -maxdepth 1 -type f \( -name '*.ppd' -o -name '*.ppd.gz' \) 2>/dev/null | sort)"
    if [ -n "$PPD_FILES" ]; then
        while IFS= read -r p; do
            [ -z "$p" ] && continue
            case "$p" in
                *.gz) FLINE="$(gunzip -c "$p" 2>/dev/null | grep -iE '^\*cupsFilter2?:' | head -3)" ;;
                *)    FLINE="$(grep -iE '^\*cupsFilter2?:' "$p" 2>/dev/null | head -3)" ;;
            esac
            [ -z "$FLINE" ] && continue
            ok "$(basename "$p")"
            printf '%s\n' "$FLINE" | sed 's/^/           /'
            case "$p" in
                *.gz) DSIZE="$(gunzip -c "$p" 2>/dev/null | grep -E '^\*DefaultPageSize:' | head -1 | awk '{print $2}')" ;;
                *)    DSIZE="$(grep -E '^\*DefaultPageSize:' "$p" 2>/dev/null | head -1 | awk '{print $2}')" ;;
            esac
            [ -n "$DSIZE" ] && plain "default page size: $DSIZE"
        done <<< "$PPD_FILES"
    else
        warn "No vendor PPDs installed in $PPD_DIR"
        plain "If your printer needs a vendor driver, it is not installed."
    fi
else
    warn "$PPD_DIR does not exist."
fi

# --- 5. printer queues ------------------------------------------------------
header "Configured printer queues"

if command -v lpstat >/dev/null 2>&1; then
    ALL_QUEUES="$(lpstat -v 2>/dev/null)"
    if [ -n "$ALL_QUEUES" ]; then
        while IFS= read -r q; do
            [ -z "$q" ] && continue
            QNAME="$(printf '%s' "$q" | sed -n 's/^device for \([^:]*\):.*/\1/p')"
            [ -z "$QNAME" ] && continue
            # Print the connection type only, not the full URI (it can contain a
            # hostname or IP the user may not want to paste into a bug report).
            SCHEME="$(printf '%s' "$q" | sed -n 's/^device for [^:]*: \([a-zA-Z0-9]*\):.*/\1/p')"
            ok "$QNAME  (connection: ${SCHEME:-unknown})"
            lpstat -p "$QNAME" 2>/dev/null | head -2 | sed 's/^/           /'
        done <<< "$ALL_QUEUES"
        plain ""
        plain "Device URIs are hidden on purpose - they can contain your printer's"
        plain "IP address. Run 'lpstat -v' yourself if you need them."
    else
        warn "No printer queues are configured on this Mac."
        plain "Add the printer in System Settings > Printers & Scanners, and set"
        plain "'Use' via 'Select Software...' to your printer's real driver -"
        plain "not Generic PostScript or Generic PCL."
    fi
else
    warn "lpstat not available; skipping queue check."
fi

# --- 6. optional CUPS log excerpt -------------------------------------------
if [ "$SHOW_LOG" -eq 1 ]; then
    header "Recent CUPS errors (filtered)"
    if [ -r "$CUPS_LOG" ]; then
        LOG_HITS="$(grep -iE 'Bad CPU type|badarch|Filter failed|execv of' "$CUPS_LOG" 2>/dev/null | tail -20)"
        if [ -n "$LOG_HITS" ]; then
            printf '%s\n' "$LOG_HITS" | sed 's/^/  /'
        else
            info "No matching errors currently in $CUPS_LOG."
            plain "To capture one: enable debug logging, reproduce the failure, read the log,"
            plain "then turn logging back off:"
            plain "  sudo cupsctl --debug-logging"
            plain "  sudo tail -n 100 $CUPS_LOG"
            plain "  sudo cupsctl --no-debug-logging"
        fi
    else
        info "$CUPS_LOG is not readable without elevated privileges."
        plain "Run: sudo grep -iE 'Bad CPU type|Filter failed' $CUPS_LOG | tail -20"
    fi
fi

# --- 7. verdict -------------------------------------------------------------
header "Diagnosis"

EXIT_CODE=0

if [ "$APPLE_SILICON" -eq 1 ] && [ "$INTEL_ONLY_COUNT" -gt 0 ] && [ "$ROSETTA_PRESENT" -eq 0 ]; then
    printf '  %s%sPROBLEM FOUND%s\n\n' "$BOLD" "$RED" "$RESET"
    plain "This printer driver uses an Intel-only CUPS filter. Rosetta 2 is required."
    plain ""
    plain "This Mac is Apple Silicon, $INTEL_ONLY_COUNT installed print filter(s) are Intel"
    plain "(x86_64) binaries, and Rosetta 2 is not installed - so CUPS cannot run"
    plain "them. That is what produces 'Filter failed' and 'The printer software"
    plain "is not compatible with this device'."
    plain ""
    printf '  %sRecommended next step - run this yourself:%s\n\n' "$BOLD" "$RESET"
    printf '      softwareupdate --install-rosetta\n\n'
    plain "Accept the licence when prompted. This script installs nothing for you."
    plain ""
    plain "Then verify, using one of the filters listed above, e.g.:"
    plain ""
    FIRST_FILTER="$(printf '%s' "$INTEL_ONLY_LIST" | head -1)"
    plain "      arch -x86_64 $FIRST_FILTER"
    plain ""
    plain "Expected: the filter's own usage message, e.g."
    plain "          'ERROR: rastertoepson job-id user title copies options [file]'"
    plain "          which means it launched successfully."
    plain "NOT:      'Bad CPU type in executable'"
    plain ""
    plain "Finally: remove and re-add the printer queue, then print a test page."
    EXIT_CODE=1

elif [ "$APPLE_SILICON" -eq 1 ] && [ "$INTEL_ONLY_COUNT" -gt 0 ] && [ "$ROSETTA_PRESENT" -eq 1 ]; then
    printf '  %s%sROSETTA REQUIREMENT SATISFIED%s\n\n' "$BOLD" "$GREEN" "$RESET"
    plain "$INTEL_ONLY_COUNT installed filter(s) are Intel-only, but Rosetta 2 is present,"
    plain "so CUPS should be able to run them."
    plain ""
    plain "If printing still fails, check in this order:"
    plain "  1. The queue was created BEFORE Rosetta was installed - remove the"
    plain "     printer in System Settings > Printers & Scanners and add it again."
    plain "  2. The queue is paused - open it and choose Resume."
    plain "  3. The queue uses a generic driver - it must use the real vendor"
    plain "     driver via 'Use > Select Software...'."
    plain "  4. For network printers, confirm reachability:"
    plain "       nc -vz YOUR_PRINTER_IP 9100"
    plain "  5. Re-run this script with --log to see recent CUPS errors."
    plain ""
    plain "Plan ahead: these drivers stop working from macOS 28. Either ask your"
    plain "vendor for a native arm64 driver, or install the script-based filter"
    plain "from this project, which has no CPU architecture at all:"
    plain "  https://github.com/giladmoyal-AI/freex-macos-apple-silicon-fix/tree/main/native-filter"

elif [ "$APPLE_SILICON" -eq 1 ] && [ "$INTEL_ONLY_COUNT" -eq 0 ] && [ "$FILTER_TOTAL" -eq 0 ]; then
    printf '  %s%sNO VENDOR DRIVER DETECTED%s\n\n' "$BOLD" "$YELLOW" "$RESET"
    plain "No compiled CUPS filters were found, so no vendor printer driver appears"
    plain "to be installed. Install your printer's official macOS driver, then run"
    plain "this script again."
    EXIT_CODE=1

else
    printf '  %s%sNO ARCHITECTURE PROBLEM DETECTED%s\n\n' "$BOLD" "$GREEN" "$RESET"
    plain "Every compiled print filter on this Mac can run on this CPU, so the"
    plain "Intel-filter / missing-Rosetta problem does not apply here."
    plain ""
    plain "If printing still fails, the cause is something else - see"
    plain "docs/troubleshooting.md in the project linked above."
fi

printf '\n'
plain "This script made no changes to your system."
printf '\n'

exit "$EXIT_CODE"
