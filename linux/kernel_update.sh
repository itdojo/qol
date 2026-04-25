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
# This script relies on the availability of the base_functions.sh file. If it
# is not found, it will be downloaded from https://github.com/itdojo/qol.
 
SCRIPT_DIR="$(dirname "$(realpath "$0")")"        # Directory of this script
BASE_FUNCTIONS="${SCRIPT_DIR}/base_functions.sh"  # Path to the base_functions.sh file
 
if [ ! -f "$BASE_FUNCTIONS" ]; then
  echo "❌  base_functions.sh not found. Downloading from GitHub."
  wget https://raw.githubusercontent.com/itdojo/qol/refs/heads/main/linux/base_functions.sh -O "$BASE_FUNCTIONS" ||
    {
      echo "❌  Failed to download base_functions.sh"
      exit 1
    }
fi
 
# Source the base_functions.sh file
source "$BASE_FUNCTIONS"
 
# ----------------------------------------------------------------------------
# Ubuntu codenames currently supported by the cappelikan/ppa mainline tool
# (as of April 2026). Update this list when Ubuntu adds/drops a release.
# https://launchpad.net/~cappelikan/+archive/ubuntu/ppa
# ----------------------------------------------------------------------------
SUPPORTED_UBUNTU_CODENAMES=("jammy" "noble" "plucky" "questing" "resolute")
 
# ----------------------------------------------------------------------------
# Helper: is this codename in the given list?
# ----------------------------------------------------------------------------
is_supported_codename() {
  local needle="$1"
  shift
  local hay
  for hay in "$@"; do
    [ "$hay" = "$needle" ] && return 0
  done
  return 1
}
 
# ----------------------------------------------------------------------------
# Helper: detect Raspberry Pi reliably and echo the model string on stdout.
# Prefers /proc/device-tree/model (canonical on modern 64-bit Pi OS), falls
# back to /proc/cpuinfo "Model" line. Returns non-zero if not a Pi.
# ----------------------------------------------------------------------------
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
 
# ----------------------------------------------------------------------------
# Helper: report whether a kernel update is staged for the next reboot.
# uname -r reflects the RUNNING kernel and does not change without a reboot,
# so we compare it against the newest installed kernel modules directory
# under /usr/lib/modules (which IS updated immediately when a new kernel is
# installed). /boot/vmlinuz-* is used as a fallback.
# ----------------------------------------------------------------------------
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
 
  echo ""
  if [ -z "$latest" ]; then
    fstring "Could not determine installed kernel version." "warning"
    printf "%s\n" "Running kernel: $running"
  elif [ "$running" = "$latest" ]; then
    fstring "Kernel is already up to date ($running). No reboot needed." "normal" "bold" "green"
  else
    fstring "Kernel update staged for next reboot." "normal" "bold" "green"
    printf "    Running:   %s\n" "$running"
    printf "    Installed: %s\n" "$latest"
    echo ""
    fstring "Reboot to load the new $latest kernel." "normal" "bold" "red"
  fi
  echo ""
}
 
# ----------------------------------------------------------------------------
# Pre-flight
# ----------------------------------------------------------------------------
clear                       # Clear the screen
as_root                     # Confirm running as root
check_if_linux              # Confirm running on Linux
trap handle_ctrl_c SIGINT   # Gracefully handle CTRL-C
 
fstring "🐧  KERNEL UPDATER FOR LINUX - v.2026-04" "title"
printline dentistry
 
# Ensure needrestart is installed so the user is told what to restart later
if ! command -v needrestart >/dev/null; then
  fstring "Installing needrestart package... " "section"
  install_packages needrestart
  check_status "needrestart installation" $?
fi
 
# ----------------------------------------------------------------------------
# Detect distro
# ----------------------------------------------------------------------------
fstring "Gathering Linux Release Info... " "section"
 
if [ -f /etc/os-release ]; then
  source /etc/os-release
  printf "%s\n" "OS Version: $PRETTY_NAME ($VERSION_CODENAME)"
else
  echo "❌  /etc/os-release not found. Cannot determine distribution. Exiting."
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
  printf "%s\n" "🥧 I am a $(fstring "Raspberry Pi" "normal" "bold" "red"): ${pi_model}"
fi
 
# Show currently running kernel
running_kernel="$(uname -r)"
printf "%s\n" "🧬  Currently running kernel: $(fstring "$running_kernel" "normal" "bold" "green")"
 
