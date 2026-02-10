#!/bin/bash
set -e

# --- 1. Prüfung: VueScan-Archiv vorhanden? ---
if [ ! -f "$HOME/vuescan.tgz" ]; then
    echo "FEHLER: Die Datei vuescan.tgz wurde nicht in $HOME gefunden!"
    echo "Bitte lade VueScan (Linux aarch64) herunter und lege die Datei dort ab."
    exit 1
fi

# --- 2. System-Updates & Abhängigkeiten ---
sudo apt update && sudo apt upgrade -y
sudo apt install -y cifs-utils novnc wayvnc

# --- 3. USB-Zugriff auf Nikon-Scanner ohne Root erlauben ---
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="04b0", MODE="0666", GROUP="plugdev"' | sudo tee /etc/udev/rules.d/99-nikon-coolscan.rules
sudo udevadm control --reload-rules

# --- 4. VueScan Installation ---
sudo mkdir -p /opt/vuescan
sudo tar -xf "$HOME/vuescan.tgz" -C /opt/vuescan/ --strip-components=1
sudo chmod +x /opt/vuescan/vuescan

# --- 5. UI-Elemente deaktivieren (Panel & On-Screen-Keyboard) ---
WAYFIRE_CONFIG="$HOME/.config/wayfire.ini"

# User-Config aus System-Config erzeugen, falls nicht vorhanden
if [ ! -f "$WAYFIRE_CONFIG" ]; then
    mkdir -p "$HOME/.config"
    if [ -f /etc/wayfire.ini ]; then
        cp /etc/wayfire.ini "$WAYFIRE_CONFIG"
    fi
fi

if [ -f "$WAYFIRE_CONFIG" ]; then
    # Panel und On-Screen-Keyboard in der Wayfire-Config auskommentieren
    sed -i 's/^panel = .*$/# panel = wf-panel-pi (disabled by kiosk)/' "$WAYFIRE_CONFIG"
    sed -i 's/^keyboard = .*$/# keyboard = squeekboard (disabled by kiosk)/' "$WAYFIRE_CONFIG"
    echo "UI-Elemente in $WAYFIRE_CONFIG deaktiviert."
else
    echo "WARNUNG: Wayfire-Config nicht gefunden unter $WAYFIRE_CONFIG"
    echo "Panel und Keyboard muessen ggf. manuell deaktiviert werden."
fi

# Laufende Instanzen sofort beenden
pkill wf-panel-pi || true
pkill squeekboard || true

# --- 6. Scan-Ordner anlegen und gegen lokales Schreiben sperren ---
mkdir -p "$HOME/Scans"
sudo chattr +i "$HOME/Scans"

# --- 7. Master-Start-Skript erstellen ---
cat << 'STARTSCRIPT' > "$HOME/start-vuescan.sh"
#!/bin/bash
# Bildschirm drehen (DSI-2 auf 270 Grad / Portrait-Flip)
wlr-randr --output DSI-2 --transform 270

# VNC Server starten
pkill wayvnc || true
sleep 1
wayvnc --render-cursor 0.0.0.0 5900 &
sleep 1

# noVNC Web-Interface starten (Browser-Zugriff auf Port 6080)
pkill -f websockify || true
websockify --web /usr/share/novnc/ 6080 localhost:5900 &

# VueScan starten
/opt/vuescan/vuescan
STARTSCRIPT

chmod +x "$HOME/start-vuescan.sh"

# --- 8. Autostart einrichten ---
mkdir -p "$HOME/.config/autostart"
cat << EOF > "$HOME/.config/autostart/kiosk.desktop"
[Desktop Entry]
Type=Application
Name=ScannerKiosk
Exec=$HOME/start-vuescan.sh
X-GNOME-Autostart-enabled=true
EOF

echo "Installation abgeschlossen! Bitte einmal rebooten."
