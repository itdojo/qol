#!/usr/bin/env bash
#
# internet_check.sh
#
# Quick internet-connectivity overview:
#   1. Can we ping a well-known IP address (no DNS involved)?
#   2. Can we resolve a well-known hostname?
# Prints a compact status line such as:   ✅ Internet   ✅ DNS
#
# Usage:
#   ./internet_check.sh                       # run directly
#   source /path/to/internet_check.sh         # e.g. from .bashrc / .zshrc
#
# Exit/return status: 0 = internet + DNS OK, 1 = something is broken.
#
# NOTE: deliberately no `set -e` — this file is meant to be sourced from
# interactive shells, where `set -e` would leak into your login shell.

# Return 0 if the hostname resolves. Prefers getent, then host, then a ping.
_internet_check_resolves() {
    local host="$1"
    if command -v getent >/dev/null 2>&1; then
        getent hosts "$host" >/dev/null 2>&1
    elif command -v host >/dev/null 2>&1; then
        host -W 2 "$host" >/dev/null 2>&1
    else
        ping -c 1 -W 2 "$host" >/dev/null 2>&1
    fi
}

# Usage: internet_check [dns_server_ip] [test_hostname]
internet_check() {
    local dns_server="${1:-1.1.1.1}"
    local site="${2:-www.google.com}"
    local routes=""

    if ! command -v ping >/dev/null 2>&1; then
        printf '%s\n' " ❌ Cannot check connectivity: 'ping' is not installed."
        return 1
    fi

    # 1) Raw connectivity: ping an IP address so DNS isn't in the path.
    if ! ping -c 1 -W 2 "$dns_server" >/dev/null 2>&1; then
        printf '%s\n' " ❌ Internet"
        if command -v ip >/dev/null 2>&1; then
            routes="$(ip route show default 2>/dev/null)"
            if [ -n "$routes" ]; then
                printf '%s\n' "    Default route(s):"
                printf '%s\n' "$routes" | while IFS= read -r route; do
                    printf '      %s\n' "$route"
                done
            else
                printf '%s\n' "    No default route - check your network link."
            fi
        fi
        return 1
    fi

    # 2) Name resolution.
    if ! _internet_check_resolves "$site"; then
        printf '%s\n' " ✅ Internet   ❌ DNS"
        return 1
    fi

    printf '%s\n' " ✅ Internet   ✅ DNS"
    return 0
}

# Runs whether this file is executed or sourced; the status propagates
# either way (exit code when executed, return code when sourced).
internet_check "$@"
