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
# This script relies on the availability of the base_functions.sh file. If it is not found, the script will exit.
# The base_functions.sh file should be available in the same directory as this script.
# If not, you can get it from https://github.com/itdojo/qol.

SCRIPT_DIR="$(dirname "$(realpath "$0")")"       # Get the directory of the script
BASE_FUNCTIONS="${SCRIPT_DIR}/base_functions.sh" # Path to the base_functions.sh file

if [ ! -f "$BASE_FUNCTIONS" ]; then
  echo "❌  base_functions.sh not found. Downloading from GitHub."
  wget https://raw.githubusercontent.com/itdojo/qol/refs/heads/main/linux/base_functions.sh -O "$BASE_FUNCTIONS" ||
    {
      echo "❌ Failed to download base_functions.sh"
      exit 1
    }
fi

# Source the base_functions.sh file
source "$BASE_FUNCTIONS"

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
  fstring "🧹  Removing any conflicting distro Docker packages... " "section"
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
  fstring "🔬  Running Docker smoke test (hello-world)... " "section"
  if docker run --rm hello-world >/dev/null 2>&1; then
    printf "✅  Smoke test passed - Docker is working.\n"
    return 0
  else
    printf "⚠️   Smoke test failed. Docker installed but couldn't run hello-world.\n"
    printf "    Check 'systemctl status docker' and 'journalctl -u docker'.\n"
    return 1
  fi
}

# ----------------------------------------------------------------------------
# Already-installed check
# ----------------------------------------------------------------------------
if command -v docker >/dev/null; then
  echo "Docker is already installed ($(docker --version))."
  read -p "Do you want to continue with the installation? [y/N]: " -r confirm
  case $confirm in
  [Yy])
    echo ""
    ;;
  *)
    echo "Exiting..."
    exit 0
    ;;
  esac
  read -p "Do you want to uninstall existing Docker install first? [y/N]: " -r confirm
  if [[ $confirm =~ ^[Yy]$ ]]; then
    source "${SCRIPT_DIR}/docker_uninstall.sh" # Source the docker_uninstall.sh
    uninstall_docker
  else
    echo "Continuing with Docker installation (will install on top of existing)..."
    # NOTE: previously had `return 0` here, which only works if sourced.
    # Falling through to the install flow is the correct behavior.
  fi
fi

clear                     # Clear the screen
as_root                   # Confirm running as root
check_if_linux            # Confirm running on Linux
trap handle_ctrl_c SIGINT # Gracefully handle CTRL-C

fstring "🐳  DOCKER INSTALLER FOR LINUX - v.2026-05" "title"
printline dentistry

if ! command -v curl >/dev/null; then
  echo "Installing curl..."
  apt-get update && apt-get install curl -y
fi
if ! command -v needrestart >/dev/null; then
  echo "Installing needrestart..."
  apt-get update && apt-get install needrestart -y
fi

# ----------------------------------------------------------------------------
# Detect distro
# ----------------------------------------------------------------------------
fstring "Gathering Linux Release Info... " "section"

# Determine if this is a Raspberry Pi 🥧
model=$(grep Raspberry /proc/cpuinfo | cut -d: -f2)
if [ -n "$model" ]; then
  printf "%s\n" "🥧 I am a $(fstring "Raspberry Pi" "normal" "bold" "red")."
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
  fstring "Installing Docker for $model... " "section"
  printf "%s\n" "Performing $(fstring "Raspberry Pi" "normal" "bold" "red") Docker installation..."

  remove_conflicting_packages
  curl -sSL https://get.docker.com | sh
  check_status "$(fstring "🥧  Raspberry Pi" "normal" "normal" "red") Docker installation" $?

