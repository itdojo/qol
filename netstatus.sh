#!/usr/bin/env bash
#
# netstatus.sh
#
# A one-line network status readout for shell startup: which Wi-Fi network you
# are on, and whether the internet actually works. macOS and Linux.
#
#    🛜 MyNetwork   ✅ Internet   ✅ DNS
#    🛜 HotelWiFi   🔒 Captive portal
#    🔌 Wired       ✅ Internet   ✅ DNS
#    ❌ No network
#
# Usage:
#   source /path/to/netstatus.sh   # defines functions, runs nothing
#   netstatus                      # print status, honouring the cache
#   netstatus -f                   # force a fresh probe, then print
#   netstatus_boot                 # .zshrc entry point (adds the tmux gate)
#   ./netstatus.sh                 # run directly, same as `netstatus`
#
# Sourcing deliberately does not print anything. The caller decides when to run,
# which is what lets other scripts ask the question without also producing output.
#
# NOTE: no `set -e` — this is meant to be sourced by interactive shells, where
# `set -e` would leak into your login shell and make a failed probe fatal.

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
#                                                                 CONFIGURATION
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒

# Probe A is a hostname, so reaching it exercises DNS, routing, and captive-portal
# interception in a single request. Probe B is a bare IP, used only when A fails,
# to tell "DNS is broken" apart from "nothing is reachable".
NETSTATUS_URL_HOST="${NETSTATUS_URL_HOST:-http://connectivitycheck.gstatic.com/generate_204}"
NETSTATUS_URL_IP="${NETSTATUS_URL_IP:-http://1.1.1.1/}"
NETSTATUS_TIMEOUT="${NETSTATUS_TIMEOUT:-2}"

NETSTATUS_CACHE="${NETSTATUS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/qol/netstatus}"

# Younger than QUIET: print the cache and do nothing else.
# Between QUIET and STALE: print the cache, refresh in the background.
# Older than STALE (or no cache): probe synchronously so a lid-open after days
# shows current information rather than a days-old line.
NETSTATUS_TTL_QUIET="${NETSTATUS_TTL_QUIET:-30}"
NETSTATUS_TTL_STALE="${NETSTATUS_TTL_STALE:-300}"

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
#                                                                SSID DETECTION
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒

# Find the Wi-Fi interface name (en0, en1, ...). Anchored on the whole line so a
# port merely containing "Wi-Fi" in its device description cannot match.
_ns_wifi_device_macos() {
    networksetup -listallhardwareports 2>/dev/null | awk '
        /^Hardware Port: (Wi-Fi|AirPort)$/ { getline; print $2; exit }
    '
}

_ns_ssid_macos() {
    local dev ssid

    dev="$(_ns_wifi_device_macos)"
    [ -n "$dev" ] || return 1

    # The anchor matters: `ipconfig getsummary` prints BSSID *before* SSID, so an
    # unanchored match returns the access point's MAC address instead of the name.
    # sed rather than awk -F: so that an SSID containing a colon survives intact.
    ssid="$(ipconfig getsummary "$dev" 2>/dev/null \
        | sed -n 's/^[[:space:]]*SSID[[:space:]]*:[[:space:]]*//p' \
        | head -n 1)"

    # Since macOS 14, reading the SSID requires the calling process to hold
    # Location Services authorization. Without it macOS does not fail — it
    # returns the literal string "<redacted>", which is a valid-looking value
    # that will happily render as a network name if you don't check for it.
    # Its presence still proves association, so report that separately from
    # "no Wi-Fi at all". Status 2 means associated, name withheld.
    if [ "$ssid" = "<redacted>" ]; then
        return 2
    fi

    # Fallback only. On macOS 14+ this reports "You are not associated with an
    # AirPort network." while you are in fact associated, so it can never be the
    # primary source — but it still works on older releases.
    if [ -z "$ssid" ]; then
        ssid="$(networksetup -getairportnetwork "$dev" 2>/dev/null \
            | sed -n 's/^Current Wi-Fi Network: //p')"
    fi

    [ -n "$ssid" ] || return 1
    printf '%s\n' "$ssid"
}

_ns_ssid_linux() {
    local ssid=""

    # Most reliable first: nmcli, then iw, then iwgetid.
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

    [ -n "$ssid" ] || return 1
    printf '%s\n' "$ssid"
}

