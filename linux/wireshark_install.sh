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
# ----------------------------------------------------------------------------

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
BASE_FUNCTIONS="${SCRIPT_DIR}/base_functions.sh"
BASE_FUNCTIONS_URL="https://raw.githubusercontent.com/itdojo/qol/refs/heads/main/linux/base_functions.sh"

if [ ! -f "$BASE_FUNCTIONS" ]; then
    echo "base_functions.sh not found. Downloading from GitHub..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$BASE_FUNCTIONS_URL" -o "$BASE_FUNCTIONS"
    else
        wget -q "$BASE_FUNCTIONS_URL" -O "$BASE_FUNCTIONS"
    fi || { echo "❌  Failed to download base_functions.sh"; exit 1; }
fi

# shellcheck source=base_functions.sh
source "$BASE_FUNCTIONS"
command -v log_step >/dev/null 2>&1 \
    || { echo "❌  base_functions.sh is outdated. Update it from https://github.com/itdojo/qol."; exit 1; }

as_root
check_if_linux

log_title "🦈  WIRESHARK INSTALLER  -  v.2026-07"

if ! command -v apt-get >/dev/null 2>&1; then
    log_err "apt-get not found. This installer supports Debian/Ubuntu-family systems only."
    exit 1
fi

# ----------------------------------------------------------------------------
# Detect distro
# ----------------------------------------------------------------------------
log_step "Gathering Linux release info..."
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '%s\n' "OS Version: ${PRETTY_NAME:-unknown} (${VERSION_CODENAME:-unknown})"
else
    log_err "/etc/os-release not found. Cannot determine distribution."
    exit 1
fi

# ----------------------------------------------------------------------------
# PPA (Ubuntu family only)
# ----------------------------------------------------------------------------
if [ "${ID:-}" = "ubuntu" ] || [[ "${ID_LIKE:-}" == *ubuntu* ]]; then
    log_step "Adding the wireshark-dev/stable PPA..."
    if ! command -v add-apt-repository >/dev/null 2>&1; then
        install_packages software-properties-common
    fi
    add-apt-repository -y ppa:wireshark-dev/stable
    check_status "Adding wireshark-dev/stable PPA" $?
else
    log_info "Non-Ubuntu system detected (${ID:-unknown}); installing Wireshark from the distro repos."
fi

update_repo

# ----------------------------------------------------------------------------
# Install
# ----------------------------------------------------------------------------
# Answer the "should non-superusers be able to capture packets?" prompt ahead
# of time so apt never blocks waiting for input.
log_step "Preseeding Wireshark capture permissions (non-root capture: yes)..."
echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections

install_packages wireshark tshark

# ----------------------------------------------------------------------------
# Let the invoking (non-root) user capture without sudo
# ----------------------------------------------------------------------------
capture_user="${SUDO_USER:-}"
if [ -n "$capture_user" ] && [ "$capture_user" != "root" ] && id "$capture_user" >/dev/null 2>&1; then
    log_step "Adding $capture_user to the wireshark group..."
    usermod -aG wireshark "$capture_user"
    check_status "Add $capture_user to wireshark group" $?
    log_info "Log out and back in (or run 'newgrp wireshark') for the group change to take effect."
else
    log_info "No non-root user detected. To capture without sudo, run:  sudo usermod -aG wireshark <username>"
fi

log_title "🏁  WIRESHARK INSTALL COMPLETE"
echo ""
