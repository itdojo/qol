#!/bin/bash

# This script installs Docker on a Linux system. It also adds the current user to the docker group.
# It has been successfully tested on Ubuntu, Pop!_OS, Kali, Ubuntu MATE, and Raspberry Pi OS.
#
# Updated: May 2026
# - Added Ubuntu 26.04 LTS (Resolute) to Docker's supported codename list and
#   dropped plucky (25.04, EOL since January 2026).
# - Added support for Ubuntu 25.10 (Questing Quokka) and 25.04 (Plucky Puffin)
# - Added explicit codename validation against Docker's supported Ubuntu releases
#   (jammy 22.04, noble 24.04, questing 25.10, resolute 26.04)
# - Added native Debian 12 (bookworm) / 13 (trixie) support (previously only Kali)
# - Fixed Linux Mint compatibility by using ${UBUNTU_CODENAME:-$VERSION_CODENAME}
#   (Mint sets UBUNTU_CODENAME=noble/jammy even when VERSION_CODENAME is wilma/etc.)
# - Removes conflicting distro packages (docker.io, podman-docker, etc.) before install
# - Switched GPG key to /etc/apt/keyrings/docker.asc per current Docker docs
# - Hardened: pipefail on key download, SUDO_USER guard, fall-through fix in
#   the "already installed" branch (return 0 only worked when sourced)
# - Added post-install check (docker run hello-world)
#
# Updated: July 2026
# - Unified terminal output with the repo-standard theme (log_* helpers from
#   base_functions.sh); replaced the old fstring calls.
# - Root check now happens before any prompts; 'q' at the uninstall prompt
#   aborts the installer instead of falling through.
# - Verify the daemon actually STARTS. `systemctl enable --now` (and
#   get.docker.com) can return 0 while dockerd dies immediately afterward, so
#   every install path now calls enable_and_start_docker(), which trusts
#   `systemctl is-active` (not $?), and on failure dumps the daemon log and
#   exits non-zero instead of reporting SUCCESS over a dead daemon.
# - Load and persist the netfilter kernel modules Docker's bridge network
#   needs (ensure_docker_kernel_modules): modprobe the required set, write
#   /etc/modules-load.d/docker.conf so they survive reboot, and on a stock
#   kernel install linux-modules-extra-$(uname -r) when any are missing.
#   Fixes dockerd dying on "MASQUERADE/addrtype ... missing kernel module?".
# - Auto-select the nftables firewall backend on kernels that lack the legacy
#   xt_MASQUERADE target but ship native nft masquerade (e.g. Gateworks Venice
#   and some VPS images). ensure_docker_firewall_backend() writes
#   "firewall-backend": "nftables" to /etc/docker/daemon.json (Docker >= 29)
#   instead of letting the daemon fail. No-op when xt_MASQUERADE is available.
#
# This script relies on the availability of the base_functions.sh file. If it is not found, the script will exit.
# The base_functions.sh file should be available in the same directory as this script.
# If not, you can get it from https://github.com/itdojo/qol.

SCRIPT_DIR="$(dirname "$(realpath "$0")")"       # Get the directory of the script
BASE_FUNCTIONS="${SCRIPT_DIR}/base_functions.sh" # Path to the base_functions.sh file

BASE_FUNCTIONS_URL="https://raw.githubusercontent.com/itdojo/qol/refs/heads/main/linux/base_functions.sh"

if [ ! -f "$BASE_FUNCTIONS" ]; then
  echo "base_functions.sh not found. Downloading from GitHub..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$BASE_FUNCTIONS_URL" -o "$BASE_FUNCTIONS"
  else
    wget -q "$BASE_FUNCTIONS_URL" -O "$BASE_FUNCTIONS"
  fi || { echo "❌  Failed to download base_functions.sh"; exit 1; }
fi

# Source the base_functions.sh file
source "$BASE_FUNCTIONS"
command -v log_step >/dev/null 2>&1 \
  || { echo "❌  base_functions.sh is outdated. Update it from https://github.com/itdojo/qol."; exit 1; }

# ----------------------------------------------------------------------------
# Docker's officially supported Ubuntu codenames (as of May 2026).
# Update this list when Docker adds/drops a release.
# https://docs.docker.com/engine/install/ubuntu/
# ----------------------------------------------------------------------------
SUPPORTED_UBUNTU_CODENAMES=("jammy" "noble" "questing" "resolute")

# Debian releases supported by Docker's repo (download.docker.com/linux/debian).
SUPPORTED_DEBIAN_CODENAMES=("bookworm" "trixie")

