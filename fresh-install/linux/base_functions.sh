# Check if the script is being run as root
as_root() {
  if [ "$EUID" -ne 0 ]; then
    echo ""
    echo " ❌  Run as root."
    echo " ℹ️  Usage: sudo $0"
    echo ""
    exit 1
  fi
}

# Check if the script is being run as root
as_not_root() {
  if [ "$EUID" -eq 0 ]; then
    echo ""
    echo " ❌  Do not run as root."
    echo " ℹ️  Usage: $0"
    echo ""
    exit 1
  fi
}

# Define the function to be executed when SIGINT (CTRL-C) is received
handle_ctrl_c() {
    printf "%s\n" "🛑 CTRL-C detected. Exiting."
    echo ""
    exit 1
}

# Function to check the status of the last executed command
check_status() {
    message=$1
    if [ $? -eq 0 ]; then
        section_title="$message Success!"
        format_font "✅  $section_title" $SUCCESS_WEIGHT $SUCCESS_COLOR
    else
        section_title="$message Failed!"
        format_font "❌  $section_title" $WARNING_WEIGHT $WARNING_COLOR
        exit 1
    fi
}

# Function to update and upgrade system
update_and_upgrade() {
    message="Updating and upgrading system... "
    printf "%s\n" "$message"
    apt -o Acquire::ForceIPv4=true update && apt upgrade -y
    check_status "$message"
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
        solid)     sep="─" ;;   # ───────────── 
        bullet)    sep="•" ;;   # •••••••••••••
        ibeam)     sep="⌶" ;;   # ⌶⌶⌶⌶⌶⌶⌶⌶⌶⌶⌶⌶
        star)      sep="★" ;;   # ★★★★★★★★★★★★★★
        dentistry) sep="⏥" ;;  # ⏥⏥⏥⏥⏥⏥⏥⏥
        *)         sep="─" ;;   # ──────────────
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
