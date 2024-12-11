#!/usr/bin/env bash

<<<<<<< HEAD
=======
# Add this script to your .bashrc, .bash_profile, or .zshrc
# to get a quick overview of your internet connectivity
# status. It will show you if you have a default route,
# if you can ping your DNS server, and if you can resolve
# a website.

set -e

# --- Internet Connectivity Check -------------------
# DNS server
DNS_SERVER="1.1.1.1"

# Define a website to name resolution
SITE="www.google.com"

# Can you ping DNS?
ping -c 1 -w 1 $DNS_SERVER > /dev/null 2>&1
if [[ $? -ne 0 ]]; then  # pinging 1st server failed
    printf "%s\n%" " ❌ Internet!"
    defaults=$(ip route | grep default)
    if [[ $? -ne 0 ]]; then
        printf "%s\n" "You have no default route."
        return 1
    else  # there is at least one default route
        printf "%s\n" "Default route\(s\): "
        for default in "${defaults[@]}"; do
            printf "$(cut -d' ' -f3,5 <<< "$default")"
        done
    printf "\n"
    exit 1
    fi
fi

# Check DNS resolution
ping -c 1 -w 1 $SITE > /dev/null 2>&1
if [[ $? -ne 0 ]]; then  # 1st DNS query failed
    printf "%s\n" " ✅ Internet.    ❌ DNS"
    exit 1
fi

printf "%s\n" " ✅ Internet   ✅ DNS"
colin@george:~/scripts$ cat wifi_check.sh 
#!/usr/bin/env bash

>>>>>>> c3b4621 (Added internet_check.sh and wifi_check.sh)
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

<<<<<<< HEAD
main
=======
main
>>>>>>> c3b4621 (Added internet_check.sh and wifi_check.sh)
