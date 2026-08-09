#!/bin/bash
#
# nm-connection-maker.sh
#
# Build a NetworkManager .nmconnection profile (Wi-Fi or Ethernet) from
# user input, write it to /etc/NetworkManager/system-connections, reload
# NetworkManager, and optionally bring the connection up.
#
# Replaces the older trio:
#   - generate_nm_wifi_profile.sh   (Wi-Fi only, DHCP only)
#   - nm-config-maker.sh            (eth/wifi, DHCP/static)
#   - nm-wifi-config-maker.sh       (Wi-Fi only, DHCP/static)
#
# Improvements over the originals:
#   - Combined ethernet + Wi-Fi support in one tool
#   - Validates SSID, passphrase length, IPv4 octets, and CIDR bits
#   - UUID fallback chain: uuidgen -> uuid -> /proc/sys/kernel/random/uuid
#   - Auto-suffixes profile name if one already exists (-2, -3, ...)
#   - Uses wpa_passphrase only for wpa-psk (SAE wants plaintext)
#   - Does NOT write the plaintext passphrase to the .nmconnection file
#   - Strict mode (set -euo pipefail) + SIGINT/SIGTERM trap
#   - File written 0600 root:root, parent dir 0700 root:root
#
# Usage:
#   sudo ./nm-connection-maker.sh
#
# IT Dojo - https://itdojo.com
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒

set -euo pipefail

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Constants
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
readonly NM_DIR="/etc/NetworkManager/system-connections"
readonly SCRIPT_NAME="$(basename "$0")"
# SCRIPT_VERSION, not VERSION: /etc/os-release defines VERSION, so a plain
# VERSION collides with anything that sources it.
readonly SCRIPT_VERSION="2026-07"

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
#                                          OUTPUT THEME (SOURCED, NOT EMBEDDED)
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# This script is Linux-only, so it sources the shared library rather than
# carrying its own copy of the theme. A copy is one more thing to drift; the
# vault's build-design-tokens.py can only check the copies it knows about.
# Same auto-download fallback as kernel_update.sh, so a lone scp'd file still
# works. Palette and rules:
#   ~/vaults/dojobrain/30-references/design-system/itdojo-terminal-design-system.md
BASE_FUNCTIONS="$(dirname "$(realpath "$0")")/base_functions.sh"
BASE_FUNCTIONS_URL="https://raw.githubusercontent.com/itdojo/qol/refs/heads/main/linux/base_functions.sh"

if [[ ! -f "$BASE_FUNCTIONS" ]]; then
    # log_* is not available yet — this is the fetch that makes it available.
    # Hand-write the same 9-column prefix the helpers emit at QOL_DEPTH=none.
    printf '%s\n' "▌ STEP   base_functions.sh not found. Downloading from GitHub..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$BASE_FUNCTIONS_URL" -o "$BASE_FUNCTIONS"
    else
        wget -q "$BASE_FUNCTIONS_URL" -O "$BASE_FUNCTIONS"
    fi || {
        printf '%s\n' "▌ STOP   Failed to download base_functions.sh." \
                      "▌ STOP   Get it from https://github.com/itdojo/qol." >&2
        exit 1
    }
fi

# shellcheck source=base_functions.sh
source "$BASE_FUNCTIONS"
command -v log_phase >/dev/null 2>&1 || {
    printf '%s\n' "▌ STOP   base_functions.sh is outdated (no log_phase)." \
                  "▌ STOP   Update it from https://github.com/itdojo/qol." >&2
    exit 1
}

# Override the library's check_status, which reports and returns. Here a failed
# step means a half-written profile, so the run stops instead of continuing.
check_status() {
    local desc="$1" rc="$2"
    if [[ $rc -eq 0 ]]; then
        log_ok "$desc"
    else
        log_err "$desc (rc=$rc)"
        exit "$rc"
    fi
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Signal handling
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
handle_interrupt() {
    printf "\n"
    log_warn "Interrupted. If a profile file was written, it remains in place."
    exit 130
}
trap handle_interrupt INT TERM

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Pre-flight
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        log_err "Run as root (try: sudo $SCRIPT_NAME)"
        exit 1
    fi
}

