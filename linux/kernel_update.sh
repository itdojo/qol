#!/bin/bash

# This script updates the Linux kernel to the latest available version.
# It uses a different update strategy depending on the detected platform:
#   - Raspberry Pi OS:        apt full-upgrade (standard) plus optional, opt-in
#                             rpi-update (bleeding-edge firmware/kernel)
#   - Kali Linux:             apt dist-upgrade + full-upgrade (rolling release)
#   - Debian (non-Kali):      apt full-upgrade against the configured suites
#                             (use backports manually if you want newer kernels)
#   - Ubuntu / Pop!_OS / Mint / Ubuntu derivatives:
#                             cappelikan/ppa "mainline" utility -> install-latest
#
# It has been successfully tested on Ubuntu, Pop!_OS, Linux Mint, Kali, Debian,
# and Raspberry Pi OS.
#
# Updated: April 2026
#  - Fixed kernel-change detection. uname -r reflects the RUNNING kernel and
#    does NOT change until reboot, so the previous before/after compare could
#    never detect a successful upgrade. Now compares the newest installed
#    kernel (from /usr/lib/modules) against the running kernel.
#  - Source /etc/os-release for reliable distro detection (was: grep against
#    a globbed /etc/os-release*).
#  - Fixed ca-certificates check. ca-certificates is a package, not a binary,
#    so `command -v ca-certificates` always failed. Install directly where
#    needed.
#  - Hardened Raspberry Pi detection: prefers /proc/device-tree/model, falls
#    back to /proc/cpuinfo, handles missing files.
#  - rpi-update is now gated behind an explicit y/N prompt with a warning
#    (it installs UNRELEASED firmware/kernels and can brick a working Pi).
#  - Added a Debian (non-Kali) branch. The mainline PPA is Ubuntu-only.
#  - Validate codename against the mainline PPA's supported list. Prefer
#    UBUNTU_CODENAME over VERSION_CODENAME so Mint/Pop!_OS/Zorin/KDE neon
#    resolve to their upstream Ubuntu codename.
#  - Falls back to apt full-upgrade when the codename is unsupported by the
#    mainline PPA (EOL releases, very new releases not yet in the PPA).
#  - Auto-downloads base_functions.sh from GitHub if missing.
#  - Kali prompt now defaults to "no" on empty/garbage input rather than
#    exiting with status 1.
#
# Updated: July 2026
#  - Unified terminal output with the repo-standard theme (log_* helpers from
#    base_functions.sh); replaced the old fstring calls.
#
# Updated: 2026-08-09
#  - Adopted the IT Dojo terminal design system: banner/log_phase/log_complete
#    bookends, badge lines instead of emoji, and no `clear` at the top. Clearing
#    the screen destroys the record of whatever the user ran before this.
#
# This script relies on the availability of the base_functions.sh file. If it
# is not found, it will be downloaded from https://github.com/itdojo/qol.

SCRIPT_DIR="$(dirname "$(realpath "$0")")"        # Directory of this script
BASE_FUNCTIONS="${SCRIPT_DIR}/base_functions.sh"  # Path to the base_functions.sh file

BASE_FUNCTIONS_URL="https://raw.githubusercontent.com/itdojo/qol/refs/heads/main/linux/base_functions.sh"

if [ ! -f "$BASE_FUNCTIONS" ]; then
  # log_* is not available yet — this is the fetch that makes it available.
  # Hand-write the same 9-column prefix the helpers emit at QOL_DEPTH=none, so
  # these lines still grep as '^. STOP' alongside every other error.
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

