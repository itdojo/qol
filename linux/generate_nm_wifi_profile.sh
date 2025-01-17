#!/bin/bash

# Generate a NetworkManager .nmconnection file based on user input or command-line arguments
set -e
set -o pipefail

# Global variables
NMCONNECTION_DIR="/etc/NetworkManager/system-connections"

# Function to validate SSID based on 802.11 standard rules
validate_ssid() {
    local ssid="$1"
    if [[ -z "$ssid" ]]; then
        printf "Error: SSID cannot be empty.\n" >&2
        return 1
    fi
    if [[ "${#ssid}" -gt 32 ]]; then
        printf "Error: SSID cannot exceed 32 characters.\n" >&2
        return 1
    fi
    if ! printf "%s" "$ssid" | grep -Eq '^[[:print:]]+$'; then
        printf "Error: SSID contains invalid characters.\n" >&2
        return 1
    fi
    return 0
}

# Function to validate key management option
validate_key_mgmt() {
    local key_mgmt="$1"
    if [[ "$key_mgmt" != "wpa-psk" && "$key_mgmt" != "sae" ]]; then
        printf "Error: Invalid key management option. Use 'wpa-psk' or 'sae'.\n" >&2
        return 1
    fi
    return 0
}

# Function to generate a valid PSK from plaintext
generate_psk() {
    local plaintext="$1"
    if [[ -z "$plaintext" ]]; then
        printf "Error: Pre-shared key (PSK) cannot be empty.\n" >&2
        return 1
    fi
    if [[ "${#plaintext}" -lt 8 || "${#plaintext}" -gt 63 ]]; then
        printf "Error: PSK must be between 8 and 63 characters long.\n" >&2
        return 1
    fi
    if ! printf "%s" "$plaintext" | grep -Eq '^[[:print:]]+$'; then
        printf "Error: PSK contains invalid characters.\n" >&2
        return 1
    fi
    # WPA passphrase to PSK conversion
    local ssid="$2"
    local psk
    if ! psk=$(wpa_passphrase "$ssid" "$plaintext" | grep -E '^\s*psk=' | awk -F= '{print $2}'); then
        printf "Error: Failed to generate PSK.\n" >&2
        return 1
    fi
    printf "%s" "$psk"
}

# Function to generate a UUID
generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif command -v uuid >/dev/null 2>&1; then
        uuid
    else
        printf "Neither 'uuidgen' nor 'uuid' found. Attempting to install...\n" >&2
        sudo apt update && sudo apt install -y uuid-runtime || sudo apt install -y uuid
        if command -v uuidgen >/dev/null 2>&1; then
            uuidgen
        elif command -v uuid >/dev/null 2>&1; then
            uuid
        else
            printf "Error: Failed to install a UUID generation tool.\n" >&2
            return 1
        fi
    fi
}

# Function to create the .nmconnection file
create_nmconnection_file() {
    local ssid="$1"
    local key_mgmt="$2"
    local plaintext_psk="$3"
    local psk="$4"
    local id="${ssid// /}" # Remove spaces from SSID for the 'id'
    local uuid; uuid=$(generate_uuid)

    if [[ -z "$uuid" ]]; then
        printf "Error: Could not generate UUID.\n" >&2
        return 1
    fi

    local filepath="${NMCONNECTION_DIR}/${id}.nmconnection"
    mkdir -p "$NMCONNECTION_DIR"

    printf "[connection]\n" > "$filepath"
    printf "id=%s\n" "$id" >> "$filepath"
    printf "uuid=%s\n" "$uuid" >> "$filepath"
    printf "type=wifi\n\n" >> "$filepath"

    printf "[wifi]\n" >> "$filepath"
    printf "mode=infrastructure\n" >> "$filepath"
    printf "ssid=%s\n" "$ssid" >> "$filepath"
    printf "hidden=false\n\n" >> "$filepath"

    printf "[ipv4]\n" >> "$filepath"
    printf "method=auto\n\n" >> "$filepath"

    printf "[ipv6]\n" >> "$filepath"
    printf "addr-gen-mode=default\n" >> "$filepath"
    printf "method=auto\n\n" >> "$filepath"

    printf "[proxy]\n\n" >> "$filepath"

    printf "[wifi-security]\n" >> "$filepath"
    printf "key-mgmt=%s\n" "$key_mgmt" >> "$filepath"
    printf "# Plaintext key: %s\n" "$plaintext_psk" >> "$filepath"
    printf "psk=%s\n" "$psk" >> "$filepath"

    chmod 600 "$filepath"
    printf "NetworkManager .nmconnection file created at: %s\n" "$filepath"
}

# Main function
main() {
    local ssid key_mgmt plaintext_psk psk

    if [[ -n "$1" ]]; then
        ssid="$1"
        if ! validate_ssid "$ssid"; then
            return 1
        fi
        if [[ -n "$2" ]]; then
            plaintext_psk="$2"
        else
            printf "Passphrase (8-63 printable characters): "
            read -r plaintext_psk
        fi
    else
        printf "SSID (1-32 printable characters): "
        read -r ssid
        if ! validate_ssid "$ssid"; then
            return 1
        fi
        printf "Passphrase (8-63 printable characters): "
        read -r plaintext_psk
    fi

    printf "Key Mgmt ('wpa-psk'|'sae') [wpa-psk]: "
    read -r key_mgmt
    key_mgmt="${key_mgmt:-wpa-psk}" # Default to 'wpa-psk' if empty
    if ! validate_key_mgmt "$key_mgmt"; then
        return 1
    fi

    if ! psk=$(generate_psk "$plaintext_psk" "$ssid"); then
        return 1
    fi

    create_nmconnection_file "$ssid" "$key_mgmt" "$plaintext_psk" "$psk"
}

main "$@"
