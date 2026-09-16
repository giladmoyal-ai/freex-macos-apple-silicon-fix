# Other Printers and Brands

This guide started with a FreeX thermal label printer, but the failure has nothing to do with FreeX
specifically. **Any** printer whose macOS driver ships an Intel-only CUPS filter fails the same way
on Apple Silicon, with the same two error messages:

- "The printer software is not compatible with this device."
- "Filter failed"

This page covers how to identify and fix it for **any** printer.

---

## The general problem

macOS printing runs on CUPS. Each vendor driver installs:

1. a **PPD** file describing the printer, in `/Library/Printers/PPDs/Contents/Resources/`, and
2. a **filter** — a compiled program in `/usr/libexec/cups/filter/` that converts page images into
   the printer's own language.

If that filter was compiled for Intel only and never rebuilt for Apple Silicon, macOS cannot execute
it, and every print job fails at the filter stage.

The vendor name on the box is irrelevant. What matters is one thing: **was the driver rebuilt as a
universal or arm64 binary?** Many were not, particularly:

- Budget **thermal label printers** (4x6 shipping label printers) sold online
- **Receipt and POS printers** using ESC/POS
- Older **wide-format, badge, card, and barcode** printers
- Any printer whose Mac driver page still lists "macOS 10.14 / 10.15" as the newest supported version
- Any driver last updated **before roughly 2020** (Apple Silicon shipped in November 2020)

Low-cost thermal label printers are especially prone to this because many are rebadges of the same
underlying hardware sold under dozens of brand names, with a driver each reseller maintains rarely or
not at all.

**Don't guess from the brand.** Check your actual installed files — it takes ten seconds.

---

## Check any printer in 10 seconds

```bash
uname -m
file /usr/libexec/cups/filter/* 2>/dev/null | grep -i x86_64 | grep -vi arm64
```

- First command prints **`arm64`** → you're on Apple Silicon.
- Second command prints **any filter** → that filter is Intel-only and needs Rosetta 2.

Or run the full report, which does this for every filter and explains what it finds:

```bash
bash scripts/diagnose_freex_macos.sh --all
```

Despite the filename, the script is **vendor-neutral** — it scans every installed filter, not just
FreeX's.

---

## Reading the output of `file`

| What `file` prints | Meaning |
| --- | --- |
| `Mach-O 64-bit executable x86_64` | **Intel only.** Needs Rosetta 2. This is the problem. |
| `Mach-O 64-bit executable arm64` | Native Apple Silicon. Fine. |
| `Mach-O universal binary with 2 architectures ... x86_64 ... arm64` | Universal. Fine. |
| `Bourne-Again shell script` / `Perl script` | A script, not a compiled binary. Architecture doesn't apply. |

Only the first row is broken.

---

## Finding your printer's filter

If you don't know which filter belongs to your printer, ask its PPD:

```bash
# List installed vendor PPDs
ls /Library/Printers/PPDs/Contents/Resources/

# See which filter a specific PPD calls for (.gz and plain both shown)
gunzip -c /Library/Printers/PPDs/Contents/Resources/YOUR_PRINTER.ppd.gz | grep -i cupsFilter
grep -i cupsFilter /Library/Printers/PPDs/Contents/Resources/YOUR_PRINTER.ppd
```

You'll get a line like:

```
*cupsFilter: "application/vnd.cups-raster 0 rastertoSOMETHING"
```

The last word is the filter name. Then:

```bash
find /Library /usr/libexec -type f -name 'rastertoSOMETHING' 2>/dev/null \
  -exec ls -l {} \; -exec file {} \;
```

Some drivers also install filters under `/Library/Printers/<Vendor>/`, which the diagnostic script
searches too.

---

## The fix (same for every brand)

```bash
softwareupdate --install-rosetta
```

Then remove and re-add the printer in System Settings → Printers & Scanners, making sure **Use →
Select Software…** picks the real vendor driver rather than a generic one.

