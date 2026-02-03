#!/bin/bash

# This script installs Docker on a Linux system. It also adds the current user to the docker group.
# It has been successfully tested on Ubuntu, PoP!_OS, Kali, Ubuntu MATE, and Raspberry Pi OS.
# It does not work on Mint 21.3 (Cinnamon).  

# This script relies on the availability of the base_functions.sh file. If it is not found, the script will exit.
# The base_functions.sh file should be available in the same directory as this script.
# If not, you can get it from https://github.com/itdojo/qol.

SCRIPT_DIR="$(dirname "$(realpath "$0")")"          # Get the directory of the script
BASE_FUNCTIONS="${SCRIPT_DIR}/base_functions.sh"    # Path to the base_functions.sh file

if [ ! -f "$BASE_FUNCTIONS" ]; then
    echo "❌  base_functions.sh not found. Downloading from GitHub."
    wget https://raw.githubusercontent.com/itdojo/qol/refs/heads/main/linux/base_functions.sh -O "$BASE_FUNCTIONS" \
        || { echo "❌ Failed to download base_functions.sh"; exit 1; }
fi

# Source the base_functions.sh file
source "$BASE_FUNCTIONS"


if command -v docker > /dev/null; then
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
        source "${SCRIPT_DIR}/docker_uninstall.sh"  # Source the docker_uninstall.sh
        uninstall_docker
    else
        echo "Continuing with Docker installation..."
        return 0
    fi
fi

clear                       # Clear the screen
as_root                     # Confirm running as root
check_if_linux              # Confirm running on Linux
trap handle_ctrl_c SIGINT   # Gracefully handle CTRL-C

fstring "🐳  DOCKER INSTALLER FOR LINUX" "title"
printline dentistry

if ! command -v curl > /dev/null; then
    echo "Installing curl..."
    apt update && apt install curl -y
fi
if ! command -v needrestart > /dev/null; then
    echo "Installing needrestart..."
    apt update && apt install needrestart -y
fi

# Determine if Kali, Raspberry Pi or "regular" Linux
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
fi

if [ -n "$model" ]; then
    # This is a Raspberry Pi
    fstring "Installing Docker for $model... " "section"
    printf "%s\n" "Performing $(fstring "Raspberry Pi" "normal" "bold" "red") Docker installation..."

    curl -sSL https://get.docker.com | sh
    check_status "$(fstring "🥧  Raspberry Pi" "normale" "normal" "red") Docker installation"  $?
elif [ "$VERSION_CODENAME" = "kali-rolling" ]; then
    # This is Kali
    printf "%s\n" "ℹ️  I am a $(fstring "$PRETTY_NAME" "normal" "bold" "blue") installation."
    fstring "Installing Docker for $PRETTY_NAME... " "section"
    printf "❓  If prompted to overwrite Docker gpg key, select 'Yes'.\n"
    printf '%s\n' "deb https://download.docker.com/linux/debian bullseye stable" | tee /etc/apt/sources.list.d/docker-ce.list
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker-ce-archive-keyring.gpg
    update_repo
    install_packages docker-ce docker-ce-cli containerd.io
    printf "%s\n" "Enabling and starting the Docker service..."
    systemctl enable docker --now
    printf "%s\n" "🐳 Docker Service Status: $(systemctl is-active docker)"
else
    fstring "Installing Docker for $PRETTY_NAME... " "section"
    printf "%s\n" "ℹ️  This is not a $(fstring "Raspberry Pi" "normal" "normal" "red") or $(fstring "Kali" "normal" "normal" "blue") installation."
    printf "%s\n" "📦  Installing some required packages for 🐳 Docker..."
    install_packages ca-certificates gnupg apt-transport-https lsb-release software-properties-common
    check_status "Checking result of package installation" $?

    # Add Docker's official GPG key:
    fstring "🔑  Adding Docker's GPG key... " "section"
    install -m 0755 -d /etc/apt/keyrings
    rm -f /etc/apt/keyrings/docker.gpg # Remove any existing Docker GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --output /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    check_status "Checking Result for Adding Docker's GPG key" $?

    # Add the repository to apt sources
    fstring "Adding Docker repository to apt sources... " "section"
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
        check_status "Checking Result for Adding Docker repository to apt sources" $?

    update_repo
    # Installing Docker
    fstring "Installing Docker... " "section"
    install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    check_status "Checking Result of Docker installation" $?
fi

# Adding user to docker group
fstring "Adding $USER to docker group... " "section"
usermod -aG docker "$USER"
check_status "Add $USER to docker group" $?
#newgrp docker
fstring "Adding $SUDO_USER to docker group... " "section"
usermod -aG docker "$SUDO_USER"
check_status "Add $SUDO_USER to docker group" $?
#newgrp docker
printf "Log out and back in (or reboot) to use Docker without sudo.\n"
printf "You can also run the following command to apply the changes:\n"
printf "newgrp docker\n"
printf "This will start a new shell with the docker group applied.\n"

fstring "🐳  DOCKER INSTALLER COMPLETE" "title"
printline dentistry
echo""
