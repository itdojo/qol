#!/bin/bash

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo " ❌  Run as root."
    echo " ℹ️  Usage: sudo ./${basename $0}"
    exit
  fi
}

# Define the function to be executed when SIGINT (CTRL-C) is received
handle_ctrl_c() {
    printf "%s\n" "🛑 CTRL-C detected. Exiting..."
    echo ""
    exit 1
}

printline() {
    printf "%.s─" $(seq 1 "$(tput cols)")
    # printf "%.s∙" $(seq 1 "$(tput cols)")  # Different line style
    # printf "%.s⌶" $(seq 1 "$(tput cols)")  # Different line style
    # printf "%.s☆" $(seq 1 "$(tput cols)")  # Different line style
    # printf "%.s⏥" "$(seq 1 "$(tput cols)") # Different line style
}

# Function to check the status of the last executed command
check_status() {
    message=$1
    if [ $? -eq 0 ]; then
        section_title="✅  $message Success!"
        format_font "$section_title" $SUCCESS_WEIGHT $SUCCESS_COLOR
    else
        section_title="❌  $message Failed!"
        format_font "$section_title" $WARNING_WEIGHT $WARNING_COLOR
        exit 1
    fi
    printline
}

# Function to update and upgrade system
update_and_upgrade() {
    message="#️⃣  Updating and upgrading system: "
    printf "%s\n" "$message"
    sudo apt -o Acquire::ForceIPv4=true update && sudo apt upgrade -y
    check_status "$message"
}

# Function to update and upgrade system
update_repo() {
    message="Updating repository: "
    printf "%s\n" "$message"
    sudo apt -o Acquire::ForceIPv4=true update
    check_status "$message"
}


# Function to install packages
# Usage: install_packages package1 package2 package3...
install_packages() {
    printf "%s\n" "#️⃣  Installing $*..."
    sudo apt install "$@" -y
    check_status "Package installation: "
    needrestart -r a # Automatically restart services if necessary
}

format_font() {
    # Usage: format_font "Text to be formatted" "font weight" "font color"
    TEXT=$1         # The string to be formatted
    RESET="\033[0m" # Resets colors to default
    case $2 in      # $2 = font weight
    normal)
        WEIGHT=0
        ;;
    bold)
        WEIGHT=1
        ;;
    *) # default to normal
        WEIGHT=0
        ;;
    esac

    case $3 in # $3 = font color
    blue)   # 🔵
        COLOR="\033[$WEIGHT;34m"
        ;;
    red)    # 🔴
        COLOR="\033[$WEIGHT;31m"
        ;;
    green)  # 🟢
        COLOR="\033[$WEIGHT;32m"
        ;;
    yellow) # 🟡
        COLOR="\033[$WEIGHT;33m"
        ;;
    *) # default to blue 🔵
        COLOR="\033[$WEIGHT;34m"
        ;;
    esac

    # Print the string with color and weight
    echo -e "${COLOR}${TEXT}${RESET}"
}

# Set some font  weight and color preferences
TITLE_COLOR="yellow"  # blue 🔵|red 🔴|green 🟢|yellow 🟡
TITLE_WEIGHT="bold"   # normal|bold
WARNING_COLOR="red"   # blue 🔵|red 🔴|green 🟢|yellow 🟡
WARNING_WEIGHT="bold" # normal|bold
SUCCESS_COLOR="green" # blue 🔵|red 🔴|green 🟢|yellow 🟡
SUCCESS_WEIGHT="bold" # normal|bold

clear # Clear the screen

check_root
trap handle_ctrl_c SIGINT

# Determine if this is a Raspberry Pi 🥧
model=$(grep Raspberry /proc/cpuinfo | cut -d: -f2)

if [ -n "$model" ]; then
    printf "%s\n" "🥧 This appears to be a Raspberry Pi."
    printf "%s\n" "Performing Raspberry Pi specific Docker installation..."
    section_title="#️⃣  Installing Docker for $model..."
    format_font "$section_title" $TITLE_WEIGHT $TITLE_COLOR
    printline
    curl -sSL https://get.docker.com | sh
    check_status
elif [ "$release" = "kali-rolling" ]; then
    printf "%s\n" "This system appears to be running Kali."
    section_title="#️⃣  Installing Docker for $release... "
    format_font "$section_title" $TITLE_WEIGHT $TITLE_COLOR
    printline
    printf '%s\n' "deb https://download.docker.com/linux/debian bullseye stable" | sudo tee /etc/apt/sources.list.d/docker-ce.list
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/docker-ce-archive-keyring.gpg
    update_repo
    install_packages docker-ce docker-ce-cli containerd.io
    printf "%s\n" "Enabling and starting the Docker service..."
    sudo systemctl enable docker --now
    check_status "Enable Docker service"
    printf "%s\n" "Docker status: $(systemctl is-active docker)"
else
    printf "%s\n" "This does not appear to be a Raspberry Pi or a Kali installation."
    printf "%s\n" "Performing Standard Linux Docker Install..."
    section_title="#️⃣  Installing Docker for $release... "
    format_font "$section_title" $TITLE_WEIGHT $TITLE_COLOR
    printline
    # Installing Docker
    printf "%s\n" "Installing some required packages for Docker..."
    install_packages ca-certificates gnupg apt-transport-https lsb-release software-properties-common
    check_status "Install required packages"

    # Add Docker's official GPG key:
    section_title="🔑  Adding Docker's GPG key... "
    format_font "$section_title" $TITLE_WEIGHT $TITLE_COLOR
    printline
    sudo install -m 0755 -d /etc/apt/keyrings
    rm -f /etc/apt/keyrings/docker.gpg # Remove any existing Docker GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    check_status "$section_title"

    # Add the repository to apt sources
    section_title="#️⃣  Adding Docker repository to apt sources... "
    format_font "$section_title" $TITLE_WEIGHT $TITLE_COLOR
    printline
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
        sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    check_status "$section_title"

    update_repo

    # Installing Docker
    printline
    section_title="#️⃣  Installing Docker... "
    format_font "$section_title" $TITLE_WEIGHT $TITLE_COLOR
    printline
    install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    check_status "$section_title"

    # Adding user to docker group
    section_title="#️⃣  Adding $SUDO_USER to docker group..."
    format_font "$section_title" $TITLE_WEIGHT $TITLE_COLOR
    sudo usermod -aG docker "$SUDO_USER"
    check_status "$section_title"
fi
