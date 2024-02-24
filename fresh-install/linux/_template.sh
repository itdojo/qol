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