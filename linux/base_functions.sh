# shellcheck shell=bash
# ----------------------------------------------------------------------------
# base_functions.sh
#
# Shared helper library for the scripts in this repo.
# This file is meant to be SOURCED, not executed:
#     source base_functions.sh
#
# Provides:
#   - The repo-standard output theme: printline, style_text, format_font and
#     the log_info / log_step / log_ok / log_warn / log_err / log_title
#     helpers. Keep the theme in sync with install_zsh.sh (standalone).
#   - fstring: back-compat wrapper around the old output API.
#   - check_status, as_root, not_as_root, check_if_linux
#   - apt helpers: update_repo, update_and_upgrade, install_packages
#   - OS_NAME / OS_VERSION / OS_CODENAME exported from /etc/os-release
#   - A CTRL-C trap (installed at the bottom of this file)
#
# NOTE: Several functions call `exit` on error. Because this file is meant to
# be sourced by scripts, that terminates the *calling* script. That is
# intentional — but do not source this into an interactive shell and then
# call e.g. `as_root` unless you're prepared to have the shell exit.
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# Pretty output — repo-standard theme
# ----------------------------------------------------------------------------

# Decide once, at source time, whether to emit ANSI colors. Colors are
# skipped when stdout is not a terminal (pipes, logs, cron) or NO_COLOR is
# set, so captured output stays clean.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    QOL_COLOR=1
else
    QOL_COLOR=""
fi

# Print a separator line the width of the terminal.
# Usage: printline [solid|bullet|ibeam|star|plus|diamond|dentistry]
printline() {
    local sep cols line
    case "${1:-solid}" in
        solid)     sep="─" ;;   # ─────────────
        bullet)    sep="•" ;;   # •••••••••••••
        ibeam)     sep="⌶" ;;   # ⌶⌶⌶⌶⌶⌶⌶⌶⌶⌶⌶⌶
        star)      sep="★" ;;   # ★★★★★★★★★★★★★
        plus)      sep="✛" ;;   # ✛✛✛✛✛✛✛✛✛✛✛✛✛
        diamond)   sep="◆" ;;   # ◆◆◆◆◆◆◆◆◆◆◆◆◆
        dentistry) sep="⏥" ;;  # ⏥⏥⏥⏥⏥⏥⏥⏥
        *)         sep="─" ;;
    esac
    # Fall back to 80 columns when there is no TTY (cron, CI, pipes, etc.)
    cols="$(tput cols 2>/dev/null)" || cols=80
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
    printf -v line '%*s' "$cols" ''
    printf '%s\n' "${line// /$sep}"
}

# Print styled text with no separator. Also usable inline via command
# substitution: echo "I am a $(style_text "Raspberry Pi" bold red)."
# Usage: style_text "text" [normal|bold|light] [red|green|yellow|blue]
style_text() {
    local text="$1" weight="${2:-normal}" color="${3:-}"
    local weight_code color_code sgr
    case "$weight" in
        normal) weight_code=0 ;;
        bold)   weight_code=1 ;;
        light)  weight_code=2 ;;
        *)      weight_code=0 ;;
    esac
    case "$color" in
        red)    color_code=31 ;;
        green)  color_code=32 ;;
        yellow) color_code=33 ;;
        blue)   color_code=34 ;;
        *)      color_code="" ;;
    esac
    if [[ -z "$QOL_COLOR" ]] || [[ -z "$color_code" && "$weight_code" -eq 0 ]]; then
        printf '%s\n' "$text"
        return 0
    fi
    if [[ -n "$color_code" ]]; then
        sgr="${weight_code};${color_code}"
    else
        sgr="$weight_code"
    fi
    printf '\033[%sm%s\033[0m\n' "$sgr" "$text"
}

# Separator + styled text: the repo-standard log line.
# Usage: format_font "text" [weight] [color]
format_font() {
    printline
    style_text "$1" "${2:-bold}" "${3:-yellow}"
}

