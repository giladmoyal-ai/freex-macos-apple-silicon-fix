# Technical Notes: CUPS Filters, Architecture Mismatches, and TSPL

How this problem was diagnosed, and what was learned about the macOS print path along the way.

The worked example is FreeX, but everything here generalises to **any** vendor driver that ships an
Intel-only CUPS filter — see [other-printers.md](other-printers.md).

**None of this is required to fix the problem.** The fix is in the [README](../README.md):
install Rosetta 2. This document is for people who want to understand *why*, or who are debugging a
similar vendor-driver failure on Apple Silicon.

---

## How macOS printing actually works here

macOS printing runs on **CUPS**. A print job moves through a chain:

```
Application
   ↓  (PDF)
CUPS scheduler (cupsd)
   ↓
Rasterizer  →  CUPS raster format (application/vnd.cups-raster)
   ↓
Vendor filter  ←  this is where FreeX plugs in
   ↓  (printer-native commands)
Backend (usb:// or socket://)
   ↓
Printer
```

The **PPD** (PostScript Printer Description) file describes the printer's capabilities and, crucially,
names the filter program to invoke:

```
/Library/Printers/PPDs/Contents/Resources/FreeX.ppd.gz
```

```bash
gunzip -c /Library/Printers/PPDs/Contents/Resources/FreeX.ppd.gz | grep -iE 'cupsFilter|cupsFilter2'
```

```
*cupsFilter: "application/vnd.cups-raster 0 rastertoFreeX"
```

Read as: *"give me CUPS raster data, cost 0, and run `rastertoFreeX` to convert it."*

CUPS resolves that name against its filter directory:

```bash
find /Library /usr/libexec -type f -name 'rastertoFreeX' 2>/dev/null \
  -exec ls -l {} \; -exec file {} \;
```

```
-rwxr-xr-x  1 root  wheel  ...  /usr/libexec/cups/filter/rastertoFreeX
/usr/libexec/cups/filter/rastertoFreeX: Mach-O 64-bit executable x86_64
```

**`Mach-O 64-bit executable x86_64`** — a single-architecture Intel binary. Not a universal binary,
no `arm64` slice. Built in 2021, before the vendor updated for Apple Silicon.

---

## The failure, at the kernel level

On an Apple Silicon Mac without Rosetta 2, `execv()` on an Intel binary fails outright. CUPS reports
it verbatim:

```bash
sudo cupsctl --debug-logging
# reproduce the print
sudo tail -n 100 /var/log/cups/error_log
```

```
execv of /usr/libexec/cups/filter/rastertoFreeX failed. err:86, Bad CPU type in executable
STATE: +com.apple.badarch-error
PID 12345 (/usr/libexec/cups/filter/rastertoFreeX) stopped with status 186 (Bad CPU type in executable)
```

Three useful details:

- **`err:86`** is `ENOEXEC`-adjacent — macOS's `EBADARCH`, "bad CPU type in executable."
- **`com.apple.badarch-error`** is the system-wide state flag macOS raises for architecture
  mismatches. Seeing it in *any* log means "wrong CPU architecture," not "corrupt file."
- **status 186** is the exit status CUPS records for the failed filter.

Remember to turn debug logging off afterwards:

```bash
sudo cupsctl --no-debug-logging
```

### Why the error message users see is so unhelpful

CUPS knows only that the filter failed, so the queue shows **"Filter failed."** The Printers &
Scanners UI generalises further to **"The printer software is not compatible with this device."**
That phrasing strongly implies "wrong driver for this printer model," which sends people off
reinstalling drivers and buying cables. The real meaning is narrower and more literal than it
sounds: the *software* (an Intel binary) is genuinely not compatible with *this device* (an Apple
Silicon Mac).

### Why Rosetta wasn't already installed

Rosetta 2 is not preinstalled on Apple Silicon Macs. macOS offers to install it the first time you
launch an Intel **app** — a GUI prompt.

A CUPS filter is not launched by the user. It is spawned by `cupsd`, a background daemon, with no
session to show a prompt in. So the on-demand install never triggers, and the failure is silent
apart from a log line. On a Mac that has never run any Intel software, the FreeX driver fails from
the moment it is installed, with no path to discovering why.

This is the general shape of the bug, and it will hit any vendor driver that still ships an
Intel-only CUPS filter.

---

## Verifying the fix

After `softwareupdate --install-rosetta`:

```bash
arch -x86_64 /usr/libexec/cups/filter/rastertoFreeX
```

```
ERROR: rastertoepson job-id user title copies options [file]
```

That is a CUPS filter's standard usage message — every filter takes
`job-id user title copies options [file]`. Getting it means the binary **executed**. The word
`rastertoepson` is a fingerprint: FreeX built their filter starting from the open-source
`rastertoepson` filter (from the Gutenprint/ESC-P-R lineage) and never changed the usage string.

Note what this test does and does not prove:

- ✅ Rosetta 2 can execute the filter.
- ❌ It does not prove the filter produces correct output, or that the printer will print.

For that, print an actual label.

---

## What the filter emits: TSC/TSPL commands

Running `strings` over the filter shows the printer language it targets:

```bash
strings /usr/libexec/cups/filter/rastertoFreeX \
  | grep -iE 'BITMAP|SIZE|GAP|DENSITY|CLS|PRINT|BARCODE|TSPL|TSC|ZPL|DOWNLOAD|PUTBMP|GW|~DG|\^XA' \
  | head -100
```

Representative results:

```
/var/log/cups/rp421_TSCs.log
SIZE 2.000,4.000
GAP 0.120,0.000
DENSITY 7
BITMAP 0,0,%d,%d,1,
PRINT 1,1
SIZE %dmm,%dmm
DENSITY %d
BITMAP %d,%d,%d,%d,1,
PRINT 1,%d
```

