#!/usr/bin/env bash

# This script checks the current SSID of the WiFi network
# that the device is currently associated with. If the device
# is not associated with a WiFi network, it will return "No WiFi Association".

set -e

# Function to check if the script is running on Linux
check_os() {
        if [[ "$(uname)" != "Linux" ]]; then
                printf "%s\n" "This script only runs on Linux."
                exit 1
        fi
}

# Function to check for required commands
check_commands() {
        for cmd in iwgetid iw nmcli; do
                if command -v $cmd &> /dev/null; then
                        return 0
                fi
        done
        printf "%s\n" "Neither iw, iwgetid, nor nmcli are installed. Cannot determine WiFi status."
        exit 1
}

# Function to get the current SSID
get_ssid() {
        local ssid=""
        if command -v iw &> /dev/null; then
                ssid=$(iw dev | grep ssid | sed s/'ssid'// | awk '{gsub(/\t/,""); print $0}')
        elif command -v nmcli &> /dev/null; then
                ssid=$(nmcli -t -f active,ssid dev wifi | grep -E '^yes' | cut -d: -f2)
        elif command -v iwgetid &> /dev/null; then
                ssid=$(iwgetid --raw)
        else
                printf "%s\n" "No suitable command found to determine WiFi status."
                exit 1
        fi

        # Debug statement to check the value of ssid

        if [[ -n "$ssid" ]]; then
                printf "%s\n" " 🛜 Current SSID: $ssid"
        else
                printf "%s\n" " ❌ Not connected to WiFi."
        fi
}

# Main script execution
main() {
        check_os
        check_commands
        get_ssid
}

main
