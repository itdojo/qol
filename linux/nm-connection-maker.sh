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
# ----------------------------------------------------------------------------

set -euo pipefail

# ----------------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------------
readonly NM_DIR="/etc/NetworkManager/system-connections"
readonly SCRIPT_NAME="$(basename "$0")"
readonly VERSION="2026-04"

# ANSI styling, gated on stdout being a tty so logs/pipes stay clean.
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    BOLD="$(tput bold)"
    RED="$(tput setaf 1)"
    GRN="$(tput setaf 2)"
    YEL="$(tput setaf 3)"
    BLU="$(tput setaf 4)"
    CYA="$(tput setaf 6)"
    RST="$(tput sgr0)"
else
    BOLD="" ; RED="" ; GRN="" ; YEL="" ; BLU="" ; CYA="" ; RST=""
fi

# ----------------------------------------------------------------------------
# Output helpers (drawline / title / section / status lines)
# ----------------------------------------------------------------------------
drawline() {
    local cols
    cols="$(tput cols 2>/dev/null || echo 80)"
    printf '%*s\n' "$cols" '' | tr ' ' '-'
}

title() {
    drawline
    printf "%s%s%s\n" "$BOLD" "$1" "$RST"
    drawline
}

section() {
    printf "\n%s%s  %s%s\n" "$BOLD" "$CYA" "$1" "$RST"
}

ok()    { printf "  %s✅  %s%s\n" "$GRN" "$1" "$RST"; }
warn()  { printf "  %s⚠️   %s%s\n" "$YEL" "$1" "$RST"; }
fail()  { printf "  %s❌  %s%s\n" "$RED" "$1" "$RST" >&2; }
info()  { printf "  %sℹ️   %s%s\n" "$BLU" "$1" "$RST"; }

check_status() {
    local desc="$1" rc="$2"
    if [[ $rc -eq 0 ]]; then
        ok "$desc"
    else
        fail "$desc (rc=$rc)"
        exit "$rc"
    fi
}

# ----------------------------------------------------------------------------
# Signal handling
# ----------------------------------------------------------------------------
handle_interrupt() {
    printf "\n"
    warn "Interrupted. If a profile file was written, it remains in place."
    exit 130
}
trap handle_interrupt INT TERM

# ----------------------------------------------------------------------------
# Pre-flight
# ----------------------------------------------------------------------------
require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        fail "Run as root (try: sudo $SCRIPT_NAME)"
        exit 1
    fi
}

