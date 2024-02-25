#!/bin/bash
# This script is intended to be sourced in other scripts
# Usgage: source base_functions.sh
#
# Check if the script is being run as root
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo ""
    echo " ❌  Run as root."
    echo " ℹ️  Usage: sudo $0"
    echo ""
    exit 1
  fi
}

# Make sure the script is not being run as root
not_as_root() {
  if [ "$EUID" -eq 0 ]; then
    echo ""
    echo " ❌  Do not run as root."
    echo " ℹ️  Usage: $0"
    echo ""
    exit 1
  fi
}

# Gracefully handle CTRL-C
handle_ctrl_c() {
    printf "%s\n" "🛑 CTRL-C detected. Exiting."
    echo ""
    exit 1
}

check_if_linux() {
    if [ "$(uname)" != "Linux" ]; then
        echo "This script is intended for Linux only."
        exit 1
    fi
}

# Update and upgrade system
update_and_upgrade() {
    message="Updating and upgrading system... "
    printf "%s\n" "$message"
    export DEBIAN_FRONTEND=noninteractive
    apt -o Acquire::ForceIPv4=true update && apt upgrade -y
    check_status "$message" $?
    unset DEBIAN_FRONTEND
}

# Update repository
update_repo() {
    message="Updating repository: "
    printf "%s\n" "$message"
    apt -o Acquire::ForceIPv4=true update
    check_status "$message" $?
}

# Install packages
install_packages() {
    # Usage: install_packages package1 package2 package3...
    printf "%s\n" "Installing $*..."
    export DEBIAN_FRONTEND=noninteractive
    apt install "$@" -y
    check_status "Package(s) installation: " $?
    unset DEBIAN_FRONTEND
    needrestart -r a # Automatically restart services if necessary
}

# Check the status of the last executed command
check_status() {
    if [ $# -ne 2 ]; then
        echo -ne "💡 "
        echo -e "Cannot check status without a message and exit status."
        echo "Usage: $(fstring "check_status <message> <exit_status>" "normal" "normal" "yellow")"

        return 1
    fi

    local message="$1"
    local exit_status="$2"

    if [ "$exit_status" -eq 0 ]; then
        printf "%s: " "$message"
        fstring "SUCCESS ✅" "normal" "bold" "green"
    else
        echo -ne ""$message": ❌ "
        echo -ne "$(fstring "FAILED" "normal" "bold" "red" "reverse")"
        echo " ❌"
        return 1
    fi
}


# Print a line the width of the terminal
printline() {
    local sep
    case $1 in
        solid)     sep="─" ;;   # ───────────── 
        bullet)    sep="•" ;;   # •••••••••••••
        ibeam)     sep="⌶" ;;   # ⌶⌶⌶⌶⌶⌶⌶⌶⌶⌶⌶⌶
        star)      sep="★" ;;   # ★★★★★★★★★★★★★★
        plus)      sep="✛" ;;   # ✛✛✛✛✛✛✛✛✛✛✛✛✛✛
        diamond)   sep="◆" ;;   # ◆◆◆◆◆◆◆◆◆◆◆◆◆◆
        dentistry) sep="⏥" ;;   # ⏥⏥⏥⏥⏥⏥⏥⏥
        *)         sep="─" ;;    # ──────────────
    esac
    printf -v line '%*s' "$(tput cols)" ''
    echo "${line// /$sep}"
}

