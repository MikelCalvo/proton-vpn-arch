#!/bin/bash

# Proton VPN Waybar Setup Script for Arch Linux
# This script sets up Proton VPN integration with Waybar
# Prerequisites: Arch Linux with Waybar and WireGuard installed

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if user is in wheel group
check_wheel_group() {
    if ! groups "$USER" | grep -q '\bwheel\b'; then
        print_error "User $USER is not in the wheel group!"
        echo "Please add yourself to the wheel group first:"
        echo "  sudo usermod -aG wheel $USER"
        echo "Then logout and login again."
        exit 1
    fi
}

# Function to install required packages
install_packages() {
    print_status "Checking for required packages..."
    
    local packages=("wireguard-tools" "libnotify")
    local missing_packages=()
    
    for package in "${packages[@]}"; do
        if ! pacman -Qi "$package" &>/dev/null; then
            missing_packages+=("$package")
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        print_status "Installing missing packages: ${missing_packages[*]}"
        sudo pacman -S --noconfirm "${missing_packages[@]}"
    else
        print_success "All required packages are already installed"
    fi
}

# Function to setup sudoers configuration
setup_sudoers() {
    print_status "Configuring sudoers for passwordless wg-quick..."
    
    # Check if the rule already exists
    if sudo grep -q "wg-quick" /etc/sudoers.d/* 2>/dev/null || sudo grep -q "wg-quick" /etc/sudoers 2>/dev/null; then
        print_warning "Sudoers rule for wg-quick already exists. Checking if it's correct..."
    fi
    
    # Create a dedicated sudoers file for wg-quick
    sudo tee /etc/sudoers.d/wg-quick << 'EOF'
# Allow wheel group to run wg-quick and find commands without password
%wheel ALL=(ALL) NOPASSWD: /usr/bin/wg-quick
%wheel ALL=(ALL) NOPASSWD: /usr/bin/find /etc/wireguard *
EOF
    
    # Verify the sudoers file syntax
    if sudo visudo -cf /etc/sudoers.d/wg-quick; then
        print_success "Sudoers configuration created successfully"
    else
        print_error "Sudoers configuration has syntax errors!"
        sudo rm -f /etc/sudoers.d/wg-quick
        exit 1
    fi
}

# Function to setup WireGuard directory permissions
setup_wireguard_permissions() {
    print_status "Setting up WireGuard directory permissions..."
    
    if [ ! -d "/etc/wireguard" ]; then
        print_status "Creating /etc/wireguard directory..."
        sudo mkdir -p /etc/wireguard
    fi
    
    # Make the directory readable
    sudo chmod 755 /etc/wireguard
    
    # If there are existing .conf files, make them readable
    if sudo find /etc/wireguard -name "*.conf" -type f | head -1 | grep -q .; then
        sudo chmod 644 /etc/wireguard/*.conf
        print_success "WireGuard directory and configuration files are now readable"
    else
        print_warning "No WireGuard configuration files found in /etc/wireguard"
        echo "Please download your Proton VPN WireGuard configuration files and place them in /etc/wireguard/"
    fi
}

# Function to create Waybar scripts
create_waybar_scripts() {
    print_status "Creating Waybar VPN integration scripts..."
    
    local waybar_dir="$HOME/.config/waybar"
    
    # Create waybar config directory if it doesn't exist
    if [ ! -d "$waybar_dir" ]; then
        print_status "Creating Waybar configuration directory..."
        mkdir -p "$waybar_dir"
    fi
    
    # Create check-vpn-status.sh
    cat > "$waybar_dir/check-vpn-status.sh" << 'EOF'
#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPN_CONF="$SCRIPT_DIR/vpn.conf"

# Create vpn.conf if it doesn't exist
if [ ! -f "$VPN_CONF" ]; then
    echo "VPN_NAME=\"\"" > "$VPN_CONF"
fi

# Source the config
source "$VPN_CONF"

# Check if VPN_NAME is set and not empty
if [ -z "$VPN_NAME" ]; then
    echo "{\"text\": \"󰿆\", \"class\": \"inactive\", \"tooltip\": \"No VPN configured\"}"
    exit 0
fi

# Check VPN status
if ip link show | grep -q "$VPN_NAME" 2>/dev/null; then
    echo "{\"text\": \"󰖂\", \"class\": \"active\", \"tooltip\": \"VPN Connected: $VPN_NAME\"}"
else
    echo "{\"text\": \"󰖂\", \"class\": \"inactive\", \"tooltip\": \"VPN Disconnected\"}"
fi
EOF
    
    # Create toggle-vpn.sh
    cat > "$waybar_dir/toggle-vpn.sh" << 'EOF'
#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPN_CONF="$SCRIPT_DIR/vpn.conf"

# Create vpn.conf if it doesn't exist
if [ ! -f "$VPN_CONF" ]; then
    echo "VPN_NAME=\"\"" > "$VPN_CONF"
    # Try to auto-configure with first available VPN
    configs_path="/etc/wireguard"
    if [ -d "$configs_path" ]; then
        first_config=$(sudo find "$configs_path" -maxdepth 1 -name "*.conf" -type f 2>/dev/null | head -n1 | xargs -r basename -s .conf)
        if [ -n "$first_config" ]; then
            echo "VPN_NAME=\"$first_config\"" > "$VPN_CONF"
        fi
    fi
fi

# Source the config
source "$VPN_CONF"

# Check if VPN_NAME is set
if [ -z "$VPN_NAME" ]; then
    notify-send "VPN Error" "No VPN configuration found. Right-click to select one."
    exit 1
fi

# Toggle VPN
if ip link show | grep -q "$VPN_NAME" 2>/dev/null; then
    # VPN is connected, disconnect it
    if timeout 2 env SUDO_ASKPASS=/bin/false sudo -A -n wg-quick down "$VPN_NAME" 2>/dev/null; then
        notify-send "VPN Disconnected" "Disconnected from $VPN_NAME"
    elif timeout 2 sudo -n wg-quick down "$VPN_NAME" 2>/dev/null; then
        notify-send "VPN Disconnected" "Disconnected from $VPN_NAME"
    else
        notify-send "VPN Error" "Failed to disconnect from $VPN_NAME"
    fi
else
    # VPN is disconnected, connect it
    if timeout 2 env SUDO_ASKPASS=/bin/false sudo -A -n wg-quick up "$VPN_NAME" 2>/dev/null; then
        notify-send "VPN Connected" "Connected to $VPN_NAME"
    elif timeout 2 sudo -n wg-quick up "$VPN_NAME" 2>/dev/null; then
        notify-send "VPN Connected" "Connected to $VPN_NAME"
    else
        notify-send "VPN Error" "Failed to connect to $VPN_NAME"
    fi
fi

# Force waybar to update
pkill -RTMIN+8 waybar 2>/dev/null || true
EOF
    
    # Create select.sh
    cat > "$waybar_dir/select.sh" << 'EOF'
#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPN_CONF="$SCRIPT_DIR/vpn.conf"

# Find available VPN configurations
configs_path="/etc/wireguard"
configs=()

# Check if directory exists
if [ ! -d "$configs_path" ]; then
    echo "Directory $configs_path does not exist"
    read -p "Press Enter to continue..."
    exit 1
fi

# Use sudo to list .conf files since /etc/wireguard requires elevated permissions
echo "Scanning for VPN configurations..."
while IFS= read -r -d '' conf_file; do
    if [ -n "$conf_file" ]; then
        # Extract basename without .conf extension
        basename_conf=$(basename "$conf_file" .conf)
        configs+=("$basename_conf")
    fi
done < <(sudo find "$configs_path" -maxdepth 1 -name "*.conf" -type f -print0 2>/dev/null)

if [ ${#configs[@]} -eq 0 ]; then
    echo "No WireGuard configurations found in $configs_path"
    echo "Make sure you have .conf files in /etc/wireguard/"
    echo ""
    echo "To get Proton VPN configurations:"
    echo "1. Log in to your Proton VPN account"
    echo "2. Go to Downloads section"
    echo "3. Download WireGuard configurations"
    echo "4. Place the .conf files in /etc/wireguard/"
    read -p "Press Enter to continue..."
    exit 1
fi

# Get current VPN name if exists
current_vpn=""
if [ -f "$VPN_CONF" ]; then
    source "$VPN_CONF"
    current_vpn="$VPN_NAME"
fi

# Present a selection menu
echo "Current VPN: ${current_vpn:-"None"}"
echo ""
echo "Available VPN configurations:"
echo "0) Disconnect current VPN (if any)"

for i in "${!configs[@]}"; do
    echo "$((i+1))) ${configs[i]}"
done

echo ""
read -p "Select option (0-${#configs[@]}): " choice

# Handle disconnect option
if [ "$choice" = "0" ]; then
    if [ -n "$current_vpn" ] && ip link show | grep -q "$current_vpn" 2>/dev/null; then
        echo "Disconnecting from $current_vpn..."
        if sudo wg-quick down "$current_vpn"; then
            echo "Successfully disconnected from $current_vpn"
        else
            echo "Failed to disconnect from $current_vpn"
        fi
    else
        echo "No VPN currently connected"
    fi
    read -p "Press Enter to continue..."
    exit 0
fi

# Validate selection
if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#configs[@]}" ]; then
    selected_vpn="${configs[$((choice-1))]}"
    
    # Update vpn.conf
    echo "VPN_NAME=\"$selected_vpn\"" > "$VPN_CONF"
    echo "VPN configuration updated to $selected_vpn"
    
    # If a VPN is currently connected, disconnect it
    if [ -n "$current_vpn" ] && ip link show | grep -q "$current_vpn" 2>/dev/null; then
        echo "Disconnecting from $current_vpn..."
        sudo wg-quick down "$current_vpn"
    fi
    
    # Connect to the new VPN
    echo "Connecting to $selected_vpn..."
    if sudo wg-quick up "$selected_vpn"; then
        echo "Successfully connected to $selected_vpn"
    else
        echo "Failed to connect to $selected_vpn"
    fi
    
    read -p "Press Enter to continue..."
else
    echo "Invalid selection."
    read -p "Press Enter to continue..."
    exit 1
fi
EOF
    
    # Make scripts executable
    chmod +x "$waybar_dir/check-vpn-status.sh"
    chmod +x "$waybar_dir/toggle-vpn.sh"
    chmod +x "$waybar_dir/select.sh"
    
    print_success "Waybar VPN scripts created successfully"
}

# Function to update Waybar configuration
update_waybar_config() {
    print_status "Updating Waybar configuration..."
    
    local waybar_config="$HOME/.config/waybar/config.jsonc"
    local backup_config="$waybar_config.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$waybar_config" ]; then
        # Create backup
        cp "$waybar_config" "$backup_config"
        print_status "Backup created: $backup_config"
        
        # Check if VPN module already exists
        if grep -q '"custom/vpn"' "$waybar_config"; then
            print_warning "VPN module already exists in Waybar configuration"
            echo "Please manually add 'custom/vpn' to your modules-right array if it's not already there"
        else
            print_status "VPN module configuration needs to be added manually to your Waybar config"
        fi
    else
        print_warning "Waybar config file not found at $waybar_config"
    fi
    
    # Display the VPN module configuration
    echo ""
    print_status "Add this VPN module to your Waybar configuration:"
    echo ""
    cat << 'EOF'
In your modules-right array, add: "custom/vpn"

And add this configuration block:

"custom/vpn": {
    "format": "{}",
    "interval": 3,
    "return-type": "json",
    "exec": "$HOME/.config/waybar/check-vpn-status.sh",
    "on-click": "$HOME/.config/waybar/toggle-vpn.sh",
    "on-click-right": "alacritty -e $HOME/.config/waybar/select.sh",
    "signal": 8
}
EOF
}

# Function to create CSS styling
create_waybar_css() {
    print_status "Creating Waybar CSS styling for VPN module..."
    
    local waybar_css="$HOME/.config/waybar/style.css"
    local css_backup=""
    
    if [ -f "$waybar_css" ]; then
        css_backup="$waybar_css.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$waybar_css" "$css_backup"
        print_status "CSS backup created: $css_backup"
    fi
    
    # Add VPN CSS if it doesn't exist
    if [ -f "$waybar_css" ] && ! grep -q "#custom-vpn" "$waybar_css"; then
        cat >> "$waybar_css" << 'EOF'

/* VPN Module Styling */
#custom-vpn {
    color: #ffffff;
    margin: 0 5px;
    padding: 0 10px;
    border-radius: 5px;
}

