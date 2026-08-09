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
#  - Added the ACTIVATE phase. Installing a kernel never makes it the running
#    kernel; only a reboot does. The script now offers to point the bootloader
#    at the new kernel and reboot into it, and prints how to switch later when
#    the offer is declined.
#  - ACTIVATE now refuses to boot a kernel that cannot boot. The phase shipped
#    trusting report_kernel_status, which reads /usr/lib/modules — a directory
#    the linux-modules package fills before linux-image has done anything. A
#    failed install left vmlinuz in /boot with no initramfs beside it, the run
#    offered to reboot into it, and the reboot panicked with "VFS: Unable to
#    mount root fs on unknown-block(0,0)". The offer is now gated on the
#    vmlinuz/initrd pair existing and on dpkg having no unconfigured kernel
#    packages, and a run that installed a broken kernel exits non-zero.
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
# Helper: can the named kernel actually boot?
#
# report_kernel_status names the newest kernel from /usr/lib/modules, which the
# linux-modules package populates. That says nothing about /boot. When a kernel
# install fails partway — modules unpacked, linux-image postinst dead before
# update-initramfs ran — /usr/lib/modules names a kernel that has no initramfs,
# and update-grub happily writes it a menuentry with no initrd line. Booting
# that entry panics: "VFS: Unable to mount root fs on unknown-block(0,0)".
#
# Sets KERNEL_BOOT_PROBLEM to the reason on failure. Returns 0 when the kernel
# looks bootable OR when this system does not use the vmlinuz/initrd layout at
# all — Raspberry Pi OS boots kernel8.img from firmware and has no initramfs to
# find, so there is nothing here to veto.
#
# BOOT_DIR is overridable so the test suite can point this at a fixture tree.
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
kernel_boot_files_ok() {
  local kver="$1" boot="${BOOT_DIR:-/boot}"
  KERNEL_BOOT_PROBLEM=""

  compgen -G "$boot/vmlinuz-*" >/dev/null 2>&1 || return 0

  if [ ! -f "$boot/vmlinuz-$kver" ]; then
    KERNEL_BOOT_PROBLEM="$boot/vmlinuz-$kver does not exist"
    return 1
  fi
  if [ ! -s "$boot/initrd.img-$kver" ]; then
    KERNEL_BOOT_PROBLEM="$boot/initrd.img-$kver is missing or empty (no initramfs was built)"
    return 1
  fi
  return 0
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Helper: list kernel packages dpkg wants installed but could not finish.
# "iF"/"iU"/"iH" mean unpacked-but-not-configured: the postinst that builds the
# initramfs and runs update-grub never completed. "ii" is fine and "rc"/"un" are
# packages that are simply gone, so only a want-install/status-broken pair counts.
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
half_installed_kernel_packages() {
  command -v dpkg-query >/dev/null 2>&1 || return 0
  dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' \
    'linux-image*' 'linux-modules*' 2>/dev/null \
    | awk '$1 ~ /^i/ && $1 != "ii" { print $2 }'
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Helper: echo the path to grub.cfg, or nothing when this system has no GRUB.
# Raspberry Pi OS boots straight from the firmware and has no bootloader menu
# to configure, so "no GRUB" is a normal answer, not an error.
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
find_grub_cfg() {
  local candidate
  for candidate in /boot/grub/grub.cfg /boot/grub2/grub.cfg; do
    if [ -r "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Helper: pull the id out of a grub.cfg `menuentry`/`submenu` line.
#   menuentry 'Ubuntu, 6.14.0-27' ... $menuentry_id_option 'gnulinux-...' {
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
grub_id_from_line() {
  printf '%s\n' "$1" | sed -n "s/.*menuentry_id_option '\([^']*\)'.*/\1/p"
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Helper: echo the grub-set-default argument for a kernel version.
# Every kernel gets an "-advanced-" entry inside the "Advanced options for ..."
# submenu, and grub-set-default addresses a nested entry as "submenu>entry".
# The submenu id is remembered until its closing brace at column 0; the inner
# entries close with an indented brace, so only the submenu itself clears it.
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
grub_entry_for_kernel() {
  local kver="$1" cfg="$2"
  local submenu="" line id

  while IFS= read -r line; do
    case "$line" in
      '}'*)
        submenu=""
        ;;
      *submenu*menuentry_id_option*)
        submenu="$(grub_id_from_line "$line")"
        ;;
      *menuentry*menuentry_id_option*)
        id="$(grub_id_from_line "$line")"
        case "$id" in
          *"$kver"-advanced-*)
            if [ -n "$submenu" ]; then
              printf '%s>%s' "$submenu" "$id"
            else
              printf '%s' "$id"
            fi
            return 0
            ;;
        esac
        ;;
    esac
  done < "$cfg"

  return 1
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Helper: make the named kernel the one the bootloader picks by default.
#
# GRUB_DEFAULT=0 already boots the newest installed kernel — 10_linux sorts the
# menu by version — so the common case needs no edit at all. Only a system
# pinned to some other entry gets /etc/default/grub rewritten, and then only to
# GRUB_DEFAULT=saved so grub-set-default has something to write to.
#
# Returns 0 when the next boot will use $kver, 1 when it will not.
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
set_default_kernel() {
  local kver="$1"
  local cfg current entry bak tmp rc

  # Never point a bootloader at a kernel that cannot boot. The caller checks
  # this too and gives a better message; this is the backstop for any other
  # path into here.
  if ! kernel_boot_files_ok "$kver"; then
    log_err "$kver is not bootable: $KERNEL_BOOT_PROBLEM"
    return 1
  fi

  if ! cfg="$(find_grub_cfg)"; then
    log_info "No GRUB menu on this system; it boots the newest installed kernel on its own."
    log_info "A reboot is all that is needed to run $kver."
    return 0
  fi

  current="0"
  if [ -r /etc/default/grub ]; then
    # \042 \047 = the double and single quotes GRUB_DEFAULT's value may be wrapped in.
    current="$(grep -m1 '^GRUB_DEFAULT=' /etc/default/grub | cut -d= -f2- | tr -d '\042\047')"
    [ -z "$current" ] && current="0"
  fi

  if [ "$current" = "0" ]; then
    log_info "GRUB_DEFAULT=0 already selects the newest installed kernel. Leaving it alone."
  elif [ "$current" != "saved" ]; then
    log_step "Repointing GRUB from entry '$current' to the newest kernel..."
    if ! ls /etc/default/grub.prekernelupdate.*.bak >/dev/null 2>&1; then
      bak="/etc/default/grub.prekernelupdate.$(date +%Y%m%d-%H%M%S).bak"
      cp /etc/default/grub "$bak"
      log_info "Backed up /etc/default/grub to $bak"
    fi
    # cat-over, not mv: mv from mktemp would tighten this 0644 file to 0600.
    tmp="$(mktemp)"
    sed 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub >"$tmp" \
      && cat "$tmp" >/etc/default/grub
    rc=$?
    rm -f "$tmp"
    check_status "Setting GRUB_DEFAULT=saved" "$rc" || return 1
    current="saved"
  fi

  log_step "Regenerating the GRUB menu..."
  if command -v update-grub >/dev/null 2>&1; then
    update-grub
    rc=$?
  else
    grub-mkconfig -o "$cfg"
    rc=$?
  fi
  check_status "GRUB menu regeneration" "$rc" || return 1

  # GRUB_DEFAULT=0 needs no entry id — index 0 is the newest kernel.
  [ "$current" = "0" ] && return 0

  if ! entry="$(grub_entry_for_kernel "$kver" "$cfg")"; then
    log_warn "No GRUB entry found for $kver. Leaving the default boot entry alone."
    log_warn "Pick it by hand at boot: hold Shift (BIOS) or Esc (UEFI), then Advanced options."
    return 1
  fi

  if command -v grub-set-default >/dev/null 2>&1; then
    grub-set-default "$entry"
    rc=$?
  elif command -v grub2-set-default >/dev/null 2>&1; then
    grub2-set-default "$entry"
    rc=$?
  else
    log_warn "grub-set-default not found. Leaving the default boot entry alone."
    return 1
  fi
  check_status "Making $kver the default boot entry" "$rc" || return 1

  log_info "Default boot entry: $entry"
  return 0
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Helper: reboot, after a countdown long enough to change your mind.
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
reboot_now() {
  local secs="${1:-10}"
  log_warn "Rebooting in ${secs}s. Press Ctrl-C to cancel and stay on $running_kernel."
  while [ "$secs" -gt 0 ]; do
    printf '\r    %s❯%s rebooting in %2ds ' "$QOL_PASS" "$QOL_RESET" "$secs"
    sleep 1
    secs=$(( secs - 1 ))
  done
  printf '\n'
  reboot
}

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Pre-flight
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# No `clear` here. An installer that blanks the scrollback has destroyed the
# record of whatever the user ran before it; the banner is the boundary now.
REBOOT_NEEDED=""
ACTIVATE_KERNEL=""       # set once the bootloader points at the new kernel and a reboot is owed
ACTIVATE_BLOCKED=""      # set when the new kernel cannot boot, so the offer is withheld
KERNEL_INSTALL_FAILED="" # set when the install step itself reported failure
KERNEL_BOOT_PROBLEM=""   # why the new kernel cannot boot, set by kernel_boot_files_ok

banner "KERNEL UPDATER" "linux · pi · kali · debian · ubuntu"

log_phase "PREFLIGHT"
as_root        # Confirm running as root
check_if_linux # Confirm running on Linux

# Ensure needrestart is installed so the user is told what to restart later
if ! command -v needrestart >/dev/null; then
  install_packages needrestart
fi

log_step "Gathering Linux release info..."

# base_functions.sh already read /etc/os-release into OS_*. Sourcing it here
# too would put the generic names (VERSION, ID, ...) back in this shell, which
# is what collides with a script's own constants.
if [ -n "$OS_ID" ]; then
  log_info "OS version: $OS_PRETTY_NAME ($OS_CODENAME)"
else
  log_err "/etc/os-release not found or unreadable. Cannot determine distribution."
  exit 1
fi

# Pick the right "apt suite" codename. For Ubuntu derivatives (Mint, Pop!_OS,
# elementary, Zorin, KDE neon, Ubuntu MATE), UBUNTU_CODENAME is the upstream
# Ubuntu release; VERSION_CODENAME is the derivative's own name (e.g. "wilma"
# on Mint 22). The mainline PPA only ships packages keyed to upstream Ubuntu
# codenames, so we prefer UBUNTU_CODENAME when present.
APT_CODENAME="${OS_UBUNTU_CODENAME:-$OS_CODENAME}"

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

elif [ "$OS_ID" = "kali" ] || [ "$OS_CODENAME" = "kali-rolling" ]; then
  # ---- Kali Linux ---------------------------------------------------------
  log_info "$OS_PRETTY_NAME detected."
  log_info "Kali is a rolling release; updating tracks the latest packaged kernel."
  log_info "That requires apt dist-upgrade + full-upgrade."

  log_ask "Proceed with the upgrade?"
  printf '    %s❯%s %s[y/N]%s ' "$QOL_PASS" "$QOL_RESET" "$QOL_META" "$QOL_RESET"
  read -r confirm
  if [[ ! $confirm =~ ^[Yy]$ ]]; then
    log_ok "Kernel update cancelled at user request."
    exit 0
  fi

  log_step "Updating $OS_PRETTY_NAME to latest kernel..."
  apt -y --fix-broken install
  update_repo
  apt -y dist-upgrade
  apt -y full-upgrade
  check_status "Kali full-upgrade" $?

elif [ "$OS_ID" = "debian" ]; then
  # ---- Debian (non-Kali) --------------------------------------------------
  # The mainline PPA is Ubuntu-only, so on Debian we update via the apt
  # suites the system is already configured for. For a newer kernel than
  # stable ships, the user can enable backports manually.
  log_info "$OS_PRETTY_NAME detected. Updating via apt against the configured suites."
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
    mainline_rc=$?
    check_status "mainline install-latest" "$mainline_rc"

    # --fix-broken may still rescue a half-finished install, so this is a
    # warning rather than the decision. What the ACTIVATE gate reads off /boot
    # afterwards is what decides whether the new kernel is safe to boot.
    apt -y --fix-broken install
    if [ "$mainline_rc" -ne 0 ]; then
      KERNEL_INSTALL_FAILED=1
      log_warn "The mainline install did not finish cleanly. Verifying what landed in /boot."
    fi
  fi
fi

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Report whether a kernel update is staged for next reboot
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
log_phase "VERIFY"
report_kernel_status

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Activate — installing a kernel does not run it. Only a reboot does.
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
if [ -n "$REBOOT_NEEDED" ]; then
  log_phase "ACTIVATE"
  log_info "$REBOOT_NEEDED is installed but $running_kernel is still running."

  # Gate the offer on the new kernel being able to boot. A half-finished install
  # leaves /usr/lib/modules naming a kernel that /boot cannot start, and the
  # reboot lands on a panic instead of a login prompt.
  activate_block=""
  if ! kernel_boot_files_ok "$REBOOT_NEEDED"; then
    activate_block="$KERNEL_BOOT_PROBLEM"
  else
    broken_kernel_pkgs="$(half_installed_kernel_packages)"
    if [ -n "$broken_kernel_pkgs" ]; then
      activate_block="dpkg left these kernel packages unconfigured: $(printf '%s' "$broken_kernel_pkgs" | tr '\n' ' ')"
    fi
  fi

  if [ -n "$activate_block" ]; then
    ACTIVATE_BLOCKED=1
    log_err "Not offering to boot $REBOOT_NEEDED — $activate_block"
    log_warn "Booting a kernel with no initramfs panics with:"
    log_warn "  VFS: Unable to mount root fs on unknown-block(0,0)"
    log_warn "Staying on $running_kernel, which still boots."
  else
    log_warn "Rebooting closes every open program and drops any SSH session to this host."

    # Deliberately NOT ask_confirm: that helper returns yes whenever ASSUME_YES is
    # set, and this script has no --yes flag to document that. A stray ASSUME_YES
    # in the environment must not be what reboots a machine out from under someone.
    # Borrow ask_confirm's shape — ASK badge, jade caret — not its semantics.
    log_ask "Boot into $REBOOT_NEEDED now (set it as the default boot entry, then reboot)?"
    printf '    %s❯%s %s[y/N]%s ' "$QOL_PASS" "$QOL_RESET" "$QOL_META" "$QOL_RESET"
    read -r activate_confirm
    if [[ $activate_confirm =~ ^[Yy]$ ]]; then
      if set_default_kernel "$REBOOT_NEEDED"; then
        ACTIVATE_KERNEL=1
      else
        log_warn "Could not guarantee $REBOOT_NEEDED is the default. Not rebooting."
      fi
    else
      log_ok "Staying on $running_kernel for now."
    fi
  fi
fi

# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Completion
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
if [ -n "$ACTIVATE_BLOCKED" ] || [ -n "$KERNEL_INSTALL_FAILED" ]; then
  log_complete "KERNEL UPGRADE INCOMPLETE"
else
  log_complete "KERNEL UPGRADE COMPLETE"
fi
if [ -n "$ACTIVATE_BLOCKED" ]; then
  log_next "Repair the install, then rerun this script:"
  log_next "  sudo dpkg --configure -a"
  log_next "  sudo apt -y --fix-broken install"
  log_next "If it still will not configure, remove the broken kernel and stay on $running_kernel:"
  log_next "  sudo apt -y purge 'linux-image*$REBOOT_NEEDED*' 'linux-modules*$REBOOT_NEEDED*' && sudo update-grub"
elif [ -n "$ACTIVATE_KERNEL" ]; then
  log_next "Rebooting into $REBOOT_NEEDED now."
  log_next "If it misbehaves, pick the old kernel at boot: hold Shift (BIOS) or Esc (UEFI), then Advanced options."
elif [ -n "$REBOOT_NEEDED" ]; then
  log_next "Reboot when you are ready to run $REBOOT_NEEDED:  sudo reboot"
  if find_grub_cfg >/dev/null; then
    log_next "To choose it just once, hold Shift (BIOS) or Esc (UEFI) at boot and use Advanced options."
    log_next "To make it the default, rerun this script and answer y at the ACTIVATE prompt."
  else
    log_next "This system boots the newest installed kernel automatically; nothing else to set."
  fi
else
  log_next "Nothing to do — the running kernel is already the newest installed."
fi
echo

if [ -n "$ACTIVATE_KERNEL" ]; then
  reboot_now 10
fi

# A run that installed a broken kernel is not a successful run, even though the
# machine it ran on is still fine. Exit non-zero so a caller can tell.
if [ -n "$ACTIVATE_BLOCKED" ] || [ -n "$KERNEL_INSTALL_FAILED" ]; then
  exit 1
fi
exit 0
