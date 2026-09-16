# Troubleshooting Guide

Symptom-by-symptom fixes for thermal label printers and other vendor-driver printers on macOS,
especially Apple Silicon Macs (M1, M2, M3, M4).

Start with the [README](../README.md). On Apple Silicon, the large majority of these symptoms share
one root cause: **the printer's CUPS filter is an Intel-only binary and Rosetta 2 isn't installed.**

Fastest triage — read-only, works for any brand:

```bash
bash scripts/diagnose_freex_macos.sh --all
```

---

## Contents

- ["The printer software is not compatible with this device"](#the-printer-software-is-not-compatible-with-this-device)
- ["Filter failed"](#filter-failed)
- ["Bad CPU type in executable"](#bad-cpu-type-in-executable)
- [The vendor's app works but macOS printing doesn't](#the-vendors-app-works-but-macos-printing-doesnt)
- [I reinstalled the driver several times and nothing changed](#i-reinstalled-the-driver-several-times-and-nothing-changed)
- [The printer is reachable on the network but nothing prints](#the-printer-is-reachable-on-the-network-but-nothing-prints)
- [My Wi-Fi queue stopped working](#my-wi-fi-queue-stopped-working)
- [The queue I made before installing Rosetta still errors](#the-queue-i-made-before-installing-rosetta-still-errors)
- [Labels print at the wrong size or on a huge blank page](#labels-print-at-the-wrong-size-or-on-a-huge-blank-page)
- [Nothing prints and there's no error at all](#nothing-prints-and-theres-no-error-at-all)
- [The printer pauses itself after every job](#the-printer-pauses-itself-after-every-job)
- [Printing broke after a macOS upgrade](#printing-broke-after-a-macos-upgrade)
- [Starting over cleanly](#starting-over-cleanly)

---

## "The printer software is not compatible with this device"

**What macOS means:** CUPS could not run the vendor's filter program for this printer.

**What "this device" means:** your **Mac**, not your printer. The wording is misleading — it sounds
like you installed the wrong driver for your printer model.

**Usual cause:** the filter is Intel (`x86_64`) and you're on Apple Silicon without Rosetta 2.

```bash
uname -m                                                            # arm64 = Apple Silicon
file /usr/libexec/cups/filter/* | grep -i x86_64 | grep -vi arm64   # any hit = Intel-only
```

**Fix:**

```bash
softwareupdate --install-rosetta
```

Then remove and re-add the printer.

**What it is not:** a corrupted download, a macOS incompatibility, a bad USB cable, or a faulty
printer.

---

## "Filter failed"

Shown in the print queue window. Same root cause — the job reached the filter stage and the filter
couldn't be executed. The queue usually pauses itself afterwards.

**Fix:** install Rosetta 2, then:

1. Open the queue: System Settings → Printers & Scanners → the printer → **Printer Queue…**
2. Delete stuck jobs
3. **Resume** the printer if it's paused
4. If it fails again, remove the printer entirely and add it back

**If "Filter failed" persists after Rosetta is installed**, the queue is probably using the wrong
driver:

```bash
lpstat -p                                             # your queue names
lpoptions -p YOUR_QUEUE_NAME | tr ' ' '\n' | grep -i printer-make
```

It must name your real printer driver — **not** *Generic PostScript Printer* or *Generic PCL
Printer*. Thermal label printers understand neither. If it's generic, remove the queue and re-add it
with **Use → Select Software… →** your printer's driver.

Other causes of "Filter failed" worth checking once Rosetta is confirmed:

- The filter file lost its executable bit (`ls -l` should show `-rwxr-xr-x`)
- A partial driver install — reinstall the vendor package
- A PPD referencing a filter that isn't installed at all (see
  [other-printers.md](other-printers.md#finding-your-printers-filter))

---

## "Bad CPU type in executable"

The real, kernel-level error. It appears only in the CUPS log:

```bash
sudo cupsctl --debug-logging
# reproduce the failed print
sudo tail -n 100 /var/log/cups/error_log
sudo cupsctl --no-debug-logging
```

```
execv of /usr/libexec/cups/filter/rastertoFreeX failed. err:86, Bad CPU type in executable
STATE: +com.apple.badarch-error
PID 12345 (/usr/libexec/cups/filter/rastertoFreeX) stopped with status 186 (Bad CPU type in executable)
```

This is unambiguous: an Intel binary, an Apple Silicon Mac, no translation layer.

- **`err:86`** is macOS's `EBADARCH` — "bad CPU type in executable"
- **`com.apple.badarch-error`** is the system state flag for architecture mismatch. Seeing it in any
  log means *wrong CPU architecture*, never *corrupt file*
- **status 186** is what CUPS records for the failed filter

**Fix:** `softwareupdate --install-rosetta`

**Verify:**

```bash
arch -x86_64 /usr/libexec/cups/filter/rastertoFreeX
```

Success is the filter's own usage message, e.g.
`ERROR: rastertoepson job-id user title copies options [file]` — it means the binary launched.
Failure is `Bad CPU type in executable` again.

---

## The vendor's app works but macOS printing doesn't

The most confusing part of this whole problem, and completely expected.

The manufacturer's utility (FreeX WiFi Toolbox, or any vendor equivalent) talks to the printer
**directly** over USB or the network. It never goes through CUPS and never runs the CUPS filter. So
it connects, tests, and configures perfectly while every normal print job fails.

**A successful connection test does not mean printing will work.** It only proves the printer, the
cable, and the network are fine — genuinely useful, because it rules out hardware.

---

## I reinstalled the driver several times and nothing changed

Expected. Reinstalling puts back the *same Intel binary*. The file was never damaged — your Mac
simply can't execute that CPU architecture without Rosetta 2.

Install Rosetta once and the driver you already have starts working. No reinstall needed.

---

## The printer is reachable on the network but nothing prints

If this succeeds:

```bash
nc -vz 192.168.1.100 9100
```

```
Connection to 192.168.1.100 port 9100 [tcp/hp-pdl-datastr] succeeded!
```

…then the network, the IP, and port 9100 are all fine. The failure happens **before** any data
reaches the network — in the filter stage on your Mac.

Go back to the Rosetta check. A network test cannot diagnose a filter problem.

---

## My Wi-Fi queue stopped working

Almost always: **the printer's DHCP lease expired and it got a new IP**, while the macOS queue still
points at the old one.

1. Restart the printer — most print a configuration label showing the current IP
2. Compare it to the address in System Settings → Printers & Scanners → your printer
3. If they differ, remove the queue and add it again with the new IP

**Permanent fix:** set a **DHCP reservation** on your router, bound to the printer's MAC address.
Leave DHCP enabled on the printer and let the router pin the address — more reliable and easier to
undo than a static IP set on the printer.

Also check:

- The printer dropped off Wi-Fi — look for the Wi-Fi/link LED, or power-cycle it
- The router moved it to a different band or a guest network. Most of these printers are
  **2.4 GHz only**
- You changed your Wi-Fi name or password — reconfigure via the vendor Toolbox over USB

---

## The queue I made before installing Rosetta still errors

A queue created while the filter was unusable can stay in a bad state — paused, holding dead jobs, or
with a cached driver selection.

**Fix:** remove that printer completely and add it again:

1. System Settings → Printers & Scanners
2. Select the printer → **Remove Printer…**
3. **Add Printer, Scanner, or Fax…** → select your printer
4. **Use → Select Software… →** your printer's driver
5. **Add**

---

## Labels print at the wrong size or on a huge blank page

Most 4x6 thermal drivers default to the correct size — macOS apps just ignore it and open the print
dialog on **US Letter**.

```bash
lpoptions -p YOUR_QUEUE_NAME -l | grep -i PageSize
```

The `*` marks the driver default:

```
PageSize/Media Size: Custom.WIDTHxHEIGHT w283h283 w283h340 *w283h425 ...
```

For FreeX, `w283h425` = 283 × 425 points = 100 × 150 mm = 4x6.

**Fix:** in the print dialog set Paper Size to the 4x6 / 100×150 mm entry and Scale to 100% / Actual
Size, then **Presets → Save Current Settings as Preset…** and name it `Label 4x6`. Limit it to that
printer if macOS offers the option, and select it every time you print labels.

Also check:

- The label file is genuinely 4x6 — a Letter-size PDF with a small label in the corner prints exactly
  that way
- **Scale to Fit** is off
- The physical roll matches the selected size, and the **gap sensor is calibrated** (the feed or
  calibration button on the printer)

---

## Nothing prints and there's no error at all

1. Confirm the queue isn't paused: System Settings → Printers & Scanners → the printer → Resume
2. Check the default printer and queue states:
   ```bash
   lpstat -p -d
   ```
3. Clear stuck jobs:
   ```bash
   lpstat -o
   cancel -a          # cancels all queued jobs
   ```
4. Re-run the diagnostic with log output:
   ```bash
   bash scripts/diagnose_freex_macos.sh --log
   ```
5. Check the obvious physical causes: labels loaded the right way up, cover fully closed, gap sensor
   calibrated, roll not jammed.

---

## The printer pauses itself after every job

macOS pauses a queue automatically when its backend or filter reports a hard failure. It's a symptom,
not the cause.

Resuming without fixing the underlying error just fails again. Find the real error first:

```bash
sudo tail -n 100 /var/log/cups/error_log
```

If it says `Bad CPU type in executable`, install Rosetta 2, then remove and re-add the printer.

---

## Printing broke after a macOS upgrade

Two possibilities:

**1. The upgrade removed or reset something.** Re-run:

```bash
softwareupdate --install-rosetta
```

Harmless if it's already installed.

**2. You upgraded to macOS 28 or later.** From macOS 28, Rosetta 2 no longer covers general-purpose
Intel binaries, including printer drivers, so Intel-only drivers stop working permanently and cannot
be rescued. You need a native arm64 driver from the vendor, a generic driver for your printer's
language, or a driverless path such as AirPrint / IPP Everywhere. See
[other-printers.md](other-printers.md#if-there-is-no-working-driver-at-all).

Check which case you're in:

```bash
sw_vers -productVersion
bash scripts/diagnose_freex_macos.sh
```

---

## Starting over cleanly

If the configuration has become a mess, reset in this order:

1. **Install Rosetta 2 first** — everything else is pointless without it:
   ```bash
   softwareupdate --install-rosetta
   ```
2. Remove **every** queue for that printer in System Settings → Printers & Scanners
3. Reinstall the official vendor driver package from the manufacturer's own site
4. Add the printer over **USB**, choosing **Select Software… →** the real driver
5. Print a test label over USB
6. Only once USB works, configure and add the Wi-Fi queue — see [wifi-setup.md](wifi-setup.md)

Fixing USB first isolates variables: if USB works and Wi-Fi doesn't, the problem is genuinely
network-related. If neither works, it's the filter/Rosetta problem.

---

## Reporting an issue

**Redact before posting.** Do not include your Wi-Fi network name or password, local IP addresses,
the printer's serial number, shipping labels, customer names or addresses, or order and tracking
numbers. Use placeholders such as `YOUR_WIFI_NAME`, `192.168.1.100`, and `YOUR_MAC_USERNAME`.

Useful to include:

- `sw_vers` and `uname -m` output
- `file` output for your printer's filter
- Your printer make/model and driver version
- Output from `scripts/diagnose_freex_macos.sh` — check it first; queue names can contain anything
  you typed when adding the printer