require_cmds() {
    local missing=() c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    if (( ${#missing[@]} > 0 )); then
        fail "Missing required command(s): ${missing[*]}"
        exit 1
    fi
}

# ----------------------------------------------------------------------------
# UUID generation with fallbacks
# ----------------------------------------------------------------------------
generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif command -v uuid >/dev/null 2>&1; then
        uuid -v 4
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        fail "No UUID source found (uuidgen, uuid, or /proc/sys/kernel/random/uuid)"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# Interface discovery
# ----------------------------------------------------------------------------
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
            fail "No $want interface available."
        else
            fail "No ethernet or Wi-Fi interfaces found via nmcli."
        fi
        return 1
    fi
}

select_interface() {
    local i
    printf "\n  %sAvailable interfaces:%s\n" "$BOLD" "$RST"
    for i in "${!IFACE_DEV[@]}"; do
        printf "    [%d] %-12s %-10s (%s)\n" \
            "$((i+1))" "${IFACE_DEV[$i]}" "${IFACE_TYPE[$i]}" "${IFACE_STATE[$i]}"
    done

    local sel=""
    while true; do
        read -rp "  Select an interface (1-${#IFACE_DEV[@]}): " sel
        if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#IFACE_DEV[@]} )); then
            SELECTED_DEV="${IFACE_DEV[$((sel-1))]}"
            SELECTED_TYPE="${IFACE_TYPE[$((sel-1))]}"
            return 0
        fi
        warn "Invalid selection: '$sel'"
    done
}

# ----------------------------------------------------------------------------
# Validators
# ----------------------------------------------------------------------------
validate_ssid() {
    local ssid="$1"
    [[ -z "$ssid" ]] && { fail "SSID cannot be empty."; return 1; }
    (( ${#ssid} > 32 )) && { fail "SSID must be 32 characters or fewer."; return 1; }
    return 0
}

validate_psk() {
    local psk="$1"
    [[ -z "$psk" ]] && { fail "Passphrase cannot be empty."; return 1; }
    (( ${#psk} < 8 || ${#psk} > 63 )) && {
        fail "Passphrase must be 8-63 characters (got ${#psk})."
        return 1
    }
    return 0
}

validate_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || {
        fail "Not a valid IPv4 address: '$ip'"
        return 1
    }
    local IFS=. octets octet
    read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if (( 10#$octet > 255 )); then
            fail "Octet out of range in '$ip'"
            return 1
        fi
    done
    return 0
}

validate_cidr_bits() {
    local bits="$1"
    if [[ ! "$bits" =~ ^[0-9]+$ ]] || (( bits < 1 || bits > 32 )); then
        fail "Invalid CIDR prefix: '$bits' (must be 1-32)"
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

# ----------------------------------------------------------------------------
# Wi-Fi specific
# ----------------------------------------------------------------------------
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

# ----------------------------------------------------------------------------
# Prompts
# ----------------------------------------------------------------------------
prompt_connection_type() {
    section "Connection type"
    printf "    [1] Wi-Fi\n"
    printf "    [2] Ethernet\n"
    local sel=""
    while true; do
        read -rp "  Select (1-2): " sel
        case "$sel" in
            1) WANT_TYPE="wifi"     ; return 0 ;;
            2) WANT_TYPE="ethernet" ; return 0 ;;
            *) warn "Invalid: '$sel'" ;;
        esac
    done
}

prompt_static_ipv4() {
    while true; do
        read -rp "  IPv4 address (e.g., 192.168.1.100): " IP_ADDR
        validate_ipv4 "$IP_ADDR" && break
    done
    while true; do
        read -rp "  Prefix bits (e.g., 24): " IP_BITS
        validate_cidr_bits "$IP_BITS" && break
    done
    while true; do
        read -rp "  Default gateway (e.g., 192.168.1.1): " IP_GW
        validate_ipv4 "$IP_GW" && break
    done
    read -rp "  DNS servers, semicolon-separated [1.1.1.1;9.9.9.9]: " IP_DNS
    IP_DNS="${IP_DNS:-1.1.1.1;9.9.9.9}"
    # Allow user to type with commas; normalize to semicolons for NM.
    IP_DNS="${IP_DNS//,/;}"
}

prompt_wifi_details() {
    while true; do
        read -rp "  SSID (1-32 chars): " SSID
        validate_ssid "$SSID" && break
    done

    local plain=""
    while true; do
        read -rsp "  Passphrase (8-63 chars, hidden): " plain
        printf "\n"
        validate_psk "$plain" && break
    done

    read -rp "  Hidden SSID? [y/N]: " HIDE_ANS
    case "${HIDE_ANS:-N}" in
        [Yy]*) WIFI_HIDDEN="true" ;;
        *)     WIFI_HIDDEN="false" ;;
    esac

    section "Wi-Fi security"
    printf "    [1] WPA2-PSK  (key-mgmt=wpa-psk)  - WPA2-Personal\n"
    printf "    [2] WPA3-SAE  (key-mgmt=sae)     - WPA3-Personal\n"
    local sel=""
    while true; do
        read -rp "  Select (1-2) [1]: " sel
        sel="${sel:-1}"
        case "$sel" in
            1) KEY_MGMT="wpa-psk" ; break ;;
            2) KEY_MGMT="sae"     ; break ;;
            *) warn "Invalid: '$sel'" ;;
        esac
    done

    if [[ "$KEY_MGMT" == "wpa-psk" ]]; then
        PSK_FOR_FILE="$(hash_psk_for_wpa_psk "$SSID" "$plain")"
    else
        # SAE: plaintext passphrase
        PSK_FOR_FILE="$plain"
    fi
    unset plain
}

prompt_ipv4_method() {
    section "IPv4 configuration"
    printf "    [1] DHCP (auto)\n"
    printf "    [2] Static\n"
    local choice=""
    while true; do
        read -rp "  Select (1-2) [1]: " choice
        choice="${choice:-1}"
        case "$choice" in
            1) IP_METHOD="auto"   ; return 0 ;;
            2) IP_METHOD="manual" ; prompt_static_ipv4 ; return 0 ;;
            *) warn "Invalid: '$choice'" ;;
        esac
    done
}