log_info() { format_font "ℹ️   $1" bold blue;   }
log_step() { format_font "📦  $1" bold yellow; }
log_ok()   { format_font "✅  $1" bold green;  }
log_warn() { format_font "⚠️   $1" bold yellow; }
log_err()  { format_font "❌  $1" bold red >&2; }

# Banner for script titles and completion messages.
log_title() {
    printline dentistry
    style_text "$1" bold blue
    printline dentistry
}

# ----------------------------------------------------------------------------
# Back-compat: the old fstring API. New scripts should call the log_*
# helpers directly. The old "emphasis" argument is no longer supported.
# Usage: fstring "text" [type] [weight] [color]
# ----------------------------------------------------------------------------
fstring() {
    local text="$1" text_type="${2:-normal}" weight="${3:-normal}" color="${4:-}"
    case "$text_type" in
        title)           log_title "$text" ;;
        section|install) log_step  "$text" ;;
        warning)         log_warn  "$text" ;;
        failure)         log_err   "$text" ;;
        success)         log_ok    "$text" ;;
        *)               style_text "$text" "$weight" "$color" ;;
    esac
}

# ----------------------------------------------------------------------------
# Status / safety helpers
# ----------------------------------------------------------------------------

# Report the result of the previous command.
# Usage: some_command; check_status "Description of step" $?
check_status() {
    if [ $# -ne 2 ]; then
        log_warn "check_status needs a message and an exit status. Usage: check_status <message> <exit_status>"
        return 1
    fi
    local message="$1" exit_status="$2"
    if [ "$exit_status" -eq 0 ]; then
        log_ok "$message: SUCCESS"
        return 0
    fi
    log_err "$message: FAILED (exit $exit_status)"
    return "$exit_status"
}

# Require the script to be run as root.
as_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        log_err "Run as root.  Usage: sudo $0"
        exit 1
    fi
}

# Require the script to NOT be run as root.
not_as_root() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        log_err "Do not run as root.  Usage: $0"
        exit 1
    fi
}

# Gracefully handle CTRL-C.
# NOTE: A trap is installed at the bottom of this file so this fires
# automatically in any script that sources base_functions.sh.
handle_ctrl_c() {
    echo
    log_err "Interrupted (CTRL-C). Exiting."
    exit 130
}

check_if_linux() {
    if [ "$(uname -s)" != "Linux" ]; then
        log_err "This script is intended for Linux only."
        exit 1
    fi
}

# ----------------------------------------------------------------------------
# apt helpers (Debian/Ubuntu-family)
# ----------------------------------------------------------------------------

# Refresh the package lists.
update_repo() {
    log_step "Updating package lists..."
    apt-get -o Acquire::ForceIPv4=true update
    check_status "apt-get update" $?
}

# Update package lists and upgrade all packages.
update_and_upgrade() {
    log_step "Updating and upgrading system..."
    DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::ForceIPv4=true update \
        && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::ForceIPv4=true upgrade -y
    check_status "System update and upgrade" $?
}

# Install one or more packages.
# Usage: install_packages package1 [package2 ...]
install_packages() {
    log_step "Installing: $*"
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
    local rc=$?
    # Restart services that need it, when needrestart is available.
    command -v needrestart >/dev/null 2>&1 && needrestart -r a
    check_status "Installing $*" "$rc"
}

# ----------------------------------------------------------------------------
# Environment
# ----------------------------------------------------------------------------

# Install the CTRL-C trap for any script that sources this library.
trap handle_ctrl_c INT

# Import the os-release file
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    export OS_NAME="$NAME"
    export OS_VERSION="$VERSION"
    export OS_CODENAME="$VERSION_CODENAME"
    # Avoid leaking the rest of os-release into the calling script's env.
    unset NAME VERSION VERSION_CODENAME VERSION_ID ID ID_LIKE PRETTY_NAME \
          ANSI_COLOR LOGO CPE_NAME HOME_URL SUPPORT_URL BUG_REPORT_URL \
          PRIVACY_POLICY_URL UBUNTU_CODENAME
fi
