# Wi-Fi Setup for Thermal Label Printers on macOS

How to put a thermal label printer on your Wi-Fi network and add it to macOS as a network printer
over **TCP port 9100**.

The worked example is a **FreeX WiFi Thermal Label Printer** using the FreeX WiFi Toolbox. The macOS
side — port 9100, "HP Jetdirect – Socket", DHCP reservations, connectivity testing — is **identical
for any network thermal printer**. Only the vendor utility's screens differ. See
[other-printers.md](other-printers.md) for other brands.

> **⚠️ Install Rosetta 2 first if you are on an Apple Silicon Mac.** A Wi-Fi queue uses the same
> Intel-only CUPS filter as a USB queue, so it fails in exactly the same way until Rosetta is
> installed. Configuring Wi-Fi perfectly will not fix a filter problem. See the
> [README](../README.md).

All IP addresses and network names below are **placeholders**. Substitute your own.

---

## Before you start

- **The printer joins 2.4 GHz networks only.** The wireless module does not support 5 GHz or 6 GHz. If your router
  broadcasts one merged name across bands, this is the most common reason setup fails. Either
  temporarily split the bands, or use a router feature that lets a device bind to 2.4 GHz.
- **Connect the printer by USB first.** The FreeX WiFi Toolbox configures the printer's wireless
  settings *through the USB connection*. You cannot configure Wi-Fi over Wi-Fi from scratch.
- Get USB printing working first. It isolates the problem: if USB works and Wi-Fi does not, the
  issue is genuinely networking.
- Have your Wi-Fi password to hand. WPA2 personal (PSK) is what these printers expect.

---

## Step 1 — Configure Wi-Fi in the FreeX Toolbox

Connect the printer over USB, power it on, and open **FreeX WiFi Toolbox**.

Go to **FreeX Setup → WiFi** and enter:

| Field | Value |
| --- | --- |
| Mode | `STA` |
| Authentication | `WPA-PSK/WPA2-PSK` |
| Type | `WPA2-PSK` |
| Encryption | `AES` |
| SSID | `YOUR_WIFI_NAME` |
| Password | your Wi-Fi password |

Then **Apply** / **Set**.

**Notes**

- `STA` means *station* — the printer joins your existing network as a client. The alternative
  (`AP`, access point) makes the printer broadcast its own network, which is not what you want here.
- Type the SSID exactly, including capitalisation and spaces.
- Some SSIDs and passwords with unusual characters confuse this firmware. If the printer refuses to
  join and everything else looks right, try a network name without spaces or punctuation as a test.

---

## Step 2 — Configure the network settings

Go to **FreeX Setup → Ethernet**. Despite the name, on a Wi-Fi model this page configures the
printer's **IP settings** — it is not about a wired Ethernet port, and the FreeX WiFi model does not
have one:

| Field | Value |
| --- | --- |
| DHCP | `Enable` |
| Port | `9100` |

**Apply** the configuration.

**Port 9100** is the standard raw-TCP printing port (sometimes called JetDirect or AppSocket). macOS
talks to the printer directly on this port — no print server, no IPP, no drivers on the network side.

Leave **DHCP enabled**. If you want the printer to keep the same address, do it with a **DHCP
reservation on your router** rather than a static IP on the printer — it is more reliable and far
easier to undo.

---

## Step 3 — Restart the printer

Power the printer off and on.

On startup it should print a small **configuration label** showing:

- its assigned **IP address**
- the **SSID** it joined
- the **port** (`9100`)

