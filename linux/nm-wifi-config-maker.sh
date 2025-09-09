#!/bin/bash

# This script creates a NetworkManager connection file for a Wi-Fi network.
# It prompts the user for connection parameters and generates a .nmconnection file.
# Usage: Run this script with sudo privileges to create a Wi-Fi connection configuration.

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo ""
    echo "❌ Run as root."
    exit 1
fi

# draw a line the width of the terminal
drawline () {
    stty_cols=$(tput cols)
    printf "%${stty_cols}s\n" | tr ' ' '-'
}

drawline
echo "🔧 Wi-Fi Connection Configuration Maker (Network Manager)"
drawline
# Prompt for connection parameters
read -rp "🆔  Enter Wi-Fi connection name (ID): " CONN_ID
read -rp "🛜  Enter SSID: " SSID

# --- Discover Wi-Fi interfaces and prompt with default ---
discover_wifi_ifs() {
    local ifs=()

    # 1) Prefer NetworkManager view
    if command -v nmcli >/dev/null 2>&1; then
        mapfile -t ifs < <(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | awk -F: '$2=="wifi"{print $1}')
    fi

    # 2) Fallback to iw
    if [[ ${#ifs[@]} -eq 0 ]] && command -v iw >/dev/null 2>&1; then
        mapfile -t ifs < <(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}')
    fi

    # 3) Fallback to sysfs (wireless presence)
    if [[ ${#ifs[@]} -eq 0 ]]; then
        while IFS= read -r -d '' dev; do
            ifs+=("$(basename "$dev")")
        done < <(find /sys/class/net -mindepth 1 -maxdepth 1 -type l -name '*' -exec bash -c '[[ -d "$0/wireless" ]] && printf "%s\0" "$0"' {} \;)
    fi

    printf '%s\n' "${ifs[@]}"
}

select_wifi_if() {
    local ifs=("$@")
    if [[ ${#ifs[@]} -eq 0 ]]; then
        echo "❌ No Wi-Fi interfaces detected. Ensure drivers are loaded and try again." >&2
        exit 1
    fi

    local default_if="${ifs[0]}"
    local options
    IFS=', ' read -r -a _ <<< "${ifs[*]}"  # no-op to satisfy shellcheck; keeps IFS side effect local
    options=$(printf "%s, " "${ifs[@]}")
    options="${options%, }"

    while :; do
        read -rp "⚙️  Enter interface name (${options}) [default: ${default_if}]: " IFACE
        IFACE="${IFACE:-$default_if}"

        # validate
        for x in "${ifs[@]}"; do
            if [[ "$IFACE" == "$x" ]]; then
                echo "$IFACE"
                return 0
            fi
        done
        echo "↩️  '$IFACE' is not in the list. Try again."
    done
}

# Get list and prompt
mapfile -t WIFI_IFS < <(discover_wifi_ifs)
IFACE="$(select_wifi_if "${WIFI_IFS[@]}")"

read -srp "🔐  Enter Wi-Fi passphrase: " PSK
echo
read -rp "❓ Use DHCP? (y/n): " USE_DHCP

if [[ "$USE_DHCP" =~ ^[Yy]$ ]]; then
    IPV4_METHOD="auto"
else
    read -rp "Enter static IP address (e.g., 192.168.1.100/24): " IPADDR
    read -rp "Enter gateway (e.g., 192.168.1.1): " GATEWAY
    read -rp "Enter DNS servers (comma-separated, e.g., 8.8.8.8,1.1.1.1): " DNS
    IPV4_METHOD="manual"
fi

UUID=$(uuid)
FILENAME="/etc/NetworkManager/system-connections/${CONN_ID}.nmconnection"

# Begin file content
cat <<EOF | sudo tee "$FILENAME" > /dev/null
[connection]
id=$CONN_ID
uuid=$UUID
type=wifi
interface-name=$IFACE
autoconnect=true
permissions=

[wifi]
mode=infrastructure
ssid=$SSID

[wifi-security]
key-mgmt=wpa-psk
psk=$PSK

[ipv4]
method=$IPV4_METHOD
EOF

# If static, append static config
if [[ "$IPV4_METHOD" == "manual" ]]; then
    cat <<EOF | sudo tee -a "$FILENAME" > /dev/null
address1=$IPADDR,$GATEWAY
dns=$(echo $DNS | tr ',' ';')
EOF
fi

# Append IPv6 config
cat <<EOF | sudo tee -a "$FILENAME" > /dev/null

[ipv6]
method=ignore
EOF

# Set ownership and permissions
chown root:root "$FILENAME"
chmod 600 "$FILENAME"

# Reload NetworkManager
echo "⚙️  Reloading NetworkManager..."
nmcli connection reload

drawline
echo "🏁  Connection '$CONN_ID' created successfully!"

echo "    Connection profile saved to $FILENAME"
echo "    Bring it up with:   sudo nmcli connection up '$CONN_ID'"
drawline