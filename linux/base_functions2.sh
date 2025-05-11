# This script is intended to be sourced in other scripts
# Usage: source base_functions.sh

as_root() {
    if [ "$EUID" -ne 0 ]; then
        printf "\n ❌  Run as root.\n ℹ️  Usage: sudo %s\n\n" "$0"
        exit 1
    fi
}

not_as_root() {
    if [ "$EUID" -eq 0 ]; then
        printf "\n ❌  Do not run as root.\n ℹ️  Usage: %s\n\n" "$0"
        exit 1
    fi
}

handle_ctrl_c() {
    printf "🛑 CTRL-C detected. Exiting.\n\n"
    exit 1
}

check_if_linux() {
    if [[ "$(uname)" != "Linux" ]]; then
        printf "This script is intended for Linux only.\n" >&2
        exit 1
    fi
}

update_and_upgrade() {
    local message="Updating and upgrading system... "
    printf "%s\n" "$message"
    export DEBIAN_FRONTEND=noninteractive
    apt -o Acquire::ForceIPv4=true update && apt upgrade -y
    check_status "$message" $?
    unset DEBIAN_FRONTEND
}

update_repo() {
    local message="Updating repository..."
    printf "%s\n" "$message"
    apt -o Acquire::ForceIPv4=true update
    check_status "$message" $?
}

install_packages() {
    printf "Installing %s...\n" "$*"
    export DEBIAN_FRONTEND=noninteractive
    apt install -y "$@"
    check_status "Package(s) installation: " $?
    unset DEBIAN_FRONTEND
    needrestart -r a
}

check_status() {
    if [[ $# -ne 2 ]]; then
        printf "💡 Cannot check status without a message and exit status.\n"
        printf "Usage: %s\n" "$(fstring "check_status <message> <exit_status>" "normal" "normal" "yellow")"
        return 1
    fi

    local message="$1"
    local exit_status="$2"

    if [[ "$exit_status" -eq 0 ]]; then
        printf "%s: %s\n" "$message" "$(fstring "SUCCESS ✅" "normal" "bold" "green")"
    else
        printf "%s: %s ❌\n" "$message" "$(fstring "FAILED" "normal" "bold" "red" "reverse")"
        return 1
    fi
}

printline() {
    local sep
    case "$1" in
        solid)     sep="─" ;;
        bullet)    sep="•" ;;
        ibeam)     sep="⌶" ;;
        star)      sep="★" ;;
        plus)      sep="✛" ;;
        diamond)   sep="◆" ;;
        dentistry) sep="⏥" ;;
        *)         sep="─" ;;
    esac
    printf -v line '%*s' "$(tput cols)" ''
    echo "${line// /$sep}"
}

fstring() {
    local string="${1:-}"
    local text_type="${2:-normal}"
    local font_weight="${3:-normal}"
    local font_color="${4:-}"
    local font_emphasis="${5:-normal}"
    local reset="\033[0m"
    local weight color linetype emphasis

    case "$text_type" in
        title)    linetype="dentistry"; string="🔹  $string"; font_weight="bold"; font_color="blue" ;;
        section)  linetype="solid";     string="🔸  $string"; font_weight="bold"; font_color="yellow" ;;
        warning)  linetype="solid";     string="⚠️  $string"; font_weight="bold"; font_color="red" ;;
        failure)  linetype="solid";     string="❌  $string"; font_weight="bold"; font_color="red"; font_emphasis="blink" ;;
        success)  linetype="solid";     string="✅  $string"; font_weight="bold"; font_color="green" ;;
        install)  linetype="solid";     string="📦  $string"; font_weight="bold"; font_color="yellow" ;;
        normal)   linetype="" ;;
        *)        linetype="" ;;
    esac

    case "$font_weight" in
        normal) weight=0 ;;
        bold)   weight=1 ;;
        light)  weight=2 ;;
        *)      weight=0 ;;
    esac

    case "$font_emphasis" in
        italics)   emphasis=3 ;;
        underline) emphasis=4 ;;
        blink)     emphasis=5 ;;
        reverse)   emphasis=7 ;;
        hidden)    emphasis=8 ;;
        *)         emphasis="$weight" ;;
    esac

    case "$font_color" in
        red)    color="\033[${weight};${emphasis};31m" ;;
        orange) color="\033[${weight};${emphasis};91m" ;;
        yellow) color="\033[${weight};${emphasis};33m" ;;
        green)  color="\033[${weight};${emphasis};32m" ;;
        blue)   color="\033[${weight};${emphasis};34m" ;;
        indigo) color="\033[${weight};${emphasis};94m" ;;
        violet) color="\033[${weight};${emphasis};35m" ;;
        white)  color="\033[${weight};${emphasis};97m" ;;
        black)  color="\033[${weight};${emphasis};30m" ;;
        *)      color="\033[${weight};${emphasis}m" ;;
    esac

    [[ -n "$linetype" ]] && printline "$linetype"
    printf "%b%s%b\n" "$color" "$string" "$reset"
}

if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    export OS_NAME="$NAME"
    export OS_VERSION="$VERSION"
    export OS_CODENAME="$VERSION_CODENAME"
    unset HOME_URL SUPPORT_URL BUG_REPORT_URL PRIVACY_POLICY_URL
fi