# Echo the current SSID. Status 0 with output means the name is known; status 2
# means associated but the OS withheld the name; status 1 means not associated.
_ns_ssid() {
    case "$(uname -s)" in
        Darwin) _ns_ssid_macos ;;
        Linux)  _ns_ssid_linux ;;
        *)      return 1 ;;
    esac
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
#                                                                  LINK / ROUTE
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒

# Echo the interface carrying the default route, or nothing if there isn't one.
# Being associated to Wi-Fi does not mean Wi-Fi is carrying your traffic: with a
# dock or USB adapter attached, both links are up and the wired one usually wins.
# Reporting the SSID in that situation credits your connectivity to the wrong
# interface, so the route is what decides the label.
_ns_primary_iface() {
    case "$(uname -s)" in
        Darwin)
            route -n get default 2>/dev/null | awk '/interface:/ { print $2; exit }'
            ;;
        Linux)
            ip route show default 2>/dev/null \
                | awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }'
            ;;
    esac
}

# Status 0 if the named interface is a Wi-Fi interface.
_ns_iface_is_wifi() {
    [ -n "$1" ] || return 1
    case "$(uname -s)" in
        Darwin) [ "$1" = "$(_ns_wifi_device_macos)" ] ;;
        Linux)  [ -d "/sys/class/net/$1/wireless" ] ;;
        *)      return 1 ;;
    esac
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
#                                                                  REACHABILITY
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒

# Echo the HTTP status code. curl prints "000" when the request never completed,
# so callers treat 000 and empty identically.
_ns_http_code() {
    curl -sS --max-time "$NETSTATUS_TIMEOUT" -o /dev/null -w '%{http_code}' "$1" 2>/dev/null
}

# Strip scheme, port, and path off a URL, leaving the bare host.
_ns_url_host() {
    printf '%s\n' "$1" | sed -e 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##' -e 's#[:/].*##'
}

_ns_ping() {
    # The flags are not portable: on macOS -W is the reply wait in *milliseconds*
    # and -t is the overall timeout in seconds; on Linux -W is the timeout in
    # seconds. Using the wrong one silently waits far too long, or not at all.
    case "$(uname -s)" in
        Darwin) ping -c 1 -t 1 "$1" >/dev/null 2>&1 ;;
        *)      ping -c 1 -W 1 "$1" >/dev/null 2>&1 ;;
    esac
}

# Fallback for machines without curl. Cannot detect a captive portal, because
# that requires reading an HTTP response rather than an ICMP echo.
_ns_reachability_ping() {
    if _ns_ping "$(_ns_url_host "$NETSTATUS_URL_HOST")"; then
        printf 'online\n'
    elif _ns_ping "$(_ns_url_host "$NETSTATUS_URL_IP")"; then
        printf 'nodns\n'
    else
        printf 'offline\n'
    fi
}

# Echo exactly one of: online | portal | nodns | offline
_ns_reachability() {
    local code

    if ! command -v curl >/dev/null 2>&1; then
        _ns_reachability_ping
        return
    fi

    code="$(_ns_http_code "$NETSTATUS_URL_HOST")"
    case "$code" in
        204)
            printf 'online\n'
            return
            ;;
        200|301|302|303|307|511)
            # Something answered on behalf of the endpoint instead of letting it
            # return its empty 204 — the signature of a hotel/airport portal.
            printf 'portal\n'
            return
            ;;
    esac

    # Probe A failed or answered oddly. A bare IP separates broken name
    # resolution from a link that carries no traffic at all.
    code="$(_ns_http_code "$NETSTATUS_URL_IP")"
    if [ -n "$code" ] && [ "$code" != "000" ]; then
        printf 'nodns\n'
    else
        printf 'offline\n'
    fi
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
#                                                                     RENDERING
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒

# Echo the Wi-Fi label: the SSID when known, a bare marker when the OS withholds
# it, nothing at all when not associated.
_ns_wifi_label() {
    local ssid rc
    ssid="$(_ns_ssid)"
    rc=$?
    if [ -n "$ssid" ]; then
        printf '🛜 %s\n' "$ssid"
    elif [ "$rc" -eq 2 ]; then
        printf '%s\n' "🛜 Wi-Fi"
    else
        return 1
    fi
}