# Codename to use for Kali (rolling, tracks Debian testing/stable).
KALI_DEBIAN_CODENAME="trixie"

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
# Helper: remove distro-provided Docker packages that conflict with docker-ce.
# Docker's docs explicitly recommend this on Ubuntu 24.04+ and Debian 12+.
# ----------------------------------------------------------------------------
remove_conflicting_packages() {
  log_step "Removing conflicting distro Docker packages..."
  local pkgs=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc)
  # apt-get remove only removes what's installed; missing packages don't error.
  apt-get remove -y "${pkgs[@]}" 2>/dev/null || true
  echo "Conflicting package cleanup done."
}

# ----------------------------------------------------------------------------
# Helper: post-install check.
# Returns 0 on success, non-zero on failure (but does NOT exit the script).
# ----------------------------------------------------------------------------
docker_smoke_test() {
  log_step "Running Docker smoke test (hello-world)..."
  if docker run --rm hello-world >/dev/null 2>&1; then
    log_ok "Smoke test passed - Docker is working."
    return 0
  else
    log_warn "Smoke test failed. Docker installed but couldn't run hello-world."
    printf "    Check 'systemctl status docker' and 'journalctl -u docker'.\n"
    return 1
  fi
}

# ----------------------------------------------------------------------------
# Helper: make sure the kernel modules Docker's default bridge network needs
# are loaded, and persist them across reboots.
#
# On stock desktop/server kernels these autoload on demand, but on minimal or
# vendor kernels (VPS, appliance/gateway images) the netfilter NAT extensions
# are not present, and dockerd then dies creating docker0 with errors like
# "MASQUERADE ... missing kernel module?" / "Couldn't load match `addrtype'".
#
# Strategy: try to load each module; anything that is already loaded or built
# into the kernel is fine. Whatever genuinely cannot be loaded is collected and,
# if we're on a stock kernel, we try the linux-modules-extra package that ships
# them. This never exits on its own — the authoritative pass/fail is the
# is-active check in enable_and_start_docker().
# ----------------------------------------------------------------------------
DOCKER_KERNEL_MODULES=(overlay br_netfilter nf_conntrack nf_nat nf_tables
                       nft_compat nft_chain_nat xt_conntrack xt_addrtype
                       xt_MASQUERADE xt_nat iptable_nat iptable_filter ip_tables)