Verify the filter can now launch (substitute your filter's path):

```bash
arch -x86_64 /usr/libexec/cups/filter/rastertoSOMETHING
```

A **usage message** means success. `Bad CPU type in executable` means Rosetta didn't install.

Most filters respond with something like:

```
ERROR: rastertoSOMETHING job-id user title copies options [file]
```

Some print nothing and exit — that's also fine, as long as you don't see `Bad CPU type`.

---

## If there is no working driver at all

Rosetta 2 only helps while the vendor's Intel driver exists and you're on macOS 27 or earlier. If
the vendor is gone, never shipped a Mac driver, or you're on macOS 28+, consider these in order.

### 1. Ask the vendor for a native arm64 driver

Worth doing even if you expect nothing. Vendor pressure is the only reliable way these get rebuilt,
and the request is concrete: *"Please provide a universal or arm64 build of your CUPS filter — the
current one is x86_64 only and will stop working on macOS 28."*

### 2. Try a generic driver for the printer's language

Many thermal printers speak a standard language. If yours does, a generic driver may work with no
vendor software at all:

| Language | Common in | Generic driver option |
| --- | --- | --- |
| **TSPL / TSPL2** | TSC and TSC-compatible label printers (including many rebadges) | A TSC-compatible driver, or raw port 9100 |
| **ZPL / ZPL II** | Zebra and Zebra-compatible label printers | Zebra's own macOS drivers, or generic ZPL |
| **EPL** | Older Zebra/Eltron label printers | Generic EPL |
| **ESC/POS** | Receipt and POS printers | Generic ESC/POS, or raw port 9100 |
| **PostScript / PCL** | Office laser printers | macOS's built-in Generic PostScript / PCL |
| **IPP Everywhere / AirPrint** | Modern network printers | **No driver needed** — macOS handles it natively |

To find out which language yours speaks, check the manual, or look at the strings inside the vendor
filter — see [technical-notes.md](technical-notes.md) for a worked example.

> **Generic PostScript and Generic PCL do not work for thermal label printers.** They're a common
> accidental choice in the Add Printer dialog and produce "Filter failed" or pages of garbage.

### 3. Print directly to port 9100

Most network thermal printers accept raw commands on TCP port 9100 with no driver involved. This is
powerful but low-level — you become responsible for rasterizing and formatting. See the
**experimental** section of [technical-notes.md](technical-notes.md).

### 4. Check for AirPrint / IPP Everywhere

Some network printers support driverless printing even when the vendor also ships a driver. If macOS
offers your printer with **"Use: AirPrint"** or **"Secure AirPrint"** in the Add Printer dialog,
select that — it bypasses vendor filters entirely and will keep working after macOS 28.

### 5. Print from another machine

An Intel Mac, a Linux box, a Raspberry Pi, or a Windows PC can host the printer and share it on the
network. CUPS on Linux often has community drivers for exactly these printers.

---

## Planning for macOS 28

macOS 27 is the last release with full Rosetta 2. From macOS 28, Intel-only drivers stop working and
Rosetta cannot rescue them.

**Before upgrading**, run the diagnostic script. If it still reports an Intel-only filter for a
printer you depend on, that printer will stop working on upgrade. Decide in advance whether you'll
get a native driver, switch to a driverless path, or delay the upgrade.

---

## Contributing a confirmed case

If you fixed a **non-FreeX** printer with this method, please open an issue or PR adding it. Helpful
details:

- Printer make and model
- The filter name and the `file` output for it
- Your macOS version and chip (`sw_vers`, `uname -m`)
- Whether Rosetta 2 alone fixed it, or you needed something more

**Please redact private information first**: no Wi-Fi network names or passwords, no local IP
addresses, no serial numbers, no shipping labels, no customer or order data. Use placeholders such as
`YOUR_WIFI_NAME`, `192.168.1.100`, and `YOUR_MAC_USERNAME`.