These are **TSPL / TSPL2** commands — the label language used by TSC printers and by many rebadged
thermal label printers:

| Command | Meaning |
| --- | --- |
| `SIZE w,h` | label dimensions (inches or mm) |
| `GAP m,n` | gap between labels, for the media sensor |
| `DENSITY n` | print darkness, typically 0–15 |
| `CLS` | clear the image buffer |
| `BITMAP x,y,width,height,mode,data` | drop a 1-bit raster block at a position |
| `PRINT sets,copies` | print the buffer |

The `%d` format specifiers show these are `printf`-style templates filled in at runtime from the
page geometry and driver options. The literal `SIZE 2.000,4.000` / `GAP 0.120,0.000` / `DENSITY 7`
values are compiled-in defaults.

The `rp421_TSCs.log` path suggests the codebase originated with an "RP421"-class TSC-compatible
printer — more evidence that FreeX's driver is a rebadge of a generic TSPL driver.

**So the full pipeline is:** app → PDF → CUPS raster → `rastertoFreeX` converts raster rows into
`BITMAP` blocks → TSPL command stream → USB or TCP 9100 → printer.

---

## Experimental: talking to port 9100 directly

> ⚠️ **Experimental. Not a recommended solution. Not needed.**
> This was explored *before* the Rosetta cause was found, as a possible way to bypass the broken
> filter entirely. Once Rosetta 2 was installed, the official driver worked normally and this
> approach became unnecessary. It is recorded here only because it is interesting, and because it
> may help someone debugging a printer whose vendor driver is truly unavailable.

Because the printer listens on raw TCP 9100 and speaks TSPL, you can send commands to it directly —
no driver, no CUPS, no filter. A minimal example:

```bash
# Illustrative only. Replace with your own printer's IP.
printf 'SIZE 4,6\r\nGAP 0.12,0\r\nDENSITY 7\r\nCLS\r\nTEXT 30,30,"3",0,1,1,"HELLO"\r\nPRINT 1,1\r\n' \
  | nc 192.168.1.100 9100
```

**What worked:** the printer accepted TSPL over port 9100 and rendered simple content, including
small `BITMAP` payloads. That confirmed the transport and the command language.

**What did not work:** reliably reproducing a full 4x6 shipping label. Getting there means
replicating what `rastertoFreeX` already does — rasterizing a PDF at the right DPI, converting to
packed 1-bit-per-pixel rows with correct byte alignment and bit order, chunking into `BITMAP` blocks
with correct coordinates and widths, and handling the printer's buffer limits. Each of those is a
place to get subtly wrong output, and the results were inconsistent.

**Conclusion:** reverse-engineering the raster path was the wrong problem. The vendor filter already
does all of this correctly — it just could not start. One `softwareupdate --install-rosetta` solved
what a raster reimplementation would not have.

If you do experiment, remember: sending malformed data to a thermal printer can leave it in a
confused state (power-cycle it), and thermal print heads wear with use. Do not send firmware.

---

## Why this fix is temporary

Rosetta 2 is being retired, which puts a hard deadline on every Intel-only printer driver.

- **macOS 27** is the last release with full Rosetta 2 support.
- From **macOS 28**, Rosetta is narrowed to legacy gaming frameworks. General-purpose Intel
  binaries — including CUPS filters and vendor utilities — no longer run.
- macOS 26.4 and later already warn when an Intel-only application is launched.

There is no workaround on the Rosetta side: once translation is gone, an `x86_64`-only filter simply
cannot execute. The options become a native `arm64` build from the vendor, a generic driver for the
printer's command language, driverless printing (AirPrint / IPP Everywhere), or talking to the
printer directly on port 9100.

Ironically, the direct-to-9100 experiment described above — dismissed as unnecessary once Rosetta
solved the problem — is one of the few approaches that will still work on macOS 28. A small
user-space program that rasterizes a PDF and emits TSPL needs no vendor filter and no Rosetta.

One detail worth noting: macOS ships its own `rastertoepson` filter as a **universal binary**, while
the FreeX filter derived from it is Intel-only. The upstream code was never the constraint; only the
vendor's build was.

---

## Takeaways for similar problems

If a printer, scanner, or other peripheral fails on Apple Silicon with a vague
"software is not compatible" message:

1. **Find the vendor's filter or plugin binary** and run `file` on it. Look for `x86_64` with no
   `arm64`.
2. **Check whether Rosetta 2 is installed** — daemon-launched binaries never trigger the install
   prompt.
   ```bash
   /usr/bin/pgrep -q oahd && echo installed || echo missing
   ```
3. **Read the real log**, not the UI message. `sudo cupsctl --debug-logging` plus
   `/var/log/cups/error_log` turns a useless dialog into an exact kernel error.
4. **`com.apple.badarch-error` anywhere in any log** means architecture mismatch. Nothing else.
5. **Recreate the device/queue after fixing it** — state cached during the broken period tends to
   persist.

---

## References

- CUPS filter and backend interface: <https://www.cups.org/doc/man-filter.html>
- Apple, *If you need to install Rosetta on your Mac*: <https://support.apple.com/en-us/102527>
- Rosetta 2 end-of-life: macOS 27 is the last release with full support; from macOS 28 it is
  limited to legacy game frameworks (announced by Apple; widely reported June 2026)
- TSPL/TSPL2 programming language (TSC Auto ID) — published by TSC for their label printers
- `man arch`, `man cupsctl`, `man lpoptions`, `man lpstat` on macOS
