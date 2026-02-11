# Nikon Coolscan Kiosk (Raspberry Pi 5)

This project turns a **Raspberry Pi 5** with the original **7" Touch Display** into a dedicated scanning station for **Nikon Coolscan** film scanners. The system boots in kiosk mode directly into **VueScan**, disables distracting UI elements, and provides remote control via any web browser through **noVNC**.

> **[Deutsche Version / German Version](README.de.md)**

---

## Shopping List

* **Computer:** Raspberry Pi 5 (4 GB or 8 GB)
* **Display:** Official Raspberry Pi 7" Touch Display
* **Power Supply:** Raspberry Pi 27W USB-C Power Supply (required to deliver 5A for the scanner!)
* **Case:** KKSB Display Stand for Raspberry Pi Touch Display 2 with Case for Raspberry Pi 5
* **Scanner:** Nikon Coolscan IV, V, 4000 or 5000 ED
* **Software:** [VueScan Professional](https://www.hamrick.com/) (Linux 64-bit aarch64 version)

---

## Prerequisites

1. **OS Installation:** Flash Raspberry Pi OS (64-bit, Desktop) onto an SD card using *Raspberry Pi Imager*.
2. **User Setup:** Create a user (e.g. `admin`) during the flashing process.
3. **Auto-Boot:** To make the Pi start as soon as it receives power (without pressing a button):
   ```bash
   sudo -E rpi-eeprom-config --edit
   ```
   Set `POWER_OFF_ON_HALT=0` and save.
4. **USB Power:** To allow the Pi 5 to deliver the full 5A over USB, add this to the end of `/boot/firmware/config.txt`:
   ```text
   usb_max_current_enable=1
   ```

---

## Installation

To set up the system automatically, make sure the `vuescan.tgz` file is already in your home directory. Then run:

```bash
curl -sSL https://raw.githubusercontent.com/NWerdermann/nikon-coolscan-kiosk/master/setup_scanner.sh | bash
```

### What the script does

1. Checks if `vuescan.tgz` is present (aborts if not).
2. Installs system dependencies (`cifs-utils`, `nfs-common`, `novnc`, `wayvnc`).
3. Creates a udev rule so the Nikon scanner can be accessed without root.
4. Extracts VueScan to `/opt/vuescan/`.
5. Disables the panel (`wf-panel-pi`) and on-screen keyboard (`squeekboard`) via the Wayfire configuration.
6. Locks the scan folder with `chattr +i` to prevent local writes (SD card protection).
7. Configures remote access: disables auth/TLS in wayvnc, sets noVNC defaults (autoconnect, scaling, reconnect).
8. Creates a start script that launches the noVNC web interface and VueScan.
9. Sets up autostart on boot.

---

## Remote Control (Web Interface)

Since the 7" touch display is too small for precise VueScan configuration (e.g. selecting scan areas or color adjustments), this kiosk includes a built-in **noVNC** web interface. This allows the desktop to be controlled directly from a browser — no separate VNC app required.

### Architecture

```
Browser (noVNC) --WebSocket--> websockify :6080 --VNC--> wayvnc :5900
```

- **wayvnc** exposes the Wayland desktop as a VNC server (port 5900).
- **websockify** translates between WebSocket and VNC protocol and serves the noVNC web files (`/usr/share/novnc/`).
- **noVNC** is the HTML/JS client that runs in the browser.

### Browser Access

1. Make sure your PC/Mac is on the same network as the Raspberry Pi.
2. Open a modern web browser (Chrome, Firefox, Edge).
3. Enter your Pi's IP address followed by port `6080`:
   ```text
   http://<YOUR-PI-IP>:6080/vnc.html
   ```

---

## NAS Integration (Network Storage)

To save scans directly to a NAS (e.g. Synology, QNAP, or TrueNAS) instead of filling up the Pi's SD card, the network share needs to be mounted.

### 1. Preparation

First, create a local folder (mount point) on the Pi:

```bash
mkdir -p ~/Scans
```

### 2. Store Credentials Securely

Create a hidden file for your NAS login:

```bash
nano ~/.nascreds
```

Add your username and password:

```text
username=YOUR_NAS_USER
password=YOUR_NAS_PASSWORD
```

Secure the file so only you can read it:

```bash
chmod 600 ~/.nascreds
```

### 3. Configure the System (fstab)

Open `/etc/fstab` with administrator privileges:

```bash
sudo nano /etc/fstab
```

Add **one** of the following lines at the end, depending on your preferred protocol.

#### Option A: SMB/CIFS

Replace `NAS_IP` and `SHARE_NAME` with your NAS IP and the name of the shared folder:

```text
//NAS_IP/SHARE_NAME /home/admin/Scans cifs credentials=/home/admin/.nascreds,uid=1000,gid=1000,iocharset=utf8,x-systemd.automount,x-systemd.idle-timeout=60,x-systemd.device-timeout=30,nofail 0 0
```

#### Option B: NFS

Replace `NAS_IP` and the export path with your NAS values. NFS does not require a credentials file (authentication is handled by the NFS server via IP/hostname).

```text
NAS_IP:/volume/share /home/admin/Scans nfs rw,async,noatime,rsize=131072,wsize=131072,nolock,tcp,intr,_netdev,noauto,x-systemd.automount 0 0
```

> **Note:** The `async` option is important for NFS performance — without it, every write waits for server confirmation, which makes scanning noticeably slower.

### 4. Parameter Reference

#### SMB/CIFS

| Parameter | Description |
|---|---|
| `credentials=...` | Uses the hidden credentials file created above. |
| `uid=1000,gid=1000` | Grants the `admin` user full read/write access to the NAS files. |
| `x-systemd.automount` | The mount is triggered only when VueScan accesses the folder. This prevents boot delays if the NAS is still in standby. |
| `nofail` | The Pi boots cleanly even if the NAS is turned off. |

#### NFS

| Parameter | Description |
|---|---|
| `async` | Asynchronous writes — significantly improves performance. |
| `noatime` | Disables access time updates, reducing unnecessary writes. |
| `rsize=131072,wsize=131072` | 128 KB read/write block size for optimal throughput. |
| `nolock` | Disables file locking (not needed for single-client scanning). |
| `_netdev` | Tells systemd this is a network mount (wait for network before mounting). |
| `x-systemd.automount` | Mount on first access, avoids boot delays if the NAS is offline. |

### 5. Write Protection for the Local Folder

To prevent VueScan from accidentally writing to the SD card (e.g. when the NAS is unreachable), the empty mount folder is locked with an immutable flag. When the NAS is mounted, the mount automatically overlays this protection.

```bash
# Unmount NAS briefly (if already mounted)
sudo umount ~/Scans

# Lock the empty folder against writes
sudo chattr +i ~/Scans

# Remount NAS
sudo mount -a
```

> **Note:** The setup script sets `chattr +i` automatically on the first run. The commands above are only needed if you want to set up the protection retroactively.

### 6. Testing

Run this command to load the configuration without rebooting:

```bash
sudo mount -a
```

Verify with `ls ~/Scans` that the contents of your NAS folder are displayed.

---

## VueScan Profiles

This repository includes ready-made VueScan profiles for the Nikon Coolscan 5000 ED:

| Profile | Description |
|---|---|
| `Negativ-Flat-RGBI.ini` | Flat scan with RGBI (infrared channel), no automatic correction. Best for manual post-processing. |
| `Nikon automatisch.ini` | Automatic color correction by VueScan. Quick results without manual adjustments. |

### Download a Profile to the Pi

```bash
curl -sSL https://raw.githubusercontent.com/NWerdermann/nikon-coolscan-kiosk/master/Negativ-Flat-RGBI.ini -o ~/.vuescan/Negativ-Flat-RGBI.ini
```

```bash
curl -sSL https://raw.githubusercontent.com/NWerdermann/nikon-coolscan-kiosk/master/Nikon%20automatisch.ini -o ~/.vuescan/Nikon\ automatisch.ini
```

### Restart VueScan (to Load Updated Profiles)

```bash
pkill vuescan; /opt/vuescan/vuescan &
```

> **Note:** VueScan reads its profiles from `~/.vuescan/` at startup. After downloading or updating a profile, VueScan must be restarted to pick up the changes.

---

## Hardening the System (Read-Only Mode)

To protect the SD card from corruption caused by hard power-offs, the root filesystem can be overlaid with a tmpfs. The `recurse=0` parameter ensures that only the root filesystem is overlaid — the NAS mount remains writable.

A helper script is included to enable/disable the overlay:

```bash
# Download the script
curl -sSL https://raw.githubusercontent.com/NWerdermann/nikon-coolscan-kiosk/master/overlay.sh -o ~/overlay.sh
chmod +x ~/overlay.sh

# Enable read-only mode
sudo ~/overlay.sh enable

# Check current status
~/overlay.sh status

# Disable for making changes
sudo ~/overlay.sh disable
```

The script modifies `/boot/firmware/cmdline.txt` by appending `overlayroot=tmpfs:recurse=0`. A reboot is required for changes to take effect.

> **Important:** This step should only be performed at the very end, after everything has been configured and tested. To make changes later, disable the overlay and reboot first.
