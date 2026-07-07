#!/usr/bin/env bash
#
# install-nerd-fonts.sh
#
# Installs Nerd Fonts on macOS via Homebrew casks. Idempotent: fonts that
# are already installed are skipped, and a single failing font does not
# abort the rest of the list.
#
# Edit FONTS below to choose which fonts get installed; the commented
# entries are additional known cask names you can enable.
#
# Usage: ./install-nerd-fonts.sh
# ----------------------------------------------------------------------------

set -eo pipefail

# ---------------------------------------------------------------------------
# Pretty output — repo-standard theme (keep in sync with linux/base_functions.sh)
# ---------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    QOL_COLOR=1
else
    QOL_COLOR=""
fi

printline() {
    local sep cols line
    case "${1:-solid}" in
        solid)     sep="─" ;;
        dentistry) sep="⏥" ;;
        *)         sep="─" ;;
    esac
    cols="$(tput cols 2>/dev/null)" || cols=80
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
    printf -v line '%*s' "$cols" ''
    printf '%s\n' "${line// /$sep}"
}

style_text() {
    local text="$1" weight="${2:-normal}" color="${3:-}"
    local weight_code color_code sgr
    case "$weight" in
        normal) weight_code=0 ;;
        bold)   weight_code=1 ;;
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

format_font() {
    printline
    style_text "$1" "${2:-bold}" "${3:-yellow}"
}

log_info() { format_font "ℹ️   $1" bold blue;   }
log_step() { format_font "📦  $1" bold yellow; }
log_ok()   { format_font "✅  $1" bold green;  }
log_warn() { format_font "⚠️   $1" bold yellow; }
log_err()  { format_font "❌  $1" bold red >&2; }

handle_ctrl_c() {
    echo
    log_err "Interrupted. Exiting."
    exit 130
}
trap handle_ctrl_c INT

# ---------------------------------------------------------------------------
# Fonts to install (Homebrew cask names)
# ---------------------------------------------------------------------------
FONTS=(
    font-meslo-lg-nerd-font
    font-meslo-for-powerlevel10k
    font-fira-mono-nerd-font
    font-droid-sans-mono-nerd-font
    font-fira-code-nerd-font
    font-hack-nerd-font
    # font-3270-nerd-font
    # font-inconsolata-go-nerd-font
    # font-inconsolata-lgc-nerd-font
    # font-inconsolata-nerd-font
    # font-monofur-nerd-font
    # font-overpass-nerd-font
    # font-ubuntu-mono-nerd-font
    # font-agave-nerd-font
    # font-arimo-nerd-font
    # font-anonymice-nerd-font
    # font-aurulent-sans-mono-nerd-font
    # font-bigblue-terminal-nerd-font
    # font-bitstream-vera-sans-mono-nerd-font
    # font-blex-mono-nerd-font
    # font-caskaydia-cove-nerd-font
    # font-code-new-roman-nerd-font
    # font-cousine-nerd-font
    # font-daddy-time-mono-nerd-font
    # font-dejavu-sans-mono-nerd-font
    # font-fantasque-sans-mono-nerd-font
    # font-go-mono-nerd-font
    # font-gohufont-nerd-font
    # font-hasklug-nerd-font
    # font-heavy-data-nerd-font
    # font-hurmit-nerd-font
    # font-im-writing-nerd-font
    # font-iosevka-nerd-font
    # font-jetbrains-mono-nerd-font
    # font-lekton-nerd-font
    # font-liberation-nerd-font
    # font-monoid-nerd-font
    # font-mononoki-nerd-font
    # font-mplus-nerd-font
    # font-noto-nerd-font
    # font-open-dyslexic-nerd-font
    # font-profont-nerd-font
    # font-proggy-clean-tt-nerd-font
    # font-roboto-mono-nerd-font
    # font-sauce-code-pro-nerd-font
    # font-shure-tech-mono-nerd-font
    # font-space-mono-nerd-font
    # font-terminess-ttf-nerd-font
    # font-tinos-nerd-font
    # font-ubuntu-nerd-font
    # font-victor-mono-nerd-font
)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_err "This script is macOS-only (it installs fonts with Homebrew casks)."
        exit 1
    fi
    if ! command -v brew >/dev/null 2>&1; then
        log_err "Homebrew is required. Install it from https://brew.sh and re-run."
        exit 1
    fi

    local failed=() font
    for font in "${FONTS[@]}"; do
        if brew list --cask "$font" >/dev/null 2>&1; then
            log_ok "$font is already installed."
            continue
        fi
        log_step "Installing $font..."
        if brew install --cask "$font"; then
            log_ok "$font installed."
        else
            log_warn "$font failed to install; continuing with the rest."
            failed+=("$font")
        fi
    done

    if (( ${#failed[@]} > 0 )); then
        log_warn "Done, but these fonts failed to install: ${failed[*]}"
        exit 1
    fi
    log_ok "All Nerd Fonts are installed."
}

main "$@"
