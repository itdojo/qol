#!/usr/bin/env bash
#
# install_nano.sh — set up GNU nano for people who actually edit in it.
#
# Installs GNU nano (Homebrew on macOS, the distro package manager on Linux),
# probes the resulting binary for which rc directives it supports, and writes a
# managed block into ~/.nanorc with syntax highlighting, line numbers, sane
# indentation and a ^S save binding.
#
# Usage:
#   ./install_nano.sh                 # install and configure
#   ./install_nano.sh --dry-run       # print the plan, change nothing
#   ./install_nano.sh --no-syntax     # skip the community syntax pack clone
#
# macOS note: /usr/bin/nano is not nano. It is UW PICO 5.09, which has no
# syntax highlighting and none of the modern rc directives. This script
# installs the real GNU nano via Homebrew and refuses to write a config if
# PATH still resolves `nano` to /usr/bin/nano.
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BLOCK_START="# >>> qol nano block >>>"
BLOCK_END="# <<< qol nano block <<<"

NANORC="$HOME/.nanorc"
SYNTAX_DIR="$HOME/.nano"
SYNTAX_REPO="https://github.com/scopatz/nanorc"
MIN_NANO_VERSION="4.0"

DRY_RUN=""
ASSUME_YES=""
NO_SYNTAX=""
SET_EDITOR=""

# ---------------------------------------------------------------------------
# Output theme
# ---------------------------------------------------------------------------
# Copied from install_zsh_starship.sh (not sourced), so this script stays a
# single self-contained file and works on macOS (linux/base_functions.sh is
# Linux-only). Keep in sync with that copy if the shared theme changes.

# Decide once whether to emit ANSI colors. Colors are skipped when stdout is
# not a terminal (pipes, logs, cron) or NO_COLOR is set.
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

# Print styled text with no separator (usable inline via command substitution).
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
format_font() {
    printline
    style_text "$1" "${2:-bold}" "${3:-yellow}"
}

# log_step is format_font under another name — kept as a distinct function so
# call sites read as "this is a phase heading," not "this is generic output."
# It must not call printline itself, or every step would print two rules.
log_step() { format_font "$1" "${2:-bold}" "${3:-yellow}"; }
log_info() { format_font "ℹ️   $1" bold blue; }
log_ok()   { format_font "✅  $1" bold green; }
log_warn() { format_font "⚠️   $1" bold yellow; }
log_err()  { format_font "❌  $1" bold red >&2; }

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
usage() {
    cat <<'USAGE'
install_nano.sh — set up GNU nano with syntax highlighting and sane defaults.

Usage: ./install_nano.sh [options]

  -n, --dry-run      Print every action; write nothing.
  -y, --yes          Skip confirmation prompts.
      --no-syntax    Skip cloning the community syntax pack (offline machines).
                     The syntax definitions shipped with nano are still used.
      --set-editor   Also export EDITOR=nano and VISUAL=nano into your shell rc.
  -h, --help         Show this message.
USAGE
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|-n)  DRY_RUN=1 ;;
            --yes|-y)      ASSUME_YES=1 ;;
            --no-syntax)   NO_SYNTAX=1 ;;
            --set-editor)  SET_EDITOR=1 ;;
            --help|-h)     usage; exit 0 ;;
            *)             log_err "Unknown option: $1"; usage >&2; exit 2 ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------------------
# nano detection
# ---------------------------------------------------------------------------
# True when HAVE is the same version as WANT or newer. Sorting both numerically
# and taking the first line means WANT sorts first in exactly the cases we want
# to accept, including the equal case. A plain string compare would put "10.0"
# below "9.1"; `sort -V` would handle that but is not on macOS's BSD sort.
version_at_least() {
    local have="$1" want="$2" first
    first="$(printf '%s\n%s\n' "$want" "$have" \
        | sort -t. -k1,1n -k2,2n -k3,3n | head -1)"
    [[ "$first" == "$want" ]]
}

# Print the bare version of a GNU nano binary, or fail.
#
# TERM=dumb and </dev/null are load-bearing, not defensive. macOS's
# /usr/bin/nano is UW PICO, which does not understand --version and will open
# a full-screen editor. Under TERM=dumb with stdin closed it bails out with
# "Incomplete terminfo entry" instead. GNU nano prints its version and exits
# before it ever calls initscr(), so it is unaffected.
nano_version() {
    local bin="$1" line
    [[ -x "$bin" ]] || return 1
    line="$(TERM=dumb "$bin" --version </dev/null 2>&1 | head -1)" || return 1
    case "$line" in
        *"GNU nano"*) ;;
        *) return 1 ;;
    esac
    printf '%s\n' "$line" \
        | sed -E 's/.*GNU nano,? version ([0-9][0-9.]*).*/\1/'
}

# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    log_ok "skeleton only"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # set -euo pipefail lives here, not at file scope: `source` runs in the
    # caller's shell, and tests/test-install-nano.sh sources this file under
    # its own `set -uo pipefail`. A top-level `set -e` would leak `-e` into
    # the test harness and let a single failing assertion kill the whole
    # suite silently instead of reporting a FAIL line.
    set -euo pipefail
    main "$@"
fi
