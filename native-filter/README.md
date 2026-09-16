# Native (architecture-independent) FreeX CUPS filter

> **Status: working, but young.** Verified end to end on a FreeX WiFi Thermal
> Printer over **both USB and Wi-Fi**, printing real USPS shipping labels whose
> barcodes scan correctly. It has not yet been tested on other models or
> firmware revisions. The vendor driver plus Rosetta 2 remains the
> better-travelled path until macOS 28 — see the [main guide](../README.md).

## What this is

A drop-in replacement for FreeX's `rastertoFreeX`, written as a **Python
script** instead of a compiled binary.

That one change is the whole point. A script has **no CPU architecture**, so it
can never fail with `Bad CPU type in executable`. It runs on Intel, on Apple
Silicon, and on whatever Apple ships next — with no rebuild, and **no Rosetta**.

Which matters because **macOS 27 is the last release with full Rosetta 2**. From
macOS 28 the vendor's Intel driver cannot run at all, and no amount of
troubleshooting will bring it back.

## How it works

CUPS hands a filter a rasterised page and expects printer-native commands back:

```
App → PDF → CUPS → 8-bit greyscale raster → rastertofreex → TSPL → printer
```

The TSPL command set was recovered from strings inside the vendor's own binary,
so this speaks exactly the dialect the printer already understands:

```
SIZE 101.6 mm,152.4 mm
GAP 3.0 mm,0 mm
DENSITY 8
DIRECTION 1
CLS
BITMAP 0,0,102,1218,1,<124236 bytes of packed 1-bit raster>
PRINT 1,1
```

In mode 1 a set bit is **white** and a clear bit is **black**, which is what the
vendor driver does. The FreeX PPD asks CUPS for 8-bit greyscale, so this filter
also does the halftoning — by default a straight threshold, which keeps barcodes
crisp. Floyd–Steinberg dithering is available for photos.

## Install

```bash
sudo bash install.sh
```

Then add the printer and pick **“FreeX WiFi Thermal Printer (Native)”** under
**Use → Select Software…** — note the `(Native)` suffix.

Your existing FreeX driver is **not** touched. Both drivers stay installed side
by side, so switching back is just re-adding the printer with the original one.

```bash
sudo bash uninstall.sh      # to remove
```

## Options

Set with `lpoptions` or `lp -o`:

| Option | Default | What it does |
| --- | --- | --- |
| `freex-threshold=N` | `128` | Black/white cutoff, 0–255. Lower = darker. |
| `freex-dither=true` | off | Floyd–Steinberg. Better for photos, **worse for barcodes**. |
| `freex-density=N` | `8` | Print darkness 0–15 (`DENSITY`). |
| `freex-gap-mm=N` | `3.0` | Gap between labels for the media sensor. |
| `freex-band-rows=N` | `0` | Split the page into N-row `BITMAP` blocks. `0` sends one block, like the vendor driver. Try `32` only if large labels truncate. |

Example:

```bash
lpoptions -p YOUR_QUEUE_NAME -o freex-threshold=110 -o freex-density=10
```

## What has and hasn't been verified

**Verified on hardware** (FreeX WiFi Thermal Printer, MacBook Air M4, macOS 27.0):

- Full 4x6 labels over **USB** — complete page, nothing truncated
- Full 4x6 labels over **Wi-Fi** (raw TCP 9100) — complete page
- Real USPS Ground Advantage labels, **barcodes scan correctly**
- Thin barcode bars, text and solid blocks all render cleanly

**Verified in software:**

- CUPS raster v1/v2/v3, both byte orders, RLE and uncompressed
- Round-trip on an 812x1218 label raster: **0 of 989,016 pixels differ**
- `BITMAP` payload length matches its declared geometry exactly
- Multi-page jobs, copies, and banding

**Also observed in continued use:**

Over a run of subsequent network problems — a DHCP lease moving, and a second DHCP server on the LAN
handing the printer an address on the wrong subnet — **the filter itself never failed**. Every
failure was at the network layer, surfacing as "the printer may not exist or is unavailable", and
printing resumed the moment the printer was reachable again. The USB queue kept working throughout.

**Not yet verified:**

- Other printer models and firmware revisions
- Long-run reliability over weeks of daily use

### About the port 9100 truncation

An earlier attempt to drive this printer directly over port 9100 — opening a
socket and writing the raster by hand — printed only the first 30-40% of each
label, and neither banding nor pacing fixed it.

This filter sends **the same bytes over the same port** and prints the full page.
The difference is that CUPS's own socket backend performs the transfer, with
real flow control, instead of an ad-hoc `sendall` loop. The printer was never
the limitation.

## Requirements

macOS with `/usr/bin/python3` (present once the Xcode Command Line Tools are
installed: `xcode-select --install`). No third-party Python packages.

## Reporting results

Please report success or failure in
[Discussions](https://github.com/giladmoyal-ai/freex-macos-apple-silicon-fix/discussions)
— include your printer model, macOS version, and whether banding was needed.
**Redact private data first**: no network names, local IP addresses, serial
numbers, or shipping labels.
