#!/bin/bash

set -e

# --- Prompt for username ---
read -p "Enter the username to configure (default: debian): " VNC_USER
VNC_USER=${VNC_USER:-debian}

VNC_HOME="/home/$VNC_USER"
SERVICE_FILE="/etc/systemd/system/x11vnc.service"
XORG_CONF_DIR="/etc/X11/xorg.conf.d"
XORG_CONF_FILE="$XORG_CONF_DIR/10-monitor.conf"

echo "Using username: $VNC_USER"
sleep 1

echo "Updating system..."
sudo apt update -y

echo "Installing XFCE desktop..."
sudo apt install -y xfce4 xfce4-goodies

echo "Installing x11vnc..."
sudo apt install -y x11vnc

echo "Installing chromium..."
sudo apt install -y chromium

echo "Installing Xorg dummy video driver..."
sudo apt install -y xorg xserver-xorg-video-dummy

echo "Setting system to graphical target..."
sudo systemctl set-default graphical.target

echo "Installing lightdm..."
sudo apt install -y lightdm

echo "Creating x11vnc systemd service..."
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Start x11vnc at startup
After=graphical.target
Requires=graphical.target

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc \\
  -display :0 \\
  -auth /var/run/lightdm/root/:0 \\
  -nopw \\
  -localhost \\
  -forever \\
  -shared \\
  -loop \\
  -noxdamage
User=root
Group=root
Restart=on-failure

[Install]
WantedBy=graphical.target
EOF

echo "Reloading systemd..."
sudo systemctl daemon-reload
sudo systemctl enable x11vnc.service
sudo systemctl start x11vnc.service

echo "Creating Xorg config directory if missing..."
sudo mkdir -p "$XORG_CONF_DIR"

echo "Adding monitor configuration..."
sudo tee "$XORG_CONF_FILE" > /dev/null <<EOF
Section "Device"
    Identifier "DummyDevice"
    Driver "dummy"
    VideoRam 256000
EndSection

Section "Monitor"
    Identifier "Monitor0"
    Modeline "1366x768_60.00" 85.25 1366 1436 1579 1792 768 771 774 798 -hsync +vsync
    Option "PreferredMode" "1366x768_60.00"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "Default Device"
    Monitor "Monitor0"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1366x768_60.00"
    EndSubSection
EndSection
EOF

echo "✅ Setup complete. Rebooting in 3 seconds..."
sleep 3
sudo reboot
