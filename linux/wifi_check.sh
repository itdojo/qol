#!/usr/bin/env bash
#
# wifi_check.sh
#
# Print the SSID of the Wi-Fi network this device is associated with, or a
# "not connected" message if there is no association. Linux only.
#
# Usage:
#   ./wifi_check.sh                       # run directly
#   source /path/to/wifi_check.sh         # e.g. from .bashrc / .zshrc
#
# NOTE: deliberately no `set -e` — this file is meant to be sourced from
# interactive shells, and the probing commands are expected to "fail" on
# machines that simply have no Wi-Fi.

wifi_check() {
    if [ "$(uname -s)" != "Linux" ]; then
        printf '%s\n' " ❌ wifi_check only supports Linux."
        return 1
    fi

    if ! command -v nmcli >/dev/null 2>&1 \
        && ! command -v iw >/dev/null 2>&1 \
        && ! command -v iwgetid >/dev/null 2>&1; then
        printf '%s\n' " ❌ None of nmcli, iw, or iwgetid are installed. Cannot determine Wi-Fi status."
        return 1
    fi

    local ssid=""

    # Try the most reliable tool first: nmcli, then iw, then iwgetid.
    if command -v nmcli >/dev/null 2>&1; then
        # -t output is colon-separated with literal colons escaped as '\:'.
        ssid="$(nmcli -t -f active,ssid device wifi list 2>/dev/null \
            | awk -F: '$1 == "yes" { sub(/^yes:/, ""); gsub(/\\:/, ":"); print; exit }')"
    fi
    if [ -z "$ssid" ] && command -v iw >/dev/null 2>&1; then
        ssid="$(iw dev 2>/dev/null \
            | awk '$1 == "ssid" { sub(/^[[:space:]]*ssid[[:space:]]+/, ""); print; exit }')"
    fi
    if [ -z "$ssid" ] && command -v iwgetid >/dev/null 2>&1; then
        ssid="$(iwgetid --raw 2>/dev/null)"
    fi

    if [ -n "$ssid" ]; then
        printf '%s\n' " 🛜 Current SSID: $ssid"
    else
        printf '%s\n' " ❌ Not connected to WiFi."
    fi
}

# Runs whether this file is executed or sourced; the status propagates
# either way (exit code when executed, return code when sourced).
wifi_check "$@"
