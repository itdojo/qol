#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Global variables
FILE_DIR="/etc/NetworkManager/system-connections"
UUID_CMD="uuid"

# Trap cleanup
trap 'printf "Script interrupted.\n" >&2; exit 1' INT TERM

list_interfaces() {
    local interfaces; interfaces=$(nmcli -t -f DEVICE,TYPE,STATE device status | grep -E 'ethernet|wifi')
    if [[ -z "$interfaces" ]]; then
        printf "No ethernet or WiFi interfaces found.\n" >&2
        return 1
    fi

    local idx=1
    printf "Available network interfaces:\n"
    while IFS=':' read -r dev type state; do
        local status="unconfigured"
        if nmcli -t -f DEVICE connection show --active | grep -q "^$dev$"; then
            status="configured (active)"
        elif nmcli -t -f DEVICE connection show | grep -q "^$dev$"; then
            status="configured"
        fi
        printf " [%d] %-10s (%s) - %s\n" "$idx" "$dev" "$type" "$status"
        INTERFACE_LIST["$idx"]="$dev:$type"
        ((idx++))
    done <<< "$interfaces"
}

prompt_interface_selection() {
    local selection
    while true; do
        read -rp "Enter the number of the interface to configure: " selection
        if [[ -n "${INTERFACE_LIST[$selection]:-}" ]]; then
            IFS=':' read -r IFACE IFACE_TYPE <<< "${INTERFACE_LIST[$selection]}"
            break
        fi
        printf "Invalid selection. Try again.\n" >&2
    done
}

generate_uuid() {
    if ! UUID=$($UUID_CMD 2>/dev/null); then
        printf "Failed to generate UUID using '%s'\n" "$UUID_CMD" >&2
        return 1
    fi
    if [[ -z "$UUID" || "$UUID" =~ [^a-fA-F0-9-] ]]; then
        printf "Invalid UUID generated.\n" >&2
        return 1
    fi
    printf "%s\n" "$UUID"
}

create_nm_file() {
    local con_name="$1" iface="$2" iface_type="$3" ip_method="$4"
    local uuid="$5"
    local file_path="$FILE_DIR/${con_name}.nmconnection"

    mkdir -p "$FILE_DIR"
    : > "$file_path"

    {
        printf "[connection]\n"
        printf "id=%s\n" "$con_name"
        printf "uuid=%s\n" "$uuid"
        printf "type=%s\n" "$iface_type"
        printf "interface-name=%s\n" "$iface"
        printf "autoconnect=true\n\n"

        if [[ "$iface_type" == "wifi" ]]; then
            read -rp "Enter SSID: " ssid
            read -rsp "Enter passphrase: " passphrase
            printf "\n[wifi]\n"
            printf "ssid=%s\n" "$ssid"
            printf "mode=infrastructure\n\n"

            printf "[wifi-security]\n"
            printf "key-mgmt=wpa-psk\n"
            printf "psk=%s\n\n" "$passphrase"
        fi

        if [[ "$ip_method" == "static" ]]; then
            read -rp "Enter static IP address (e.g., 192.168.1.100): " ip
            read -rp "Enter subnet mask bits (e.g., 24): " mask
            read -rp "Enter default gateway (e.g., 192.168.1.1): " gw
            read -rp "Enter DNS servers separated by semicolon (e.g., 8.8.8.8;1.1.1.1): " dns

            printf "[ipv4]\n"
            printf "method=manual\n"
            printf "addresses=%s/%s\n" "$ip" "$mask"
            printf "gateway=%s\n" "$gw"
            printf "dns=%s\n" "$dns"
            printf "dns-search=\n"
            printf "ignore-auto-dns=true\n\n"
        else
            printf "[ipv4]\n"
            printf "method=auto\n\n"
        fi

        printf "[ipv6]\n"
        printf "method=ignore\n"
    } > "$file_path"

    chmod 600 "$file_path"
    printf "\nSaved connection to %s\n" "$file_path"
}

reload_and_activate() {
    local con_name="$1"
    if ! nmcli connection reload; then
        printf "\nFailed to reload NetworkManager.\n" >&2
        return 1
    fi
    if ! nmcli connection up "$con_name"; then
        printf "\nFailed to bring up connection '%s'.\n" "$con_name" >&2
        return 1
    fi
    printf "\nConnection '%s' is now active.\n" "$con_name"
}

main() {
    declare -A INTERFACE_LIST
    list_interfaces || return 1
    prompt_interface_selection

    read -rp "Connection name: " CON_NAME
    read -rp "Use DHCP or Static IP? (dhcp/static) [dhcp]: " ip_choice
    IP_METHOD=${ip_choice,,}
    [[ -z "$IP_METHOD" ]] && IP_METHOD="dhcp"
    if [[ "$IP_METHOD" != "dhcp" && "$IP_METHOD" != "static" ]]; then
        printf "Invalid choice: '%s'. Must be 'dhcp' or 'static'.\n" "$IP_METHOD" >&2
        return 1
    fi

    if ! uuid=$(generate_uuid); then
        return 1
    fi

    create_nm_file "$CON_NAME" "$IFACE" "$IFACE_TYPE" "$IP_METHOD" "$uuid" || return 1
    reload_and_activate "$CON_NAME"
}

main "$@"
