#!/bin/bash

. base_functions2.sh        # Source the base functions
clear                       # Clear the screen
check_root                  # Confirm running as root
trap handle_ctrl_c SIGINT   # Gracefully handle CTRL-C

fstring "🐳  DOCKER INSTALLER" "title"

fstring "Gathering Release Info... " "section"
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

printline solid
if [ -n "$model" ]; then
    # This is a Raspberry Pi
    fstring "Installing Docker for $model... " "section"
    printf "%s\n" "Performing $(fstring "Raspberry Pi" "normal" "bold" "red") specific Docker installation..."
    curl -sSL https://get.docker.com | sh
    check_status
elif [ "$VERSION_CODENAME" = "kali-rolling" ]; then
    printf "%s\n" "I am a $(printf "$PRETTY_NAME" "normal" "bold" "blue") installation."
    fstring "Installing Docker for $PRETTY_NAME... " "section"
    printf '%s\n' "deb https://download.docker.com/linux/debian bullseye stable" | tee /etc/apt/sources.list.d/docker-ce.list
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker-ce-archive-keyring.gpg
    update_repo
    install_packages docker-ce docker-ce-cli containerd.io
    printf "%s\n" "Enabling and starting the Docker service..."
    systemctl enable docker --now
    printf "%s\n" "🐳 Docker status: $(systemctl is-active docker)"
else
    fprint "Installing Docker for $PRETTY_NAME... " "section"
    printf "%s\n" "This is not a $fstring "Raspberry Pi" "normal" "normal" "red") or $fstring "Kali" "normal" "normal" "blue") installation."
    printf "%s\n" "📦  Installing some required packages for 🐳 Docker..."
    install_packages ca-certificates gnupg apt-transport-https lsb-release software-properties-common
    check_status "Checking result of package installation" $?

    # Add Docker's official GPG key:
    frpint "🔑  Adding Docker's GPG key... " "section"
    install -m 0755 -d /etc/apt/keyrings
    rm -f /etc/apt/keyrings/docker.gpg # Remove any existing Docker GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    check_status "Checking Result for Adding Docker's GPG key"

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
    check_status "Checking Result for Docker installation" $?
fi

# Adding user to docker group
fprint "Adding $USER to docker group... " "section"
usermod -aG docker "$USER"
check_status "Add $USER to docker group" $?

frpint "🐳  DOCKER INSTALLER COMPLETE" "title"
echo""
