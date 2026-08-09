#!/bin/bash
#
# wireshark_install.sh
#
# Installs Wireshark and TShark on Debian/Ubuntu-family systems.
#   - Ubuntu & derivatives: adds the wireshark-dev/stable PPA for current builds
#   - Debian / Kali / other apt distros: installs from the distro repos
#     (the PPA only publishes Ubuntu packages)
#   - Preseeds the "allow non-root users to capture packets" debconf question
#     so the install is non-interactive
#   - Adds the invoking user to the 'wireshark' group
#
# Usage: sudo ./wireshark_install.sh
#
# Relies on base_functions.sh (auto-downloaded from GitHub if missing).
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
BASE_FUNCTIONS="${SCRIPT_DIR}/base_functions.sh"
BASE_FUNCTIONS_URL="https://raw.githubusercontent.com/itdojo/qol/refs/heads/main/linux/base_functions.sh"

if [ ! -f "$BASE_FUNCTIONS" ]; then
    # log_* is not available yet — this is the fetch that makes it available.
    # Hand-write the same 9-column prefix the helpers emit at QOL_DEPTH=none,
    # so these lines still grep as '^. STOP' alongside every other error.
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

banner "WIRESHARK INSTALLER" "wireshark · tshark · non-root capture"

log_phase "PREFLIGHT"
as_root
check_if_linux

if ! command -v apt-get >/dev/null 2>&1; then
    log_err "apt-get not found. This installer supports Debian/Ubuntu-family systems only."
    exit 1
fi

log_step "Gathering Linux release info..."
# base_functions.sh already read /etc/os-release into OS_*. Sourcing it here
# too would put the generic names (VERSION, ID, ...) back in this shell, which
# is what collides with a script's own constants.
if [ -n "$OS_ID" ]; then
    log_info "OS version: ${OS_PRETTY_NAME:-unknown} (${OS_CODENAME:-unknown})"
else
    log_err "/etc/os-release not found or unreadable. Cannot determine distribution."
    exit 1
fi

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# PPA (Ubuntu family only)
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
log_phase "REPOSITORY"
if [ "$OS_ID" = "ubuntu" ] || [[ "$OS_ID_LIKE" == *ubuntu* ]]; then
    log_step "Adding the wireshark-dev/stable PPA..."
    if ! command -v add-apt-repository >/dev/null 2>&1; then
        install_packages software-properties-common
    fi
    add-apt-repository -y ppa:wireshark-dev/stable
    check_status "Adding wireshark-dev/stable PPA" $?
else
    log_info "Non-Ubuntu system detected (${OS_ID:-unknown}); installing Wireshark from the distro repos."
fi

update_repo

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Install
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
log_phase "WIRESHARK"
# Answer the "should non-superusers be able to capture packets?" prompt ahead
# of time so apt never blocks waiting for input.
log_step "Preseeding Wireshark capture permissions (non-root capture: yes)..."
echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections

install_packages wireshark tshark

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Let the invoking (non-root) user capture without sudo
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
log_phase "CAPTURE PERMISSIONS"
capture_user="${SUDO_USER:-}"
group_added=""
if [ -n "$capture_user" ] && [ "$capture_user" != "root" ] && id "$capture_user" >/dev/null 2>&1; then
    log_step "Adding $capture_user to the wireshark group..."
    usermod -aG wireshark "$capture_user"
    check_status "Add $capture_user to wireshark group" $?
    group_added=1
else
    log_info "No non-root user detected; nobody was added to the wireshark group."
fi

log_complete "WIRESHARK INSTALL COMPLETE"
if [ -n "$group_added" ]; then
    log_next "Log out and back in for the group change to take effect."
    log_next "Or apply it to this shell now:  newgrp wireshark"
else
    log_next "To capture without sudo:  sudo usermod -aG wireshark <username>"
fi
log_next "Start capturing:  wireshark   (or tshark -i <interface> for the CLI)"
echo
