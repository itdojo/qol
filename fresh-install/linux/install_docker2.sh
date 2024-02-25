#!/bin/bash

uninstall_docker() {
    if ! command -v apt > /dev/null; then
        echo "❌  Cannot uninstall Docker. apt package manager not found."
        exit 1  # Terminate the script
    fi

    echo "Stopping all running Docker containers..."
    docker stop "$(docker ps -aq)" 2>/dev/null    # Stop all running containers
    echo "Removing all Docker containers..."
    docker rm "$(docker ps -aq)" 2>/dev/null      # Remove all Docker containers
    echo "Removing all Docker images..."
    docker rmi "$(docker images -q)" 2>/dev/null  # Remove all Docker images
    echo "Removing all Docker volumes..."
    docker volume rm "$(docker volume ls -q)" 2>/dev/null  # Remove all Docker volumes
    echo "Removing all Docker networks..."
    docker network rm "$(docker network ls -q)" 2>/dev/null  # Remove all Docker networks
    echo "Removing all Docker plugins..."
    docker plugin rm "$(docker plugin ls -q)" 2>/dev/null  # Remove all Docker plugins
    echo "Note: This does not remove Docker Swarm services, nodes, or secrets."
    echo "Uninstalling Docker..."
    sudo apt-get purge -y docker-engine docker docker.io docker-ce docker-ce-cli
    if command -v docker-desktop > /dev/null; then
        # Uninstall Docker Desktop
        echo "Uninstalling Docker Desktop..."
        sudo apt-get purge -y docker-desktop
        sudo apt-get autoremove -y --purge docker-desktop
    fi
    if command -v docker-compose > /dev/null; then
        # Uninstall Docker Compose
        echo "Uninstalling Docker Compose..."
        sudo apt-get purge -y docker-compose
        sudo apt-get autoremove -y --purge docker-compose
    fi
    sudo apt-get autoremove -y --purge docker-engine docker docker.io docker-ce  

    sudo rm -rf /var/lib/docker /var/lib/containerd      # Remove Docker storage directories
    sudo rm -rf /etc/docker                              # Remove Docker config files
    sudo rm -rf ~/.docker                                # Remove Docker user directory
    if getent group docker > /dev/null; then
        sudo groupdel docker                             # Remove Docker group
    fi
    sudo rm -rf /var/run/docker.sock                     # Remove Docker socket

    echo "Docker has been uninstalled."
}

. base_functions2.sh        # Source the base functions
clear                       # Clear the screen
check_root                  # Confirm running as root
trap handle_ctrl_c SIGINT   # Gracefully handle CTRL-C

fstring "🐳  DOCKER INSTALLER FOR LINUX" "title"
printline dentistry

# Check if Docker is already installed
if command -v docker > /dev/null; then
    echo "Docker is already installed."
    echo "Reinstalling will remove Docker and $(fstring "all containers and images" "normal" "bold" "red")."
    echo "You $(fstring "cannot" "normal" "normal" "normal" "underline") undo this action."
    read -p "Do you want to reinstall Docker? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Docker reinstall cancelled. Exiting..."
        echo ""
        exit 0  # Terminate the script
    else
        echo "Removing Existing Docker Installation... "
        uninstall_docker
    fi
fi

if ! command -v curl > /dev/null; then
    echo "Installing curl..."
    apt update && apt install curl -y
fi
if ! command -v needreinstall > /dev/null; then
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
    printf "%s\n" "ℹ️  I am a $(fstring "$PRETTY_NAME" "normal" "bold" "blue") installation."
    fstring "Installing Docker for $PRETTY_NAME... " "section"
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
    frpint "🔑  Adding Docker's GPG key... " "section"
    install -m 0755 -d /etc/apt/keyrings
    rm -f /etc/apt/keyrings/docker.gpg # Remove any existing Docker GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    check_status "Checking Result for Adding Docker's GPG key" $?

    # Add the repository to apt sources
    fprint "Adding Docker repository to apt sources... " "section"
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $VERSION_CODENAME stable" |
        tee /etc/apt/sources.list.d/docker.list >/dev/null
        check_status "Checking Result for Adding Docker repository to apt sources" $?

    update_repo
    # Installing Docker
    fprint "Installing Docker... " "section"
    install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    check_status "Checking Result of Docker installation" $?
fi

# Adding user to docker group
fstring "Adding $USER to docker group... " "section"
usermod -aG docker "$USER"
check_status "Add $USER to docker group" $?
fstring "Adding $SUDO_USER to docker group... " "section"
usermod -aG docker "$SUDO_USER"
check_status "Add $SUDO_USER to docker group" $?

fstring "🐳  DOCKER INSTALLER COMPLETE" "title"
printline dentistry
echo""
