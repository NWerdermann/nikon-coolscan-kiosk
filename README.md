# Nikon Coolscan Kiosk (Raspberry Pi 5)

Dieses Projekt verwandelt einen **Raspberry Pi 5** mit dem originalen **7" Touch-Display** in eine dedizierte Scan-Station für **Nikon Coolscan** Filmscanner. Das System bootet im Kiosk-Modus direkt in **VueScan**, deaktiviert störende UI-Elemente und ermöglicht die Fernsteuerung über jeden Webbrowser via **noVNC**.

---

## Einkaufsliste

* **Computer:** Raspberry Pi 5 (4 GB oder 8 GB)
* **Display:** Original Raspberry Pi 7" Touch Display
* **Netzteil:** Raspberry Pi 27W USB-C Power Supply (zwingend erforderlich für die 5A Stromversorgung des Scanners!)
* **Gehäuse:** KKSB Display Stand for Raspberry Pi Touch Display 2 with Case for Raspberry Pi 5
* **Scanner:** Nikon Coolscan IV, V, 4000 oder 5000 ED
* **Software:** [VueScan Professional](https://www.hamrick.com/) (Linux 64-bit aarch64 Version)

---

## Vorbereitung

1. **OS Installation:** Raspberry Pi OS (64-bit, Desktop) via *Raspberry Pi Imager* auf eine SD-Karte flashen.
2. **User-Setup:** Erstelle beim Flashen einen Benutzer (z. B. `admin`).
3. **Auto-Boot:** Damit der Pi startet, sobald er Strom bekommt (ohne Knopfdruck):
   ```bash
   sudo -E rpi-eeprom-config --edit
   ```
   Setze `POWER_OFF_ON_HALT=0` und speichere.
4. **USB-Power:** Damit der Pi 5 volle 5A an USB liefert, füge dies am Ende der `/boot/firmware/config.txt` hinzu:
   ```text
   usb_max_current_enable=1
   ```

---

## Installation

Um das System vollautomatisch einzurichten, stelle sicher, dass die Datei `vuescan.tgz` bereits in deinem Home-Verzeichnis liegt. Führe dann diesen Befehl aus:

```bash
curl -sSL https://raw.githubusercontent.com/NWerdermann/nikon-coolscan-kiosk/master/setup_scanner.sh | bash
```

### Was das Skript macht

1. Prüft, ob `vuescan.tgz` vorhanden ist (bricht ab, falls nicht).
2. Installiert Systemabhängigkeiten (`cifs-utils`, `novnc`, `wayvnc`).
3. Erstellt eine udev-Regel, damit der Nikon-Scanner ohne Root-Rechte angesprochen werden kann.
4. Entpackt VueScan nach `/opt/vuescan/`.
5. Deaktiviert Panel (`wf-panel-pi`) und On-Screen-Keyboard (`squeekboard`) über die Wayfire-Konfiguration.
6. Sperrt den Scan-Ordner mit `chattr +i` gegen lokales Schreiben (SD-Karten-Schutz).
7. Erstellt ein Start-Skript, das VNC-Server, noVNC-Web-Interface und VueScan startet.
8. Richtet den Autostart beim Booten ein.

---

## Fernsteuerung (Web-Interface)

Da das 7" Touch-Display für die präzise Konfiguration von VueScan (z. B. Auswahl von Scan-Bereichen oder Farbabgleich) zu klein ist, verfügt dieser Kiosk über ein integriertes **noVNC**-Web-Interface. Dadurch kann der Desktop direkt im Browser gesteuert werden — ohne separate VNC-App.

### Architektur

```
Browser (noVNC) --WebSocket--> websockify :6080 --VNC--> wayvnc :5900
```

- **wayvnc** stellt den Wayland-Desktop als VNC-Server bereit (Port 5900).
- **websockify** übersetzt zwischen WebSocket und VNC-Protokoll und liefert die noVNC-Webdateien aus (`/usr/share/novnc/`).
- **noVNC** ist der HTML/JS-Client, der im Browser läuft.

### Zugriff über den Browser

1. Stelle sicher, dass sich dein PC/Mac im selben Netzwerk wie der Raspberry Pi befindet.
2. Öffne einen modernen Webbrowser (Chrome, Firefox, Edge).
3. Gib die IP-Adresse deines Pi gefolgt vom Port `6080` ein:
   ```text
   http://<IP-DEINES-PI>:6080/vnc.html
   ```

---

## NAS-Anbindung (Netzwerkspeicher)

Damit die Scans direkt auf einem NAS (z. B. Synology, QNAP oder TrueNAS) gespeichert werden und nicht die SD-Karte des Pi füllen, muss die Netzwerkfreigabe eingebunden werden.

### 1. Vorbereitung

Erstelle zuerst einen lokalen Ordner (Mount-Point) auf dem Pi:

```bash
mkdir -p ~/Scans
```

### 2. Zugangsdaten sicher hinterlegen

Erstelle eine versteckte Datei für deine NAS-Logins:

```bash
nano ~/.nascreds
```

Füge dort deinen Benutzernamen und dein Passwort ein:

```text
username=DEIN_NAS_USER
password=DEIN_NAS_PASSWORT
```

Sichere die Datei ab, damit nur du sie lesen kannst:

```bash
chmod 600 ~/.nascreds
```

### 3. Systemkonfiguration anpassen (fstab)

Öffne die Datei `/etc/fstab` mit Administratorrechten:

```bash
sudo nano /etc/fstab
```

Füge am Ende der Datei die folgende Zeile hinzu. Ersetze `IP_NAS` und `ORDNERNAME` durch die IP deines NAS und den Namen des freigegebenen Ordners:

```text
//IP_NAS/ORDNERNAME /home/admin/Scans cifs credentials=/home/admin/.nascreds,uid=1000,gid=1000,iocharset=utf8,x-systemd.automount,x-systemd.idle-timeout=60,x-systemd.device-timeout=30,nofail 0 0
```

### 4. Erklärung der Parameter

| Parameter | Beschreibung |
|---|---|
| `credentials=...` | Nutzt die soeben erstellte versteckte Datei für den Login. |
| `uid=1000,gid=1000` | Gibt dem Benutzer `admin` volle Schreib- und Leserechte auf die NAS-Dateien. |
| `x-systemd.automount` | Der Mount wird erst ausgelöst, wenn VueScan auf den Ordner zugreift. Das verhindert Boot-Verzögerungen, falls das NAS noch im Standby ist. |
| `nofail` | Der Pi bootet auch dann sauber durch, wenn das NAS einmal ausgeschaltet sein sollte. |

### 5. Schreibschutz für den lokalen Ordner

Damit VueScan niemals versehentlich auf die SD-Karte schreibt (z. B. wenn das NAS nicht erreichbar ist), wird der leere Mount-Ordner mit einem Immutable-Flag gesperrt. Sobald das NAS gemountet wird, überlagert der Mount diese Sperre automatisch.

```bash
# NAS kurz aushängen (falls bereits gemountet)
sudo umount ~/Scans

# Den leeren Ordner gegen Schreiben sperren
sudo chattr +i ~/Scans

# NAS wieder einhängen
sudo mount -a
```

> **Hinweis:** Das Setup-Skript setzt `chattr +i` automatisch beim ersten Durchlauf. Die obigen Befehle sind nur nötig, falls du den Schutz nachträglich einrichten möchtest.

### 6. Testen

Führe diesen Befehl aus, um die Konfiguration ohne Neustart zu laden:

```bash
sudo mount -a
```

Überprüfe mit `ls ~/Scans`, ob der Inhalt deines NAS-Ordners angezeigt wird.

---

## System abhärten (Read-Only Mode)

Um die SD-Karte vor Defekten durch hartes Ausschalten zu schützen, sollte das System in den Read-Only Modus versetzt werden:

1. `sudo raspi-config` ausführen.
2. Unter **Performance Options** -> **Overlay File System** auf **Enable** setzen.
3. Die Schreibsperre für die Boot-Partition ebenfalls aktivieren.

Ab jetzt ist das System immun gegen Dateisystemfehler. Scans werden weiterhin sicher auf dem NAS gespeichert, da der Netzwerk-Mount vom Schreibschutz ausgenommen ist.

> **Wichtig:** Dieser Schritt sollte erst ganz zum Schluss durchgeführt werden, nachdem alles konfiguriert und getestet wurde. Um später Änderungen vorzunehmen, muss der Overlay-Modus vorübergehend wieder deaktiviert werden.