elif [ "$ID" = "kali" ] || [ "$VERSION_CODENAME" = "kali-rolling" ]; then
  # ---- Kali Linux ---------------------------------------------------------
  # Kali is a rolling release based on Debian. Use the appropriate Debian
  # codename for Docker's apt repo.
  printf "%s\n" "ℹ️  I am a $(fstring "$PRETTY_NAME" "normal" "bold" "blue") installation."
  fstring "Installing Docker for $PRETTY_NAME... " "section"

  remove_conflicting_packages
  install_packages ca-certificates curl gnupg

  fstring "🔑  Adding Docker's GPG key... " "section"
  install -m 0755 -d /etc/apt/keyrings
  rm -f /etc/apt/keyrings/docker.gpg /etc/apt/keyrings/docker.asc
  set -o pipefail
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc
  rc=$?
  set +o pipefail
  chmod a+r /etc/apt/keyrings/docker.asc
  check_status "Adding Docker's GPG key" $rc

  fstring "Adding Docker repository to apt sources (Debian ${KALI_DEBIAN_CODENAME})... " "section"
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
        ${KALI_DEBIAN_CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
  check_status "Adding Docker repository" $?

  update_repo

  fstring "Installing Docker... " "section"
  install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  check_status "Docker installation" $?

  printf "%s\n" "Enabling and starting the Docker service..."
  systemctl enable docker --now
  printf "%s\n" "🐳 Docker Service Status: $(systemctl is-active docker)"

elif [ "$ID" = "debian" ]; then
  # ---- Debian (non-Kali) --------------------------------------------------
  printf "%s\n" "ℹ️  I am a $(fstring "$PRETTY_NAME" "normal" "bold" "blue") installation."

  if ! is_supported_codename "$VERSION_CODENAME" "${SUPPORTED_DEBIAN_CODENAMES[@]}"; then
    printf "⚠️   Debian codename '%s' is not in Docker's supported list (%s).\n" \
      "$VERSION_CODENAME" "${SUPPORTED_DEBIAN_CODENAMES[*]}"
    printf "    Falling back to Docker's convenience script (get.docker.com).\n"
    remove_conflicting_packages
    curl -sSL https://get.docker.com | sh
    check_status "Docker convenience-script installation" $?
  else
    fstring "Installing Docker for $PRETTY_NAME ($VERSION_CODENAME)... " "section"
    remove_conflicting_packages
    install_packages ca-certificates curl gnupg apt-transport-https lsb-release software-properties-common

    fstring "🔑  Adding Docker's GPG key... " "section"
    install -m 0755 -d /etc/apt/keyrings
    rm -f /etc/apt/keyrings/docker.gpg /etc/apt/keyrings/docker.asc
    set -o pipefail
    curl -fsSL https://download.docker.com/linux/debian/gpg \
      -o /etc/apt/keyrings/docker.asc
    rc=$?
    set +o pipefail
    chmod a+r /etc/apt/keyrings/docker.asc
    check_status "Adding Docker's GPG key" $rc

    fstring "Adding Docker repository to apt sources... " "section"
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
          $VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    check_status "Adding Docker repository" $?

    update_repo

    fstring "Installing Docker... " "section"
    install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    check_status "Docker installation" $?

    systemctl enable docker --now
    printf "%s\n" "🐳 Docker Service Status: $(systemctl is-active docker)"
  fi

else
  # ---- Ubuntu and Ubuntu derivatives --------------------------------------
  # Covers Ubuntu, Pop!_OS, Linux Mint, Ubuntu MATE/Studio/Kylin/Budgie,
  # elementary OS, Zorin, KDE neon, etc.
  fstring "Installing Docker for $PRETTY_NAME... " "section"
  printf "%s\n" "ℹ️  This is not a $(fstring "Raspberry Pi" "normal" "normal" "red"), $(fstring "Kali" "normal" "normal" "blue") or $(fstring "Debian" "normal" "normal" "blue") installation."
  printf "%s\n" "    Treating as Ubuntu / Ubuntu-derivative. Apt suite: $(fstring "$APT_CODENAME" "normal" "bold" "green")"

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
  else
    printf "%s\n" "📦  Installing some required packages for 🐳 Docker..."
    install_packages ca-certificates gnupg apt-transport-https lsb-release software-properties-common
    check_status "Checking result of package installation" $?

    remove_conflicting_packages

    # Add Docker's official GPG key
    fstring "🔑  Adding Docker's GPG key... " "section"
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
    fstring "Adding Docker repository to apt sources... " "section"
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
          $APT_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    check_status "Checking Result for Adding Docker repository to apt sources" $?

    update_repo

    fstring "Installing Docker... " "section"
    install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    check_status "Checking Result of Docker installation" $?

    systemctl enable docker --now
    printf "%s\n" "🐳 Docker Service Status: $(systemctl is-active docker)"
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
    fstring "Adding $u to docker group... " "section"
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

fstring "🐳  DOCKER INSTALLER COMPLETE" "title"
printline dentistry
echo ""