# Format and print text
fstring() {
    # Usage: fstring "text" "type" "weight" "color" "emphasis"
    #⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽
    #│  type   ⎪  weight  ⎪  color  ⎪  emphasis  │ 
    #│⎺⎺⎺⎺⎺⎺⎺⎺⎺│⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺│⎺⎺⎺⎺⎺⎺⎺⎺⎺│⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺│
    #│ normal  │  normal  │ red     │  italics   │
    #│ title   │  bold    │ orange  │  underline │
    #│ section │  light   │ yellow  │  blink     │
    #│ warning │          │ green   │  reverse   │
    #│ success │          │ blue    │  hidden    │
    #│         │          │ indigo  │            │
    #│         │          │ violet  │            │
    #│         │          │ white   │            │
    #│         │          │ black   │            │
    #⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺
    # Example: fstring "Say Something" "normal" "bold" "blue" "italics"
    # Example: fstring "Say Something"  <-- This will print normal text
    # "weight" "color" and "emphasis" are optional (controlled by "type" setting when not specified)
    # If you want to override the "type" setting, you can set "weight", "color" and "emphasis" explicitly
    # If you want "color" to be applied, you must specify "weight".
    # If you want "emphasis" to be applied, you must specify "weight" and "color".
    local string="$1"
    local text_type="${2:-normal}"       # Default to normal if not specified
    local font_weight="${3:-normal}"     # Default to normal if not specified
    local font_color="$4"                # No default, to allow conditional application
    local font_emphasis="${5:-normal}"   # Default to normal if not specified
    local reset="\033[0m"
    local weight color linetype emphasis 

    # Determine line type and prepend symbols to string if needed
    case "$text_type" in
        title)    linetype="dentistry"; string="🔹  $string"; font_weight="bold"; font_color="blue" ;;
        section)  linetype="solid";     string="🔸  $string"; font_weight="bold"; font_color="yellow" ;;
        warning)  linetype="solid";     string="⚠️  $string"; font_weight="bold"; font_color="red" ;;
        success)  linetype="solid";     string="✅  $string"; font_weight="bold"; font_color="green" ;;
        normal)   linetype="" ;;  # No line type
        *)        linetype="" ;;  # No line type
    esac

    # Set font weight
    case $font_weight in
        normal)    weight=0 ;;  # Normal text
        bold)      weight=1 ;;  # Bold text
        light)     weight=2 ;;  # Light text
        *)         weight=0 ;;  # Use normal weight if unspecified
    esac

    case $font_emphasis in
        italics)   emphasis=3 ;;  # Italic text
        underline) emphasis=4 ;;  # Underlined text
        blink)     emphasis=5 ;;  # Blinking text (may not work in all terminals)
        reverse)   emphasis=7 ;;  # Reverse text (swap foreground and background colors)
        hidden)    emphasis=8 ;;  # Hidden text (useful for passwords)
        *)         emphasis=$weight ;;  # Use given weight without emphasis if unspecified
    esac

    # Set font color
    case $font_color in
        red)    color="\033[${weight};${emphasis};31m" ;;  # 🔴
        orange) color="\033[${weight};${emphasis};91m" ;;  # 🟠
        yellow) color="\033[${weight};${emphasis};33m" ;;  # 🟡
        green)  color="\033[${weight};${emphasis};32m" ;;  # 🟢
        blue)   color="\033[${weight};${emphasis};34m" ;;  # 🔵
        indigo) color="\033[${weight};${emphasis};94m" ;;  # 🟣
        violet) color="\033[${weight};${emphasis};35m" ;;  # 🟤
        white)  color="\033[${weight};${emphasis};97m" ;;  # ⚪
        black)  color="\033[${weight};${emphasis};30m" ;;  # ⚫  
        *)      color="\033[${weight};${emphasis};m"   ;;  # Use given weight without color if unspecified
    esac

    # Print the line, text, and line again if linetype is set
    if [[ -n $linetype ]]; then printline "$linetype"; fi
    echo -e "${color}${string}${reset}"
    #if [[ -n $linetype ]]; then printline "$linetype"; fi
}

# Import the os-release file
if [ -f /etc/os-release ]; then
    . /etc/os-release
    export OS_NAME="$NAME"
    export OS_VERSION="$VERSION"
    export OS_CODENAME="$VERSION_CODENAME"
    unset HOME_URL SUPPORT_URL BUG_REPORT_URL PRIVACY_POLICY_URL
fi