ensure_docker_kernel_modules() {
  # Only meaningful where modprobe exists (skip gracefully otherwise).
  command -v modprobe >/dev/null 2>&1 || return 0

  log_step "Ensuring Docker's kernel modules are available..."
  local m missing=()
  for m in "${DOCKER_KERNEL_MODULES[@]}"; do
    # Already loaded, loadable, or built-in ("(builtin)" via modinfo) → fine.
    lsmod 2>/dev/null | grep -qw "$m" && continue
    modprobe "$m" 2>/dev/null && continue
    modinfo "$m" >/dev/null 2>&1 && continue
    missing+=("$m")
  done

  # Persist across reboots so a future boot doesn't regress to a dead daemon.
  printf '# Loaded by docker_install.sh for Docker bridge networking.\n%s\n' \
    "$(printf '%s\n' "${DOCKER_KERNEL_MODULES[@]}")" \
    > /etc/modules-load.d/docker.conf 2>/dev/null || true

  [ ${#missing[@]} -eq 0 ] && { echo "All required modules present."; return 0; }

  log_warn "Kernel modules missing for the running kernel ($(uname -r)): ${missing[*]}"
  printf "    Docker's default (iptables) bridge network needs these.\n"
  # On a stock kernel the extra package supplies them; on a custom/appliance
  # kernel (VPS, Gateworks, etc.) it won't exist. Non-fatal either way — if
  # xt_MASQUERADE is the gap, ensure_docker_firewall_backend() may still get
  # Docker running via the native nftables backend.
  if install_packages "linux-modules-extra-$(uname -r)"; then
    for m in "${missing[@]}"; do modprobe "$m" 2>/dev/null || true; done
  else
    printf "ℹ️   No linux-modules-extra-%s package (custom/minimal kernel).\n" "$(uname -r)"
    printf "    Will try the nftables firewall backend next if applicable.\n"
  fi
}

# ----------------------------------------------------------------------------
# Helper: merge "firewall-backend": "nftables" into /etc/docker/daemon.json
# without clobbering an existing config. Returns:
#   0 = key is set (written now or already present)
#   2 = a daemon.json exists that we couldn't safely merge (no jq)
# ----------------------------------------------------------------------------
enable_nftables_backend() {
  local f=/etc/docker/daemon.json
  mkdir -p /etc/docker
  if [ ! -s "$f" ]; then
    printf '{\n  "firewall-backend": "nftables"\n}\n' > "$f"
    return 0
  fi
  grep -q '"firewall-backend"' "$f" && return 0   # respect an existing setting
  if command -v jq >/dev/null 2>&1; then
    local merged
    merged="$(jq '. + {"firewall-backend":"nftables"}' "$f" 2>/dev/null)" \
      && printf '%s\n' "$merged" > "$f" && return 0
  fi
  return 2
}

# ----------------------------------------------------------------------------
# Helper: pick Docker's firewall backend. Docker's default path uses the legacy
# iptables MASQUERADE target (xt_MASQUERADE). Some vendor/embedded kernels
# (e.g. Gateworks Venice, some VPS images) omit CONFIG_NETFILTER_XT_TARGET_
# MASQUERADE while still shipping native nftables NAT (CONFIG_NF_NAT_MASQUERADE,
# nft_masq). Docker >= 29 can use those directly via "firewall-backend":
# "nftables", so on such a kernel we switch backends instead of dying.
# Only acts when xt_MASQUERADE is genuinely unavailable; otherwise no-op.
# ----------------------------------------------------------------------------
ensure_docker_firewall_backend() {
  command -v docker >/dev/null 2>&1 || return 0
  command -v modprobe >/dev/null 2>&1 || return 0

  # xt_MASQUERADE present (as module or built-in)? Then the default backend is
  # fine — don't touch daemon.json.
  modprobe xt_MASQUERADE 2>/dev/null && return 0

  local dver
  dver=$(docker --version 2>/dev/null | grep -oE '[0-9]+' | head -1)
  if [ "${dver:-0}" -ge 29 ] && modprobe nft_masq 2>/dev/null; then
    log_step "xt_MASQUERADE absent; switching Docker to the nftables backend..."
    if enable_nftables_backend; then
      log_ok "Set \"firewall-backend\": \"nftables\" in /etc/docker/daemon.json."
      printf "    This kernel lacks xt_MASQUERADE but has native nft masquerade,\n"
      printf "    so Docker runs its bridge NAT via the 'ip docker-bridges' table.\n"
    else
      log_warn "Docker needs the nftables backend here, but /etc/docker/daemon.json"
      printf "    already exists and jq isn't installed to merge it safely.\n"
      printf "    Add this key manually, then restart docker:\n"
      printf '        "firewall-backend": "nftables"\n'
    fi
  else
    log_warn "xt_MASQUERADE is missing and the nftables backend isn't available"
    printf "    (needs Docker >= 29 and kernel nft masq support). Docker's bridge\n"
    printf "    network can't start until the kernel provides one of them.\n"
  fi
}

# ----------------------------------------------------------------------------
# Helper: enable + start docker.service, then VERIFY the daemon is actually
# running. `systemctl enable --now` (and get.docker.com) can return 0 while the
# daemon dies immediately afterward, so we trust `is-active`, not $?. A dead
# daemon is a failed install — this exits the script and dumps the daemon log
# so the real cause (usually a kernel/netfilter or storage-driver issue, not a
# packaging problem) is visible instead of buried under a green SUCCESS.
# ----------------------------------------------------------------------------
enable_and_start_docker() {
  ensure_docker_kernel_modules
  ensure_docker_firewall_backend
  log_step "Enabling and starting the Docker service..."
  # Clear any restart-limit backoff from a previous failed attempt so this
  # start is actually tried rather than refused ("start request repeated...").
  systemctl reset-failed docker.service docker.socket >/dev/null 2>&1
  systemctl enable docker --now 2>/dev/null
  if systemctl is-active --quiet docker; then
    printf "%s\n" "🐳 Docker Service Status: $(style_text "active" bold green)"
    return 0
  fi

  printf "%s\n" "🐳 Docker Service Status: $(style_text "failed" bold red)"
  log_err "Docker installed but the daemon failed to start."
  printf "    This is almost always an environment/kernel issue (netfilter/iptables\n"
  printf "    modules, storage driver) rather than a packaging problem —\n"
  printf "    reinstalling Docker will NOT fix it. Last lines of the daemon log:\n\n"
  # Clear the restart-limit backoff so the log shows the real error, not a
  # "start request repeated too quickly" message.
  systemctl reset-failed docker.service >/dev/null 2>&1
  journalctl -u docker.service --no-pager -n 25 2>/dev/null \
    || printf "    (journalctl unavailable; run: systemctl status docker.service)\n"
  exit 1
}

# ----------------------------------------------------------------------------
# Pre-flight
# ----------------------------------------------------------------------------
clear          # Clear the screen
as_root        # Confirm running as root (before any prompts or apt work)
check_if_linux # Confirm running on Linux

log_title "🐳  DOCKER INSTALLER FOR LINUX  -  v.2026-07"

# ----------------------------------------------------------------------------
# Already-installed check
# ----------------------------------------------------------------------------
if command -v docker >/dev/null; then
  log_info "Docker is already installed ($(docker --version))."
  read -r -p "Do you want to continue with the installation? [y/N]: " confirm
  if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "Exiting..."
    exit 0
  fi
  read -r -p "Do you want to uninstall the existing Docker install first? [y/N]: " confirm
  if [[ $confirm =~ ^[Yy]$ ]]; then
    # shellcheck source=docker_uninstall.sh
    source "${SCRIPT_DIR}/docker_uninstall.sh"
    uninstall_docker || exit $? # 'q' (or a failed uninstall) aborts the install
  else
    echo "Continuing with Docker installation (will install on top of existing)..."
  fi
fi

command -v curl >/dev/null || install_packages curl
command -v needrestart >/dev/null || install_packages needrestart

# ----------------------------------------------------------------------------
# Detect distro
# ----------------------------------------------------------------------------
log_step "Gathering Linux release info..."

# Determine if this is a Raspberry Pi 🥧
model=$(grep Raspberry /proc/cpuinfo | cut -d: -f2)
if [ -n "$model" ]; then
  printf "%s\n" "🥧 I am a $(style_text "Raspberry Pi" bold red)."
fi

# Source the os-release file
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
# on Mint 22). Docker only ships packages keyed to upstream codenames, so we
# prefer UBUNTU_CODENAME when present.
APT_CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

# ----------------------------------------------------------------------------
# Branch on platform
# ----------------------------------------------------------------------------
if [ -n "$model" ]; then
  # ---- Raspberry Pi -------------------------------------------------------
  log_step "Installing Docker for $model..."
  printf "%s\n" "Performing $(style_text "Raspberry Pi" bold red) Docker installation..."

  remove_conflicting_packages
  curl -sSL https://get.docker.com | sh
  check_status "🥧  Raspberry Pi Docker installation" $?
  enable_and_start_docker

elif [ "$ID" = "kali" ] || [ "$VERSION_CODENAME" = "kali-rolling" ]; then
  # ---- Kali Linux ---------------------------------------------------------
  # Kali is a rolling release based on Debian. Use the appropriate Debian
  # codename for Docker's apt repo.
  printf "%s\n" "ℹ️  I am a $(style_text "$PRETTY_NAME" bold blue) installation."
  log_step "Installing Docker for $PRETTY_NAME..."

  remove_conflicting_packages
  install_packages ca-certificates curl gnupg

  log_step "Adding Docker's GPG key..."
  install -m 0755 -d /etc/apt/keyrings
  rm -f /etc/apt/keyrings/docker.gpg /etc/apt/keyrings/docker.asc
  set -o pipefail
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc
  rc=$?
  set +o pipefail
  chmod a+r /etc/apt/keyrings/docker.asc
  check_status "Adding Docker's GPG key" $rc

  log_step "Adding Docker repository to apt sources (Debian ${KALI_DEBIAN_CODENAME})..."
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
        ${KALI_DEBIAN_CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
  check_status "Adding Docker repository" $?

  update_repo

  log_step "Installing Docker..."
  install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  check_status "Docker installation" $?

  enable_and_start_docker

elif [ "$ID" = "debian" ]; then
  # ---- Debian (non-Kali) --------------------------------------------------
  printf "%s\n" "ℹ️  I am a $(style_text "$PRETTY_NAME" bold blue) installation."

  if ! is_supported_codename "$VERSION_CODENAME" "${SUPPORTED_DEBIAN_CODENAMES[@]}"; then
    printf "⚠️   Debian codename '%s' is not in Docker's supported list (%s).\n" \
      "$VERSION_CODENAME" "${SUPPORTED_DEBIAN_CODENAMES[*]}"
    printf "    Falling back to Docker's convenience script (get.docker.com).\n"
    remove_conflicting_packages
    curl -sSL https://get.docker.com | sh
    check_status "Docker convenience-script installation" $?
    enable_and_start_docker
  else
    log_step "Installing Docker for $PRETTY_NAME ($VERSION_CODENAME)..."
    remove_conflicting_packages
    install_packages ca-certificates curl gnupg apt-transport-https lsb-release software-properties-common

    log_step "Adding Docker's GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    rm -f /etc/apt/keyrings/docker.gpg /etc/apt/keyrings/docker.asc
    set -o pipefail
    curl -fsSL https://download.docker.com/linux/debian/gpg \
      -o /etc/apt/keyrings/docker.asc
    rc=$?
    set +o pipefail
    chmod a+r /etc/apt/keyrings/docker.asc
    check_status "Adding Docker's GPG key" $rc

    log_step "Adding Docker repository to apt sources..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
          $VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    check_status "Adding Docker repository" $?

    update_repo

    log_step "Installing Docker..."
    install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    check_status "Docker installation" $?

    enable_and_start_docker
  fi

else
  # ---- Ubuntu and Ubuntu derivatives --------------------------------------
  # Covers Ubuntu, Pop!_OS, Linux Mint, Ubuntu MATE/Studio/Kylin/Budgie,
  # elementary OS, Zorin, KDE neon, etc.
  log_step "Installing Docker for $PRETTY_NAME..."
  printf "%s\n" "ℹ️  This is not a $(style_text "Raspberry Pi" normal red), $(style_text "Kali" normal blue) or $(style_text "Debian" normal blue) installation."
  printf "%s\n" "    Treating as Ubuntu / Ubuntu-derivative. Apt suite: $(style_text "$APT_CODENAME" bold green)"

  # Validate the codename. If we can't, fall back to get.docker.com which
  # has its own per-distro logic. This avoids a confusing 404 on the apt
  # repo for unsupported releases (e.g. EOL focal, oracular, lunar).
  if ! is_supported_codename "$APT_CODENAME" "${SUPPORTED_UBUNTU_CODENAMES[@]}"; then
    printf "⚠️   Ubuntu codename '%s' is not in Docker's currently supported list (%s).\n" \
      "$APT_CODENAME" "${SUPPORTED_UBUNTU_CODENAMES[*]}"
    printf "    This usually means the release is too old (EOL) or too new for Docker's apt repo.\n"
    printf "    Falling back to Docker's convenience script (get.docker.com).\n"
    remove_conflicting_packages
    curl -sSL https://get.docker.com | sh
    check_status "Docker convenience-script installation" $?
    enable_and_start_docker
  else
    install_packages ca-certificates gnupg apt-transport-https lsb-release software-properties-common
    check_status "Checking result of package installation" $?

    remove_conflicting_packages

    # Add Docker's official GPG key
    log_step "Adding Docker's GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    rm -f /etc/apt/keyrings/docker.gpg /etc/apt/keyrings/docker.asc
    set -o pipefail
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      -o /etc/apt/keyrings/docker.asc
    rc=$?
    set +o pipefail
    chmod a+r /etc/apt/keyrings/docker.asc
    check_status "Checking Result for Adding Docker's GPG key" $rc

    # Add the repository to apt sources. We use APT_CODENAME so that
    # Mint/Pop!_OS/etc. resolve to their upstream Ubuntu codename.
    log_step "Adding Docker repository to apt sources..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
          $APT_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    check_status "Checking Result for Adding Docker repository to apt sources" $?

    update_repo

    log_step "Installing Docker..."
    install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    check_status "Checking Result of Docker installation" $?

    enable_and_start_docker
  fi
fi

# ----------------------------------------------------------------------------
# Add user(s) to docker group
# ----------------------------------------------------------------------------
# Build a deduplicated list of candidate users to add. Skip empty values
# (happens when running as a true root login where SUDO_USER isn't set) and
# skip "root" (root doesn't need to be in the docker group).
declare -A _seen_users=()
candidate_users=()
for u in "$USER" "$SUDO_USER"; do
  if [ -n "$u" ] && [ "$u" != "root" ] && [ -z "${_seen_users[$u]+x}" ]; then
    if id "$u" >/dev/null 2>&1; then
      candidate_users+=("$u")
      _seen_users[$u]=1
    fi
  fi
done

if [ ${#candidate_users[@]} -eq 0 ]; then
  printf "ℹ️   No non-root user detected to add to the docker group.\n"
  printf "    If you want a regular user to run docker without sudo, run:\n"
  printf "        sudo usermod -aG docker <username>\n"
else
  for u in "${candidate_users[@]}"; do
    log_step "Adding $u to docker group..."
    usermod -aG docker "$u"
    check_status "Add $u to docker group" $?
  done
  printf "Log out and back in (or reboot) to use Docker without sudo.\n"
  printf "You can also run the following command to apply the changes:\n"
  printf "    newgrp docker\n"
  printf "This will start a new shell with the docker group applied.\n"
fi

# ----------------------------------------------------------------------------
# Smoke test (non-fatal; informational)
# ----------------------------------------------------------------------------
docker_smoke_test || true

log_title "🐳  DOCKER INSTALLER COMPLETE"
echo ""
