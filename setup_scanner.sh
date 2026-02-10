#!/bin/bash
set -e

# --- 1. Check: VueScan archive present? ---
if [ ! -f "$HOME/vuescan.tgz" ]; then
    echo "ERROR: vuescan.tgz not found in $HOME!"
    echo "Please download VueScan (Linux aarch64) and place the file there."
    exit 1
fi

# --- 2. System updates & dependencies ---
sudo apt update && sudo apt upgrade -y
sudo apt install -y cifs-utils nfs-common novnc wayvnc

# --- 3. Allow USB access to Nikon scanner without root ---
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="04b0", MODE="0666", GROUP="plugdev"' | sudo tee /etc/udev/rules.d/99-nikon-coolscan.rules
sudo udevadm control --reload-rules

# --- 4. Install VueScan ---
sudo mkdir -p /opt/vuescan
sudo tar -xf "$HOME/vuescan.tgz" -C /opt/vuescan/ --strip-components=1
sudo chmod +x /opt/vuescan/vuescan

# --- 5. Disable UI elements (panel & on-screen keyboard) ---
WAYFIRE_CONFIG="$HOME/.config/wayfire.ini"

# Create user config from system config if not present
if [ ! -f "$WAYFIRE_CONFIG" ]; then
    mkdir -p "$HOME/.config"
    if [ -f /etc/wayfire.ini ]; then
        cp /etc/wayfire.ini "$WAYFIRE_CONFIG"
    fi
fi

if [ -f "$WAYFIRE_CONFIG" ]; then
    # Comment out panel and on-screen keyboard in Wayfire config
    sed -i 's/^panel = .*$/# panel = wf-panel-pi (disabled by kiosk)/' "$WAYFIRE_CONFIG"
    sed -i 's/^keyboard = .*$/# keyboard = squeekboard (disabled by kiosk)/' "$WAYFIRE_CONFIG"
    echo "UI elements disabled in $WAYFIRE_CONFIG."
else
    echo "WARNING: Wayfire config not found at $WAYFIRE_CONFIG"
    echo "Panel and keyboard may need to be disabled manually."
fi

# Kill running instances immediately
pkill wf-panel-pi || true
pkill squeekboard || true

# --- 6. Create scan folder and lock against local writes ---
mkdir -p "$HOME/Scans"
sudo chattr +i "$HOME/Scans"

# --- 7. Create master start script ---
cat << 'STARTSCRIPT' > "$HOME/start-vuescan.sh"
#!/bin/bash
# Rotate display (DSI-2 to 270 degrees / portrait flip)
wlr-randr --output DSI-2 --transform 270

# Start VNC server
pkill wayvnc || true
sleep 1
wayvnc --render-cursor 0.0.0.0 5900 &
sleep 1

# Start noVNC web interface (browser access on port 6080)
pkill -f websockify || true
websockify --web /usr/share/novnc/ 6080 localhost:5900 &

# Start VueScan
/opt/vuescan/vuescan
STARTSCRIPT

chmod +x "$HOME/start-vuescan.sh"

# --- 8. Set up autostart ---
mkdir -p "$HOME/.config/autostart"
cat << EOF > "$HOME/.config/autostart/kiosk.desktop"
[Desktop Entry]
Type=Application
Name=ScannerKiosk
Exec=$HOME/start-vuescan.sh
X-GNOME-Autostart-enabled=true
EOF

echo "Setup complete! Please reboot."