_ns_render() {
    local primary state left right

    primary="$(_ns_primary_iface)"
    state="$(_ns_reachability)"

    case "$state" in
        online) right="✅ Internet   ✅ DNS" ;;
        portal) right="🔒 Captive portal" ;;
        nodns)  right="✅ Internet   ❌ DNS" ;;
        *)      right="❌ Offline" ;;
    esac

    if _ns_iface_is_wifi "$primary"; then
        left="$(_ns_wifi_label)" || left="🛜 Wi-Fi"
    elif [ -n "$primary" ]; then
        # Something other than Wi-Fi holds the default route. Not probed beyond
        # the route itself, so a VPN or tethered link also renders this way.
        left="🔌 Wired"
    else
        # No default route at all. Wi-Fi may still be associated, and saying so
        # is more useful than a bare failure — it separates "associated but the
        # link goes nowhere" from "nothing is connected".
        left="$(_ns_wifi_label)" || {
            printf ' %s\n' "❌ No network"
            return
        }
    fi

    printf ' %s   %s\n' "$left" "$right"
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
#                                                                         CACHE
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒

# Probe, write the result to the cache, and echo it.
# Cache format: line 1 is epoch seconds, line 2 is the rendered text.
_ns_refresh() {
    local dir tmp line

    line="$(_ns_render)"
    printf '%s\n' "$line"

    dir="$(dirname "$NETSTATUS_CACHE")"
    mkdir -p "$dir" 2>/dev/null || return 0

    # Write then rename. mv within a directory is atomic, so a shell starting up
    # concurrently reads either the old file or the new one, never a half-written
    # one. No lockfile: two simultaneous probes are harmless, whereas a lock adds
    # a stale-lock failure mode that would need its own recovery path.
    tmp="$NETSTATUS_CACHE.$$"
    if printf '%s\n%s\n' "$(date +%s)" "$line" > "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$NETSTATUS_CACHE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    else
        rm -f "$tmp" 2>/dev/null
    fi
    return 0
}

# Populate _NS_TS and _NS_LINE from the cache. Status 1 if there is nothing usable.
_ns_cache_read() {
    _NS_TS=""
    _NS_LINE=""

    [ -r "$NETSTATUS_CACHE" ] || return 1
    { IFS= read -r _NS_TS; IFS= read -r _NS_LINE; } < "$NETSTATUS_CACHE" 2>/dev/null

    case "$_NS_TS" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ -n "$_NS_LINE" ] || return 1
    return 0
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
#                                                                        PUBLIC
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒

netstatus() {
    local age now

    case "${1:-}" in
        -f|--force)
            _ns_refresh
            return
            ;;
    esac

    if ! _ns_cache_read; then
        _ns_refresh
        return
    fi

    now="$(date +%s)"
    age=$(( now - _NS_TS ))
    # A backwards clock jump would otherwise pin the cache as permanently fresh.
    [ "$age" -lt 0 ] && age="$NETSTATUS_TTL_STALE"

    if [ "$age" -lt "$NETSTATUS_TTL_QUIET" ]; then
        printf '%s\n' "$_NS_LINE"
    elif [ "$age" -lt "$NETSTATUS_TTL_STALE" ]; then
        printf '%s\n' "$_NS_LINE"
        # The inner job is orphaned when the subshell exits, so it outlives this
        # shell, holds no terminal file descriptor, and never prints job-control
        # noise. This form works in sh, bash, and zsh; zsh's `&!` does not.
        ( _ns_refresh >/dev/null 2>&1 </dev/null & )
    else
        _ns_refresh
    fi
}

# True if this shell should print the status line. Outside tmux, always. Inside
# tmux, only the first shell of a session: the marker is a session-scoped user
# option, so it dies with the session and leaves no files to clean up. Attaching
# to an existing session correctly stays quiet.
_ns_tmux_gate() {
    local sess

    [ -n "${TMUX:-}" ] || return 0
    command -v tmux >/dev/null 2>&1 || return 0

    sess="$(tmux display-message -p '#{session_id}' 2>/dev/null)"
    [ -n "$sess" ] || return 0

    # -t must precede -qv, or tmux errors with "too many arguments".
    if [ -n "$(tmux show-option -t "$sess" -qv @qol_netstatus_shown 2>/dev/null)" ]; then
        return 1
    fi

    tmux set-option -t "$sess" -q @qol_netstatus_shown 1 2>/dev/null
    return 0
}

# The .zshrc / .bashrc entry point.
netstatus_boot() {
    _ns_tmux_gate || return 0
    netstatus
}

# Run when executed, stay quiet when sourced. $BASH_SOURCE is only set by bash,
# and this file's shebang means direct execution is always bash; zsh short-circuits
# on the first test and never evaluates the second.
if [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE-}" = "$0" ]; then
    netstatus "$@"
fi