#custom-vpn.active {
    background-color: #4CAF50;
    color: #000000;
}

#custom-vpn.inactive {
    background-color: #f44336;
    color: #ffffff;
}
EOF
        print_success "VPN CSS styling added to $waybar_css"
    else
        print_status "CSS styling for VPN module (add manually if needed):"
        echo ""
        cat << 'EOF'
/* VPN Module Styling */
#custom-vpn {
    color: #ffffff;
    margin: 0 5px;
    padding: 0 10px;
    border-radius: 5px;
}

#custom-vpn.active {
    background-color: #4CAF50;
    color: #000000;
}

#custom-vpn.inactive {
    background-color: #f44336;
    color: #ffffff;
}
EOF
    fi
}

# Function to test the setup
test_setup() {
    print_status "Testing the setup..."
    
    # Test sudo access
    if sudo -n wg-quick --help >/dev/null 2>&1; then
        print_success "Sudo access for wg-quick: OK"
    else
        print_error "Sudo access for wg-quick: FAILED"
        echo "You may need to logout and login again for sudo changes to take effect"
    fi
    
    # Test find access
    if sudo -n find /etc/wireguard -maxdepth 1 -name "*.conf" -type f >/dev/null 2>&1; then
        print_success "Sudo access for find command: OK"
    else
        print_error "Sudo access for find command: FAILED"
    fi
    
    # Test script permissions
    local waybar_dir="$HOME/.config/waybar"
    for script in "check-vpn-status.sh" "toggle-vpn.sh" "select.sh"; do
        if [ -x "$waybar_dir/$script" ]; then
            print_success "Script $script: OK"
        else
            print_error "Script $script: NOT EXECUTABLE"
        fi
    done
    
    # Check for WireGuard configs
    local config_count=$(sudo find /etc/wireguard -maxdepth 1 -name "*.conf" -type f 2>/dev/null | wc -l)
    if [ "$config_count" -gt 0 ]; then
        print_success "Found $config_count WireGuard configuration(s)"
    else
        print_warning "No WireGuard configurations found"
        echo "Please download Proton VPN WireGuard configs and place them in /etc/wireguard/"
    fi
}