Write down the IP. If no label prints, or the label shows no IP, the printer did not join the
network — see [Wi-Fi troubleshooting](#wi-fi-troubleshooting) below.

You can now unplug USB if you want, though leaving it connected does no harm.

---

## Step 4 — Test connectivity from the Mac

Replace `192.168.1.100` with the IP from the configuration label:

```bash
nc -vz 192.168.1.100 9100
```

Success looks like:

```
Connection to 192.168.1.100 port 9100 [tcp/hp-pdl-datastr] succeeded!
```

If that fails:

```bash
ping -c 3 192.168.1.100
```

- **Ping fails too** → the printer is not on the network, or your Mac is on a different network
  (guest Wi-Fi, a different VLAN, or a VPN that captures all traffic). Disconnect any VPN and retry.
- **Ping works but port 9100 refuses** → the printer is on the network but not listening. Re-check
  the port setting in the Toolbox and restart the printer.

---

## Step 5 — Add the printer in macOS

1. System Settings → **Printers & Scanners** → **Add Printer, Scanner, or Fax…**
2. Select the **IP** tab.

| Field | Value |
| --- | --- |
| Address | `192.168.1.100` (your printer's IP) |
| Protocol | **HP Jetdirect – Socket** |
| Queue | *leave blank* |
| Name | `FreeX Printer (WiFi)` |
| Location | optional |
| Use | **Select Software…** → **FreeX WiFi Thermal Printer** |

3. Click **Add**.

**Why "HP Jetdirect – Socket"?** It is just macOS's label for raw TCP printing on port 9100. It has
nothing to do with HP hardware and is the correct protocol for this printer. Do not use IPP, LPD, or
AirPrint.

**Do not** accept a generic driver. If the **Use** dropdown auto-fills with *Generic PostScript
Printer*, change it via **Select Software…** to **FreeX WiFi Thermal Printer**. A thermal label
printer does not understand PostScript.

---

## Step 6 — Print a test label

Open a 4x6 label PDF, press **⌘P**, choose the Wi-Fi queue, and set the paper size to the
4x6 / 100x150 mm entry. See the [4x6 Defaults](../README.md#4x6-label-defaults) section for saving this as
a preset so you don't set it every time.

---

## Wi-Fi troubleshooting

### No configuration label prints on restart

- The printer never joined the network. Re-check SSID, password, and that the network is 2.4 GHz.
- Confirm the Toolbox actually applied the settings — some versions need you to press **Set** on the
  WiFi page *and* **Apply** on the Ethernet page separately.
- Make sure labels are loaded and the gap sensor is calibrated; a printer that cannot detect labels
  prints nothing at all.

### The label prints but shows no IP address (or 0.0.0.0)

The printer associated with Wi-Fi but did not get a DHCP lease.

- Confirm DHCP is **Enable** in **FreeX Setup → Ethernet**.
- Check your router isn't out of DHCP addresses or filtering by MAC address.
- Restart the router, then the printer.

### It joined, but the Mac can't reach it

- Your Mac and the printer must be on the **same network**. Guest networks and client-isolation
  ("AP isolation") settings deliberately block device-to-device traffic — turn that off, or move the
  printer to the main network.
- Disconnect any VPN on the Mac and retry.
- Some mesh systems place devices on separate subnets. Check the IP range matches your Mac's:
  ```bash
  ipconfig getifaddr en0
  ```

### It worked, then stopped

Most likely the printer's DHCP lease expired and it got a new IP, while the macOS queue still points
at the old one. Restart the printer, read the IP from the new configuration label, and either update
the queue or — better — set a DHCP reservation on your router.

### Wi-Fi is configured but printing still fails with "Filter failed"

That is not a network problem. If `nc -vz YOUR_IP 9100` succeeds, the network is fine and the
failure is in the CUPS filter on your Mac. See the [README](../README.md) and
[troubleshooting.md](troubleshooting.md) — you need Rosetta 2.

---

## A note on macOS 28 and later

Network setup is unaffected by Apple's Rosetta 2 retirement — port 9100 keeps working. What stops
working from macOS 28 is the **Intel-only driver** that converts your document into printer
commands.

If you rely on this printer, check before upgrading:

```bash
bash scripts/diagnose_freex_macos.sh
```

If it still reports an Intel-only filter, see
[other-printers.md](other-printers.md#if-there-is-no-working-driver-at-all) for alternatives —
including driving the printer directly over port 9100, which needs no vendor driver at all.

---

## Privacy note

When sharing configuration screenshots or logs for help, redact your **SSID**, your **Wi-Fi
password**, your **local IP addresses**, and the printer's **serial number**. Use placeholders like
`YOUR_WIFI_NAME` and `192.168.1.100` instead.
