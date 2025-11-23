# Proton VPN Waybar Integration for Arch Linux

An automated setup script for integrating Proton VPN with Waybar on Arch Linux using WireGuard. This creates a functional VPN toggle button in your Waybar with click-to-connect functionality.

**Original guide**: This script is based on the tutorial by [rulonder](https://github.com/basecamp/omarchy/discussions/1366)

![VPN Module Preview](https://img.shields.io/badge/VPN-Connected-green)

## Features

- **One-click VPN toggle** - Left-click to connect/disconnect
- **Server selection** - Right-click to choose different VPN servers
- **Random VPN Mode** - Randomly select your VPN server
- **Real-time status** - Visual indicator with connection status
- **Passwordless operation** - No password prompts during VPN operations
- **Desktop notifications** - Get notified of connection changes
- **Lightweight** - Minimal resource usage

## Prerequisites

- Arch Linux
- Waybar
- Proton VPN account (can be free)

## Installation

### 1. Download and Run the Setup Script

```bash
# Download the setup script
wget https://raw.githubusercontent.com/lajosdeme/proton-vpn-arch/main/proton-vpn-setup.sh

# Make it executable
chmod +x proton-vpn-setup.sh

# Run the setup
./proton-vpn-setup.sh
```

### 2. Download Proton VPN WireGuard Configurations

1. **Log into your Proton VPN account** at [account.protonvpn.com](https://account.protonvpn.com)

2. **Navigate to Downloads section**:
   - Go to "Downloads" in the left sidebar
   - Select "WireGuard configuration"

3. **Download configurations**:
   - Choose your preferred servers/countries
   - Select "GNU/Linux" as platform
   - Download the `.conf` files

4. **Install the configurations**:
   ```bash
   # Move downloaded .conf files to /etc/wireguard/
   sudo mv ~/Downloads/*.conf /etc/wireguard/
   
   # Set proper permissions
   sudo chmod 755 /etc/wireguard
   ```

### 3. Configure Waybar

Add the VPN module to your Waybar configuration:

**In `~/.config/waybar/config.jsonc`:**

1. **Add to modules array**:
   ```json
   "modules-right": [
       "group/tray-expander",
       "bluetooth",
       "network",
       "custom/vpn",
       "pulseaudio",
       "cpu",
       "battery"
   ]
   ```

2. **Add module configuration**:
   ```json
   "custom/vpn": {
       "format": "{}",
       "interval": 3,
       "return-type": "json",
       "exec": "$HOME/.config/waybar/check-vpn-status.sh",
       "on-click": "$HOME/.config/waybar/toggle-vpn.sh",
       "on-click-right": "alacritty -e $HOME/.config/waybar/select.sh",
       "signal": 8
   }
   ```

### 4. Restart Waybar

```bash
pkill waybar && waybar &
```

## Usage

- **Left-click** the VPN icon:
  - If specific VPN server selected: Toggle VPN connection on/off
  - If random VPN server mode: VPN server will be changed
- **Right-click** the VPN icon: Open settings menu
- **Hover** over the icon: See connection status and server name

## Troubleshooting

### VPN toggle not working

1. **Check sudo configuration**:
   ```bash
   sudo -n wg-quick --help
   ```
   This should not prompt for a password.

2. **Verify script permissions**:
   ```bash
   ls -la ~/.config/waybar/*.sh
   ```
   All scripts should be executable (`-rwxr-xr-x`).

3. **Test manual connection**:
   ```bash
   sudo wg-quick up [config-name]
   sudo wg-quick down [config-name]
   ```

### No VPN configurations found

1. **Check WireGuard directory**:
   ```bash
   sudo ls -la /etc/wireguard/
   ```

2. **Verify file permissions**:
   ```bash
   sudo chmod 755 /etc/wireguard
   ```

### Script asks for password

1. **Check if you're in wheel group**:
   ```bash
   groups $USER
   ```

2. **Verify sudoers configuration**:
   ```bash
   sudo cat /etc/sudoers.d/wg-quick
   ```

3. **If needed, logout and login again** for group changes to take effect.

### Waybar module not appearing

1. **Check Waybar config syntax**:
   ```bash
   waybar -c ~/.config/waybar/config.jsonc
   ```

2. **Verify module is in the modules array**:
   ```bash
   grep -A5 -B5 "custom/vpn" ~/.config/waybar/config.jsonc
   ```

## Files Created

The setup script creates these files in `~/.config/waybar/`:

- **`check-vpn-status.sh`** - Monitors VPN connection status
- **`toggle-vpn.sh`** - Handles VPN connection/disconnection
- **`select.sh`** - Interactive server selection menu
- **`vpn.conf`** - Stores currently selected VPN configuration

## Security Notes

- The script only grants passwordless sudo access to `wg-quick` and `find /etc/wireguard`
- Fingerprint authentication remains active for all other sudo operations
- WireGuard configuration files are kept in the standard `/etc/wireguard/` location
- All scripts run with user privileges except for the specific VPN operations

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve this setup script.

## License

This code is open source. Use it freely and modify as needed.

---