# Main function
main() {
    echo "=================================================="
    echo "Proton VPN Waybar Setup Script for Arch Linux"
    echo "=================================================="
    echo ""
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_error "Please don't run this script as root!"
        exit 1
    fi
    
    # Check wheel group membership
    check_wheel_group
    
    # Install required packages
    install_packages
    
    # Setup sudoers
    setup_sudoers
    
    # Setup WireGuard permissions
    setup_wireguard_permissions
    
    # Create Waybar scripts
    create_waybar_scripts
    
    # Update Waybar configuration
    update_waybar_config
    
    # Create CSS styling
    create_waybar_css
    
    # Test the setup
    test_setup
    
    echo ""
    print_success "Setup completed!"
    echo ""
    print_status "Next steps:"
    echo "1. Download your Proton VPN WireGuard configurations from your account"
    echo "2. Place the .conf files in /etc/wireguard/"
    echo "3. Add 'custom/vpn' to your Waybar modules-right array in config.jsonc"
    echo "4. Add the VPN module configuration shown above to your Waybar config"
    echo "5. Restart Waybar: pkill waybar && waybar &"
    echo ""
    echo "Usage:"
    echo "- Left click VPN icon: Toggle VPN connection"
    echo "- Right click VPN icon: Select VPN configuration"
    echo ""
    print_warning "You may need to logout and login again for sudo changes to take full effect"
}

# Run the main function
main "$@"