require_cmds() {
    local missing=() c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    if (( ${#missing[@]} > 0 )); then
        log_err "Missing required command(s): ${missing[*]}"
        exit 1
    fi
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# UUID generation with fallbacks
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif command -v uuid >/dev/null 2>&1; then
        uuid -v 4
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        log_err "No UUID source found (uuidgen, uuid, or /proc/sys/kernel/random/uuid)"
        return 1
    fi
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Interface discovery
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Populated by discover_interfaces(); parallel arrays.
declare -a IFACE_DEV=() IFACE_TYPE=() IFACE_STATE=()

discover_interfaces() {
    local want="${1:-}"          # "ethernet", "wifi", or "" for both
    IFACE_DEV=() ; IFACE_TYPE=() ; IFACE_STATE=()

    local dev type state
    while IFS=':' read -r dev type state; do
        case "$type" in
            ethernet|wifi) ;;
            *) continue ;;
        esac
        if [[ -n "$want" && "$type" != "$want" ]]; then
            continue
        fi
        IFACE_DEV+=("$dev")
        IFACE_TYPE+=("$type")
        IFACE_STATE+=("$state")
    done < <(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null)

    if (( ${#IFACE_DEV[@]} == 0 )); then
        if [[ -n "$want" ]]; then
            log_err "No $want interface available."
        else
            log_err "No ethernet or Wi-Fi interfaces found via nmcli."
        fi
        return 1
    fi
}

select_interface() {
    local i rows=() sel
    for i in "${!IFACE_DEV[@]}"; do
        rows+=("${IFACE_DEV[$i]}|${IFACE_TYPE[$i]} — ${IFACE_STATE[$i]}")
    done
    sel="$(ask_choice "SELECT AN INTERFACE" 1 "${rows[@]}")"
    SELECTED_DEV="${IFACE_DEV[$((sel-1))]}"
    SELECTED_TYPE="${IFACE_TYPE[$((sel-1))]}"
    return 0
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Validators
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
validate_ssid() {
    local ssid="$1"
    [[ -z "$ssid" ]] && { log_err "SSID cannot be empty."; return 1; }
    (( ${#ssid} > 32 )) && { log_err "SSID must be 32 characters or fewer."; return 1; }
    return 0
}

validate_psk() {
    local psk="$1"
    [[ -z "$psk" ]] && { log_err "Passphrase cannot be empty."; return 1; }
    (( ${#psk} < 8 || ${#psk} > 63 )) && {
        log_err "Passphrase must be 8-63 characters (got ${#psk})."
        return 1
    }
    return 0
}

validate_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || {
        log_err "Not a valid IPv4 address: '$ip'"
        return 1
    }
    local IFS=. octets octet
    read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if (( 10#$octet > 255 )); then
            log_err "Octet out of range in '$ip'"
            return 1
        fi
    done
    return 0
}

validate_cidr_bits() {
    local bits="$1"
    if [[ ! "$bits" =~ ^[0-9]+$ ]] || (( bits < 1 || bits > 32 )); then
        log_err "Invalid CIDR prefix: '$bits' (must be 1-32)"
        return 1
    fi
    return 0
}

# Avoid clobbering an existing profile (file or known nmcli connection).
unique_connection_id() {
    # NB: declare separately. With `set -u`, `local a=$1 b=$a` expands $a
    # in the caller's scope (before `local` creates a), and aborts.
    local base="$1"
    local candidate="$base"
    local n=2
    while [[ -e "$NM_DIR/${candidate}.nmconnection" ]] \
          || nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "$candidate"; do
        candidate="${base}-${n}"
        ((n++))
    done
    printf '%s\n' "$candidate"
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Wi-Fi specific
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Convert plaintext passphrase to hashed PSK, ONLY for wpa-psk.
# SAE expects the plaintext passphrase in the psk= field, not the PBKDF2 hash.
hash_psk_for_wpa_psk() {
    local ssid="$1" plain="$2" hashed=""
    if command -v wpa_passphrase >/dev/null 2>&1; then
        hashed="$(wpa_passphrase "$ssid" "$plain" 2>/dev/null \
                  | awk -F= '/^[[:space:]]*psk=/ {print $2; exit}')"
    fi
    if [[ -n "$hashed" ]]; then
        printf '%s' "$hashed"
    else
        # Fallback: NM accepts plaintext for wpa-psk too.
        printf '%s' "$plain"
    fi
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Prompts
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Every pick-one below is ask_choice and every free-text field is ask_value, so
# a question here looks the same as a question in any other qol script. The
# validators still gate the answer — ask_value collects, it does not validate,
# so each free-text field keeps its retry loop around the call.
prompt_connection_type() {
    local sel
    sel="$(ask_choice "CONNECTION TYPE" 1 \
        "Wi-Fi|802-11-wireless profile" \
        "Ethernet|802-3-ethernet profile")"
    case "$sel" in
        1) WANT_TYPE="wifi" ;;
        2) WANT_TYPE="ethernet" ;;
    esac
}

prompt_static_ipv4() {
    while true; do
        IP_ADDR="$(ask_value "IPv4 address" "192.168.1.100" "the address this machine will claim")"
        validate_ipv4 "$IP_ADDR" && break
    done
    while true; do
        IP_BITS="$(ask_value "Prefix bits" "24" "CIDR mask length, 1-32")"
        validate_cidr_bits "$IP_BITS" && break
    done
    while true; do
        IP_GW="$(ask_value "Default gateway" "192.168.1.1" "the router on this subnet")"
        validate_ipv4 "$IP_GW" && break
    done
    IP_DNS="$(ask_value "DNS servers" "1.1.1.1;9.9.9.9" "semicolon-separated")"
    # Allow user to type with commas; normalize to semicolons for NM.
    IP_DNS="${IP_DNS//,/;}"
}

prompt_wifi_details() {
    while true; do
        SSID="$(ask_value "SSID" "" "1-32 characters")"
        validate_ssid "$SSID" && break
    done

    # Not ask_value: the passphrase must not echo, and ask_value has no hidden
    # mode. Borrow its shape — ASK badge, dimmed hint, jade caret — by hand.
    local plain=""
    while true; do
        log_ask "Passphrase" >&2
        printf '         %s%s%s\n' "$QOL_META" "8-63 characters, hidden as you type" "$QOL_RESET" >&2
        printf '    %s❯%s ' "$QOL_PASS" "$QOL_RESET" >&2
        read -rs plain
        printf '\n' >&2
        validate_psk "$plain" && break
    done

    if ask_confirm "Is this SSID hidden?" N; then
        WIFI_HIDDEN="true"
    else
        WIFI_HIDDEN="false"
    fi

    local sel
    sel="$(ask_choice "WI-FI SECURITY" 1 \
        "WPA2-PSK|WPA2-Personal, key-mgmt=wpa-psk" \
        "WPA3-SAE|WPA3-Personal, key-mgmt=sae")"
    case "$sel" in
        1) KEY_MGMT="wpa-psk" ;;
        2) KEY_MGMT="sae" ;;
    esac

    if [[ "$KEY_MGMT" == "wpa-psk" ]]; then
        PSK_FOR_FILE="$(hash_psk_for_wpa_psk "$SSID" "$plain")"
    else
        # SAE: plaintext passphrase
        PSK_FOR_FILE="$plain"
    fi
    unset plain
}

prompt_ipv4_method() {
    local choice
    choice="$(ask_choice "IPV4 CONFIGURATION" 1 \
        "DHCP|address assigned by the network" \
        "Static|you supply address, gateway, DNS")"
    case "$choice" in
        1) IP_METHOD="auto" ;;
        2) IP_METHOD="manual"; prompt_static_ipv4 ;;
    esac
}

prompt_ipv6_method() {
    local choice
    choice="$(ask_choice "IPV6 CONFIGURATION" 1 \
        "auto|SLAAC" \
        "ignore|IPv6 disabled on this profile")"
    case "$choice" in
        1) IPV6_METHOD="auto" ;;
        2) IPV6_METHOD="ignore" ;;
    esac
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Config writer
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
write_connection_file() {
    local file="$NM_DIR/${CONN_ID}.nmconnection"

    install -d -m 700 -o root -g root "$NM_DIR"

    # Build then move atomically so a partial write never sits with 600 perms
    # under a half-baked config.
    local tmp; tmp="$(mktemp "${NM_DIR}/.${CONN_ID}.XXXXXX")"
    chmod 600 "$tmp"

    {
        printf "[connection]\n"
        printf "id=%s\n" "$CONN_ID"
        printf "uuid=%s\n" "$UUID"
        printf "type=%s\n" "$SELECTED_TYPE"
        printf "interface-name=%s\n" "$SELECTED_DEV"
        printf "autoconnect=true\n\n"

        if [[ "$SELECTED_TYPE" == "wifi" ]]; then
            printf "[wifi]\n"
            printf "mode=infrastructure\n"
            printf "ssid=%s\n" "$SSID"
            printf "hidden=%s\n\n" "$WIFI_HIDDEN"

            printf "[wifi-security]\n"
            printf "key-mgmt=%s\n" "$KEY_MGMT"
            printf "psk=%s\n\n" "$PSK_FOR_FILE"
        fi

        printf "[ipv4]\n"
        printf "method=%s\n" "$IP_METHOD"
        if [[ "$IP_METHOD" == "manual" ]]; then
            printf "addresses=%s/%s\n" "$IP_ADDR" "$IP_BITS"
            printf "gateway=%s\n" "$IP_GW"
            printf "dns=%s\n" "$IP_DNS"
            printf "ignore-auto-dns=true\n"
        fi
        printf "\n"

        printf "[ipv6]\n"
        printf "addr-gen-mode=default\n"
        printf "method=%s\n\n" "$IPV6_METHOD"

        printf "[proxy]\n"
    } > "$tmp"

    chown root:root "$tmp"
    mv -f "$tmp" "$file"
    NM_FILE="$file"
}

reload_and_optionally_activate() {
    log_step "Reloading NetworkManager..."
    nmcli connection reload
    check_status "nmcli connection reload" $?

    if ask_confirm "Bring '$CONN_ID' up now?" Y; then
        log_step "Activating the connection..."
        if nmcli connection up "$CONN_ID"; then
            log_ok "Connection '$CONN_ID' is up."
        else
            log_warn "Activation failed. Check it manually with:  nmcli connection up $CONN_ID"
        fi
    else
        log_info "Skipping activation."
        ACTIVATE_SKIPPED=1
    fi
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# main
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
main() {
    # No `clear`. A tool that blanks the scrollback has destroyed the record of
    # whatever the user ran before it; the banner is the boundary now.
    banner "NM CONNECTION MAKER" "wi-fi · ethernet · v.${SCRIPT_VERSION}"

    log_phase "PREFLIGHT"
    require_root
    require_cmds nmcli awk grep
    # Every value below comes from a question, and the answer helpers return
    # their default rather than blocking without a TTY. Refuse the run outright
    # instead of writing a profile nobody chose.
    if [[ ! -t 0 ]]; then
        log_err "This tool is interactive and stdin is not a terminal."
        log_err "Run it from a terminal:  sudo $SCRIPT_NAME"
        exit 1
    fi

    log_step "Discovering ethernet and Wi-Fi interfaces..."
    discover_interfaces ""
    log_ok "Found ${#IFACE_DEV[@]} ethernet/Wi-Fi interface(s)."

    prompt_connection_type
    discover_interfaces "$WANT_TYPE"
    select_interface
    log_ok "Selected: $SELECTED_DEV ($SELECTED_TYPE)"

    local raw_id=""
    while [[ -z "$raw_id" ]]; do
        raw_id="$(ask_value "Profile ID" "" "no spaces; whitespace is stripped")"
        # Strip any whitespace the user typed.
        raw_id="${raw_id//[[:space:]]/}"
    done
    CONN_ID="$(unique_connection_id "$raw_id")"
    if [[ "$CONN_ID" != "$raw_id" ]]; then
        log_info "Profile '$raw_id' already exists; using '$CONN_ID' instead."
    fi

    if [[ "$SELECTED_TYPE" == "wifi" ]]; then
        prompt_wifi_details
    fi

    prompt_ipv4_method
    prompt_ipv6_method

    # Everything is collected. Restate it before anything is written, so the
    # user sees what they agreed to.
    log_phase "WRITE"
    log_ok "Profile '$CONN_ID' on $SELECTED_DEV ($SELECTED_TYPE), IPv4 $IP_METHOD, IPv6 $IPV6_METHOD."

    log_step "Generating a UUID..."
    UUID="$(generate_uuid)"
    log_ok "UUID = $UUID"

    log_step "Writing the connection file..."
    write_connection_file
    log_ok "Wrote $NM_FILE (mode 600, root:root)"

    reload_and_optionally_activate

    log_complete "PROFILE '$CONN_ID' CREATED"
    if [[ -n "${ACTIVATE_SKIPPED:-}" ]]; then
        log_next "Bring the connection up:  sudo nmcli connection up '$CONN_ID'"
    fi
    log_next "Inspect it:  sudo nmcli connection show '$CONN_ID'"
    log_next "Edit it later:  sudo nmcli connection edit '$CONN_ID'"
    echo
}

main "$@"