# Source the base_functions.sh file
source "$BASE_FUNCTIONS"
command -v log_phase >/dev/null 2>&1 || {
  printf '%s\n' "▌ STOP   base_functions.sh is outdated (no log_phase)." \
                "▌ STOP   Update it from https://github.com/itdojo/qol." >&2
  exit 1
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Ubuntu codenames currently supported by the cappelikan/ppa mainline tool
# (as of April 2026). Update this list when Ubuntu adds/drops a release.
# https://launchpad.net/~cappelikan/+archive/ubuntu/ppa
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
SUPPORTED_UBUNTU_CODENAMES=("jammy" "noble" "plucky" "questing" "resolute")

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Helper: is this codename in the given list?
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
is_supported_codename() {
  local needle="$1"
  shift
  local hay
  for hay in "$@"; do
    [ "$hay" = "$needle" ] && return 0
  done
  return 1
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Helper: detect Raspberry Pi reliably and echo the model string on stdout.
# Prefers /proc/device-tree/model (canonical on modern 64-bit Pi OS), falls
# back to /proc/cpuinfo "Model" line. Returns non-zero if not a Pi.
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
detect_raspberry_pi() {
  if [ -r /proc/device-tree/model ] && grep -qa "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    tr -d '\0' </proc/device-tree/model
    return 0
  fi
  if [ -r /proc/cpuinfo ] && grep -q "^Model.*Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
    grep "^Model" /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//'
    return 0
  fi
  return 1
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Helper: report whether a kernel update is staged for the next reboot.
# uname -r reflects the RUNNING kernel and does not change without a reboot,
# so we compare it against the newest installed kernel modules directory
# under /usr/lib/modules (which IS updated immediately when a new kernel is
# installed). /boot/vmlinuz-* is used as a fallback.
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
report_kernel_status() {
  local running latest
  running="$(uname -r)"

  if [ -d /usr/lib/modules ]; then
    latest="$(ls -1 /usr/lib/modules 2>/dev/null | sort -V | tail -1)"
  elif compgen -G "/boot/vmlinuz-*" >/dev/null; then
    latest="$(ls -1 /boot/vmlinuz-* 2>/dev/null \
      | sed 's|.*/vmlinuz-||' \
      | sort -V \
      | tail -1)"
  else
    latest=""
  fi

  # REBOOT_NEEDED is read by the completion block to pick its NEXT lines.
  if [ -z "$latest" ]; then
    log_warn "Could not determine the installed kernel version; running kernel is $running."
  elif [ "$running" = "$latest" ]; then
    log_ok "Kernel is already up to date ($running). No reboot needed."
  else
    log_ok "Kernel update staged for next reboot."
    log_info "Running:   $running"
    log_info "Installed: $latest"
    REBOOT_NEEDED="$latest"
  fi
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Pre-flight
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# No `clear` here. An installer that blanks the scrollback has destroyed the
# record of whatever the user ran before it; the banner is the boundary now.
REBOOT_NEEDED=""

banner "KERNEL UPDATER" "linux · pi · kali · debian · ubuntu"

log_phase "PREFLIGHT"
as_root        # Confirm running as root
check_if_linux # Confirm running on Linux

# Ensure needrestart is installed so the user is told what to restart later
if ! command -v needrestart >/dev/null; then
  install_packages needrestart
fi

log_step "Gathering Linux release info..."

if [ -f /etc/os-release ]; then
  source /etc/os-release
  log_info "OS version: $PRETTY_NAME ($VERSION_CODENAME)"
else
  log_err "/etc/os-release not found. Cannot determine distribution."
  exit 1
fi

# Pick the right "apt suite" codename. For Ubuntu derivatives (Mint, Pop!_OS,
# elementary, Zorin, KDE neon, Ubuntu MATE), UBUNTU_CODENAME is the upstream
# Ubuntu release; VERSION_CODENAME is the derivative's own name (e.g. "wilma"
# on Mint 22). The mainline PPA only ships packages keyed to upstream Ubuntu
# codenames, so we prefer UBUNTU_CODENAME when present.
APT_CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

# Detect Raspberry Pi
pi_model=""
if pi_model="$(detect_raspberry_pi)"; then
  log_info "Raspberry Pi detected: ${pi_model}"
fi

# Show currently running kernel
running_kernel="$(uname -r)"
log_info "Currently running kernel: $running_kernel"

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Branch on platform
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
log_phase "KERNEL"
if [ -n "$pi_model" ]; then
  # ---- Raspberry Pi -------------------------------------------------------
  # Standard apt path is the safe default. rpi-update is opt-in.
  export DEBIAN_FRONTEND=noninteractive
  log_step "Performing Raspberry Pi kernel update (apt full-upgrade)..."

  install_packages ca-certificates
  apt -y --fix-broken install
  update_repo
  apt -y full-upgrade
  check_status "Raspberry Pi apt full-upgrade" $?

  log_warn "rpi-update installs UNRELEASED firmware and kernels. It can break a working Pi."
  log_warn "Most users should answer 'n' here."
  # Deliberately NOT ask_confirm: that helper returns yes whenever ASSUME_YES is
  # set, and this script has no --yes flag to document that. A stray ASSUME_YES
  # in the environment must not be what flashes unreleased firmware to a Pi.
  # Borrow ask_confirm's shape — ASK badge, jade caret — not its semantics.
  log_ask "Run rpi-update for bleeding-edge firmware/kernel?"
  printf '    %s❯%s %s[y/N]%s ' "$QOL_PASS" "$QOL_RESET" "$QOL_META" "$QOL_RESET"
  read -r rpi_confirm
  if [[ $rpi_confirm =~ ^[Yy]$ ]]; then
    if ! command -v rpi-update >/dev/null; then
      install_packages rpi-update
    fi
    if ! command -v ntpdate >/dev/null; then
      install_packages ntpdate
    fi
    # Older Pi units have no RTC; rpi-update needs accurate time for SSL.
    ntpdate -u ntp.ubuntu.com || true
    SKIP_WARNING=1 rpi-update
    check_status "rpi-update" $?
  else
    log_ok "Skipping rpi-update (recommended)."
  fi

elif [ "$ID" = "kali" ] || [ "$VERSION_CODENAME" = "kali-rolling" ]; then
  # ---- Kali Linux ---------------------------------------------------------
  log_info "$PRETTY_NAME detected."
  log_info "Kali is a rolling release; updating tracks the latest packaged kernel."
  log_info "That requires apt dist-upgrade + full-upgrade."

  log_ask "Proceed with the upgrade?"
  printf '    %s❯%s %s[y/N]%s ' "$QOL_PASS" "$QOL_RESET" "$QOL_META" "$QOL_RESET"
  read -r confirm
  if [[ ! $confirm =~ ^[Yy]$ ]]; then
    log_ok "Kernel update cancelled at user request."
    exit 0
  fi

  log_step "Updating $PRETTY_NAME to latest kernel..."
  apt -y --fix-broken install
  update_repo
  apt -y dist-upgrade
  apt -y full-upgrade
  check_status "Kali full-upgrade" $?

elif [ "$ID" = "debian" ]; then
  # ---- Debian (non-Kali) --------------------------------------------------
  # The mainline PPA is Ubuntu-only, so on Debian we update via the apt
  # suites the system is already configured for. For a newer kernel than
  # stable ships, the user can enable backports manually.
  log_info "$PRETTY_NAME detected. Updating via apt against the configured suites."
  log_info "For newer kernels, enable backports manually: https://backports.debian.org/Instructions/"

  log_step "Running apt full-upgrade..."
  apt -y --fix-broken install
  update_repo
  apt -y full-upgrade
  check_status "Debian apt full-upgrade" $?

else
  # ---- Ubuntu and Ubuntu derivatives --------------------------------------
  # Covers Ubuntu, Pop!_OS, Linux Mint, Ubuntu MATE/Studio/Kylin/Budgie,
  # elementary OS, Zorin, KDE neon, etc. We use the mainline utility from
  # cappelikan/ppa to install the latest mainline kernel.
  log_info "Not a Raspberry Pi, Kali or Debian installation; treating as Ubuntu / Ubuntu-derivative."
  log_info "Apt suite: $APT_CODENAME"

  if ! is_supported_codename "$APT_CODENAME" "${SUPPORTED_UBUNTU_CODENAMES[@]}"; then
    log_warn "Codename '$APT_CODENAME' is not in the mainline PPA's supported list (${SUPPORTED_UBUNTU_CODENAMES[*]})."
    log_warn "The release is likely too old (EOL) or too new for the PPA. Falling back to apt full-upgrade."

    log_step "Running apt full-upgrade..."
    apt -y --fix-broken install
    update_repo
    apt -y full-upgrade
    check_status "apt full-upgrade" $?
  else
    log_step "Adding mainline kernel update PPA..."
    apt -y --fix-broken install
    if ! command -v add-apt-repository >/dev/null; then
      install_packages software-properties-common
    fi
    add-apt-repository -y ppa:cappelikan/ppa
    check_status "Adding mainline PPA" $?

    log_step "Installing mainline utility..."
    update_repo
    install_packages mainline

    log_step "Installing latest mainline kernel..."
    mainline install-latest
    check_status "mainline install-latest" $?

    apt -y --fix-broken install
  fi
fi

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Report whether a kernel update is staged for next reboot
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
log_phase "VERIFY"
report_kernel_status

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Completion
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
log_complete "KERNEL UPGRADE COMPLETE"
if [ -n "$REBOOT_NEEDED" ]; then
  log_next "Reboot to load the new $REBOOT_NEEDED kernel:  sudo reboot"
else
  log_next "Nothing to do — the running kernel is already the newest installed."
fi
echo