# ----------------------------------------------------------------------------
# Branch on platform
# ----------------------------------------------------------------------------
if [ -n "$pi_model" ]; then
  # ---- Raspberry Pi -------------------------------------------------------
  # Standard apt path is the safe default. rpi-update is opt-in.
  export DEBIAN_FRONTEND=noninteractive
  fstring "Performing Raspberry Pi kernel update (apt full-upgrade)... " "section"
 
  install_packages ca-certificates
  apt -y --fix-broken install
  update_repo
  apt -y full-upgrade
  check_status "Raspberry Pi apt full-upgrade" $?
 
  echo ""
  fstring "rpi-update installs UNRELEASED firmware and kernels." "warning"
  fstring "It can break a working Pi. Most users should answer 'n' here." "warning"
  read -r -p "Run rpi-update for bleeding-edge firmware/kernel? [y/N]: " rpi_confirm
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
    printf "%s\n" "Skipping rpi-update (recommended)."
  fi
 
elif [ "$ID" = "kali" ] || [ "$VERSION_CODENAME" = "kali-rolling" ]; then
  # ---- Kali Linux ---------------------------------------------------------
  printf "%s\n" "👾  I am $(fstring "$PRETTY_NAME" "normal" "bold" "blue")."
  printf "%s\n" "    $(fstring "Kali" "normal" "normal" "blue") is a rolling release; updating tracks the latest packaged kernel."
  printf "%s\n" "    This requires apt dist-upgrade + full-upgrade."
 
  read -r -p "Proceed with the upgrade? [y/N]: " confirm
  if [[ ! $confirm =~ ^[Yy]$ ]]; then
    printf "Kernel update cancelled.\n"
    exit 0
  fi
 
  fstring "Updating $PRETTY_NAME to latest kernel... " "section"
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
  printf "%s\n" "ℹ️   I am $(fstring "$PRETTY_NAME" "normal" "bold" "blue")."
  printf "%s\n" "    Updating via apt against the configured suites."
  printf "%s\n" "    For newer kernels, consider enabling backports manually:"
  printf "%s\n" "        https://backports.debian.org/Instructions/"
 
  fstring "Running apt full-upgrade... " "section"
  apt -y --fix-broken install
  update_repo
  apt -y full-upgrade
  check_status "Debian apt full-upgrade" $?
 
else
  # ---- Ubuntu and Ubuntu derivatives --------------------------------------
  # Covers Ubuntu, Pop!_OS, Linux Mint, Ubuntu MATE/Studio/Kylin/Budgie,
  # elementary OS, Zorin, KDE neon, etc. We use the mainline utility from
  # cappelikan/ppa to install the latest mainline kernel.
  printf "%s\n" "ℹ️   This is not a $(fstring "Raspberry Pi" "normal" "normal" "red"), $(fstring "Kali" "normal" "normal" "blue") or $(fstring "Debian" "normal" "normal" "blue") installation."
  printf "%s\n" "    Treating as Ubuntu / Ubuntu-derivative. Apt suite: $(fstring "$APT_CODENAME" "normal" "bold" "green")"
 
  if ! is_supported_codename "$APT_CODENAME" "${SUPPORTED_UBUNTU_CODENAMES[@]}"; then
    printf "⚠️   Codename '%s' is not in the mainline PPA's supported list (%s).\n" \
      "$APT_CODENAME" "${SUPPORTED_UBUNTU_CODENAMES[*]}"
    printf "    This usually means the release is too old (EOL) or too new for the PPA.\n"
    printf "    Falling back to apt full-upgrade against the configured suites.\n"
 
    fstring "Running apt full-upgrade... " "section"
    apt -y --fix-broken install
    update_repo
    apt -y full-upgrade
    check_status "apt full-upgrade" $?
  else
    fstring "Adding mainline kernel update PPA... " "section"
    apt -y --fix-broken install
    if ! command -v add-apt-repository >/dev/null; then
      fstring "Adding add-apt-repository utility... " "section"
      install_packages software-properties-common
      check_status "software-properties-common installation" $?
    fi
    add-apt-repository -y ppa:cappelikan/ppa
    check_status "Adding mainline PPA" $?
 
    fstring "Installing mainline utility... " "section"
    update_repo
    install_packages mainline
    check_status "mainline installation" $?
 
    fstring "Installing latest mainline kernel... " "section"
    mainline install-latest
    check_status "mainline install-latest" $?
 
    apt -y --fix-broken install
  fi
fi
 
# ----------------------------------------------------------------------------
# Report whether a kernel update is staged for next reboot
# ----------------------------------------------------------------------------
report_kernel_status
 
# ----------------------------------------------------------------------------
# Completion
# ----------------------------------------------------------------------------
fstring "🏁  KERNEL UPGRADE COMPLETE  🏁" "title"
printline dentistry
echo ""
 