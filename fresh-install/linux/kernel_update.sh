#!/bin/bash

# Update kernel to latest version
# Usage: sudo ./kernel_update.sh

source base_functions.sh

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "❌ Run as root."
    exit
  fi
}

# Define the function to be executed when SIGINT (CTRL-C) is received
handle_ctrl_c() {
    printf "%s\n" "🛑 CTRL-C detected. Exiting."
    echo ""
    exit 1
}

# Function to update and upgrade system
update_repo() {
    message="Updating repository: "
    printf "%s\n" "$message"
    apt -o Acquire::ForceIPv4=true update
    check_status "$message"
}

# Function to install packages
# Usage: install_packages package1 package2 package3...
install_packages() {
    printf "%s\n" "Installing $*..."
    apt install "$@" -y
    check_status "Package(s) installation: "
    needrestart -r a # Automatically restart services if necessary
}

printline() {
    case $1 in
        solid)
            sep="─"   # ─────────────
            ;;  
        bullet)
            sep="•"   # •••••••••••••
            ;;
        ibeam)
            sep="⌶"   # ⌶⌶⌶⌶⌶⌶⌶⌶⌶⌶⌶⌶
            ;;
        star)
            sep="★"   # ★★★★★★★★★★★★★★
            ;;
        dentistry)
            sep="⏥"  # ⏥⏥⏥⏥⏥⏥⏥⏥
            ;;
        *)
            sep="─"   # ──────────────
            ;;
        esac
printf "%.s$sep" $(seq 1 "$(tput cols)")
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

check_root  # Check for root

trap handle_ctrl_c SIGINT  # Handle CTRL-C

printline dentistry
format_font "UPGRADING KERNEL" "bold" "blue"
printline dentistry

# Installing mainline
section_title="Adding Kernel Repository..."
format_font "#️⃣   $section_title" $TITLE_WEIGHT $TITLE_COLOR
add-apt-repository -y ppa:cappelikan/ppa
check_status "Checking Result for $section_title"


# Installing mainline
printline solid
section_title="Installing mainline..."
format_font "#️⃣   $section_title" $TITLE_WEIGHT $TITLE_COLOR
install_packages mainline
check_status "Checking Result for $section_title"


# Installing latest kernel
printline solid
section_title="Installing Latest Kernel..."
format_font "#️⃣   $section_title" $TITLE_WEIGHT $TITLE_COLOR
mainline install-latest
check_status "Checking Result for $section_title"
apt -y --fix-broken install

printline dentistry
format_font "KERNEL UPGRADE COMPLETE" "bold" "blue"
printline dentistry
echo ""
format_font "Reboot your computer to load new kernel" "bold" "red"
echo ""
