#!/usr/bin/env bash

# Add this script to your .bashrc, .bash_profile, or .zshrc
# to get a quick overview of your internet connectivity
# status. It will show you if you have a default route,
# if you can ping your DNS server, and if you can resolve
# a website.

set -e

# --- Internet Connectivity Check -------------------
# DNS server
DNS_SERVER="1.1.1.1"

# Define a website to check connectivity with
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
