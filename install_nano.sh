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
set -euo pipefail

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
# Copied from install_zsh_starship.sh rather than sourced, so this script stays
# a single self-contained file and works on macOS (linux/base_functions.sh is
# Linux-only).
printline() {
    local char="─" width
    width="$(tput cols 2>/dev/null || echo 80)"
    case "${1:-solid}" in
        solid)     char="─" ;;
        bullet)    char="•" ;;
        ibeam)     char="⌶" ;;
        star)      char="★" ;;
        plus)      char="+" ;;
        diamond)   char="◆" ;;
        dentistry) char="⚑" ;;
    esac
    printf '%*s\n' "$width" '' | tr ' ' "$char"
}

style_text() {
    local text="$1" weight="${2:-normal}" colour="${3:-}" seq=""
    case "$weight" in
        bold)   seq="1" ;;
        light)  seq="2" ;;
        normal) seq="0" ;;
    esac
    case "$colour" in
        red)    seq="$seq;31" ;;
        green)  seq="$seq;32" ;;
        yellow) seq="$seq;33" ;;
        blue)   seq="$seq;34" ;;
    esac
    printf '\033[%sm%s\033[0m\n' "$seq" "$text"
}

format_font() { style_text "$1" "${2:-normal}" "${3:-}"; }

log_step() { echo; printline; style_text "$1" "${2:-bold}" "${3:-yellow}"; }
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
main() {
    parse_args "$@"
    log_ok "skeleton only"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