prompt_ipv6_method() {
    section "IPv6 configuration"
    printf "    [1] auto    (SLAAC)\n"
    printf "    [2] ignore  (disabled)\n"
    local choice=""
    while true; do
        read -rp "  Select (1-2) [1]: " choice
        choice="${choice:-1}"
        case "$choice" in
            1) IPV6_METHOD="auto"   ; return 0 ;;
            2) IPV6_METHOD="ignore" ; return 0 ;;
            *) warn "Invalid: '$choice'" ;;
        esac
    done
}

# ----------------------------------------------------------------------------
# Config writer
# ----------------------------------------------------------------------------
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
    section "Reloading NetworkManager"
    nmcli connection reload
    check_status "nmcli connection reload" $?

    local yn=""
    read -rp "  Bring '$CONN_ID' up now? [Y/n]: " yn
    yn="${yn:-Y}"
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        section "Activating connection"
        if nmcli connection up "$CONN_ID"; then
            ok "Connection '$CONN_ID' is up."
        else
            warn "Activation failed. Check 'nmcli connection up $CONN_ID' manually."
        fi
    else
        info "Skipping activation. Bring it up later with:"
        printf "        sudo nmcli connection up '%s'\n" "$CONN_ID"
    fi
}

# ----------------------------------------------------------------------------
# main
# ----------------------------------------------------------------------------
main() {
    clear
    title "🔧  NETWORK MANAGER CONNECTION MAKER  -  v.${VERSION}"

    require_root
    require_cmds nmcli awk grep

    section "Discovering interfaces"
    discover_interfaces ""
    ok "Found ${#IFACE_DEV[@]} ethernet/Wi-Fi interface(s)."

    prompt_connection_type
    discover_interfaces "$WANT_TYPE"
    select_interface
    ok "Selected: $SELECTED_DEV ($SELECTED_TYPE)"

    section "Profile name"
    local raw_id=""
    while [[ -z "$raw_id" ]]; do
        read -rp "  Profile ID (no spaces): " raw_id
        # Strip any whitespace the user typed.
        raw_id="${raw_id//[[:space:]]/}"
    done
    CONN_ID="$(unique_connection_id "$raw_id")"
    if [[ "$CONN_ID" != "$raw_id" ]]; then
        info "Profile '$raw_id' already exists; using '$CONN_ID' instead."
    fi

    if [[ "$SELECTED_TYPE" == "wifi" ]]; then
        section "Wi-Fi credentials"
        prompt_wifi_details
    fi

    prompt_ipv4_method
    prompt_ipv6_method

    section "Generating UUID"
    UUID="$(generate_uuid)"
    ok "UUID = $UUID"

    section "Writing connection file"
    write_connection_file
    ok "Wrote $NM_FILE (mode 600, root:root)"

    reload_and_optionally_activate

    drawline
    printf "%s🏁  Done. Profile '%s' created.%s\n" "$BOLD" "$CONN_ID" "$RST"
    drawline
    echo ""
}

main "$@"
