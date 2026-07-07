#!/usr/bin/env bash
#
# install_zsh.sh
#
# Installs zsh, Oh My Zsh, Powerlevel10k, MesloLGS Nerd Font (+ Symbols Only),
# and the plugins zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions.
#
# Targets:
#   - macOS                       (Homebrew)
#   - Debian / Ubuntu / Pi OS     (apt-get)
#   - Fedora / RHEL / Rocky / Alma (dnf)
#   - Arch / Manjaro              (pacman)
#   - Alpine                       (apk)
#   - openSUSE                    (zypper)
#
# Architecture-agnostic: x86_64, arm64/aarch64, armv7l (Pi, Gateworks, etc).
#
# Usage:  ./install_zsh.sh
# Do not run as root.
#
# The script is idempotent: rerunning it should not duplicate config or fail.
# ----------------------------------------------------------------------------

set -eo pipefail

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
OS="$(uname -s)"
ARCH="$(uname -m)"
PKG_MGR=""
SUDO=""
ZSHRC="$HOME/.zshrc"
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
NERD_FONTS_VERSION="v3.3.0"
PLUGINS=(zsh-autosuggestions zsh-syntax-highlighting zsh-completions)

# ---------------------------------------------------------------------------
# Pretty output — repo-standard theme (keep in sync with linux/base_functions.sh)
# ---------------------------------------------------------------------------
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

log_info() { format_font "ℹ️   $1" bold blue;   }
log_step() { format_font "📦  $1" bold yellow; }
log_ok()   { format_font "✅  $1" bold green;  }
log_warn() { format_font "⚠️   $1" bold yellow; }
log_err()  { format_font "❌  $1" bold red >&2; }

# ---------------------------------------------------------------------------
# Safety
# ---------------------------------------------------------------------------
handle_ctrl_c() {
    echo
    log_err "Interrupted. Exiting."
    exit 130
}
trap handle_ctrl_c INT

handle_err() {
    local exit_code=$?
    log_err "Error on line $1 (exit $exit_code). Aborting."
    exit "$exit_code"
}
trap 'handle_err $LINENO' ERR

check_for_root() {
    if [[ $EUID -eq 0 ]]; then
        log_err "Do not run as root. You'll be prompted for sudo if needed."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Package manager detection
# ---------------------------------------------------------------------------
detect_package_manager() {
    if [[ "$OS" == "Darwin" ]]; then
        PKG_MGR="brew"
        return
    fi
    for cmd in apt-get dnf pacman apk zypper; do
        if command -v "$cmd" &>/dev/null; then
            PKG_MGR="$cmd"
            return
        fi
    done
    log_err "No supported package manager found (apt-get, dnf, pacman, apk, zypper, brew)."
    exit 1
}

setup_sudo() {
    if [[ "$OS" != "Darwin" ]] && command -v sudo &>/dev/null; then
        SUDO="sudo"
    fi
}

pkg_install() {
    local pkgs=("$@")
    case "$PKG_MGR" in
        brew)
            for p in "${pkgs[@]}"; do
                brew list --formula "$p" &>/dev/null || brew install "$p"
            done
            ;;
        apt-get)
            $SUDO apt-get update -qq
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}"
            ;;
        dnf)
            $SUDO dnf install -y "${pkgs[@]}"
            ;;
        pacman)
            $SUDO pacman -Sy --noconfirm --needed "${pkgs[@]}"
            ;;
        apk)
            $SUDO apk add --no-cache "${pkgs[@]}"
            ;;
        zypper)
            $SUDO zypper install -y "${pkgs[@]}"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Homebrew (macOS only) — must happen before anything that calls brew
# ---------------------------------------------------------------------------
ensure_homebrew() {
    [[ "$OS" == "Darwin" ]] || return 0
    if ! command -v brew &>/dev/null; then
        log_step "Installing Homebrew..."
        NONINTERACTIVE=1 /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if   [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -x /usr/local/bin/brew    ]]; then eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi
    log_ok "Homebrew is installed."
}

# ---------------------------------------------------------------------------
# Generic tool installer (idempotent)
# ---------------------------------------------------------------------------
ensure_tool() {
    local tool="$1" pkg="${2:-$1}"
    if command -v "$tool" &>/dev/null; then
        log_ok "$tool is already installed."
        return
    fi
    log_step "Installing $tool..."
    pkg_install "$pkg"
    log_ok "$tool is installed."
}

# ---------------------------------------------------------------------------
# Oh My Zsh
# ---------------------------------------------------------------------------
ensure_oh_my_zsh() {
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        log_ok "Oh My Zsh is already installed."
        return
    fi
    log_step "Installing Oh My Zsh..."
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        "" --unattended
    log_ok "Oh My Zsh is installed."
}

# ---------------------------------------------------------------------------
# Powerlevel10k
# ---------------------------------------------------------------------------
install_powerlevel10k() {
    local p10k_dir="$ZSH_CUSTOM_DIR/themes/powerlevel10k"
    if [[ -d "$p10k_dir/.git" ]]; then
        log_info "Powerlevel10k already cloned; pulling latest..."
        git -C "$p10k_dir" pull --ff-only --quiet || log_warn "p10k pull failed; continuing."
    else
        log_step "Cloning Powerlevel10k..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
    fi
    log_ok "Powerlevel10k is installed."
}

# ---------------------------------------------------------------------------
# Plugins
# ---------------------------------------------------------------------------
install_zsh_plugins() {
    log_step "Installing Zsh plugins..."
    local plugin dest
    for plugin in "${PLUGINS[@]}"; do
        dest="$ZSH_CUSTOM_DIR/plugins/$plugin"
        if [[ -d "$dest/.git" ]]; then
            log_info "$plugin already cloned; pulling latest..."
            git -C "$dest" pull --ff-only --quiet || log_warn "$plugin pull failed."
        else
            git clone --depth=1 "https://github.com/zsh-users/$plugin.git" "$dest"
        fi
    done
    log_ok "Zsh plugins are installed."
}

# ---------------------------------------------------------------------------
# Nerd Fonts
# ---------------------------------------------------------------------------
install_nerd_fonts() {
    log_step "Installing Nerd Fonts (MesloLGS NF + Symbols Only)..."
    if [[ "$OS" == "Darwin" ]]; then
        # Modern homebrew-cask carries fonts in the main cask repo.
        brew install --cask font-meslo-lg-nerd-font font-symbols-only-nerd-font \
            || log_warn "One or more font casks failed to install."
    else
        local fonts_dir="$HOME/.local/share/fonts"
        mkdir -p "$fonts_dir"
        local meslo_url="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/Meslo.zip"
        local symbols_url="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/NerdFontsSymbolsOnly.zip"
        local tmp; tmp="$(mktemp -d)"

        ensure_tool unzip
        ensure_tool fc-cache fontconfig

        log_info "Downloading Meslo Nerd Font (${NERD_FONTS_VERSION})..."
        curl -fSL "$meslo_url"   -o "$tmp/Meslo.zip"
        log_info "Downloading Nerd Fonts Symbols Only (${NERD_FONTS_VERSION})..."
        curl -fSL "$symbols_url" -o "$tmp/Symbols.zip"

        unzip -oq "$tmp/Meslo.zip"   -d "$fonts_dir/"
        unzip -oq "$tmp/Symbols.zip" -d "$fonts_dir/"
        rm -rf "$tmp"

        fc-cache -f "$fonts_dir" >/dev/null
    fi
    log_ok "Nerd Fonts are installed."
}

# ---------------------------------------------------------------------------
# .zshrc editing helpers (idempotent)
# ---------------------------------------------------------------------------
ensure_line_in_file() {
    local line="$1" file="$2"
    [[ -f "$file" ]] || touch "$file"
    grep -qxF "$line" "$file" || printf '%s\n' "$line" >> "$file"
}

# Replace `plugins=( ... )` block (single- or multi-line) with one canonical line.
replace_plugins_block() {
    local file="$1" new_line="$2" tmp
    tmp="$(mktemp)"
    awk -v new="$new_line" '
        BEGIN { skip = 0; replaced = 0 }
        /^plugins=\(/ {
            if (!replaced) { print new; replaced = 1 }
            if ($0 ~ /\)/) { next }
            skip = 1; next
        }
        skip {
            if ($0 ~ /\)/) { skip = 0 }
            next
        }
        { print }
        END {
            if (!replaced) { print new }
        }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}

cleanup_legacy_zshrc() {
    # Sweep up artifacts left by older versions of this script so reruns are clean:
    #   * stray `source .../powerlevel10k.zsh-theme` line that pointed at a
    #     non-existent brew path on macOS
    #   * duplicate `set -o AUTO_CD` lines appended on every previous run
    [[ -f "$ZSHRC" ]] || return 0
    local tmp; tmp="$(mktemp)"
    awk '
        # Drop any line that sources a powerlevel10k.zsh-theme outside our $ZSH_CUSTOM
        # tree. The new install loads p10k via the Oh My Zsh ZSH_THEME setting.
        /^[[:space:]]*source[[:space:]].*powerlevel10k\.zsh-theme/ { next }
        # Collapse repeated `set -o AUTO_CD` lines down to zero (we add `setopt AUTO_CD` later).
        /^[[:space:]]*set[[:space:]]+-o[[:space:]]+AUTO_CD[[:space:]]*$/ { next }
        { print }
    ' "$ZSHRC" > "$tmp"
    mv "$tmp" "$ZSHRC"
}

update_zshrc() {
    log_step "Updating $ZSHRC..."
    [[ -f "$ZSHRC" ]] || touch "$ZSHRC"

    # One-time backup with timestamp (don't clobber existing backups).
    if ! ls "$ZSHRC".preinstall_zsh.* &>/dev/null; then
        cp "$ZSHRC" "$ZSHRC.preinstall_zsh.$(date +%Y%m%d-%H%M%S).bak"
    fi

    cleanup_legacy_zshrc

    # Theme
    if grep -q '^ZSH_THEME=' "$ZSHRC"; then
        # Portable in-place edit: sed to a temp file then mv (works on BSD + GNU sed).
        local tmp; tmp="$(mktemp)"
        sed 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC" > "$tmp"
        mv "$tmp" "$ZSHRC"
    else
        ensure_line_in_file 'ZSH_THEME="powerlevel10k/powerlevel10k"' "$ZSHRC"
    fi

    # Plugins
    replace_plugins_block "$ZSHRC" \
        'plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)'

    # zsh-completions needs to be on fpath BEFORE compinit runs.
    # Oh My Zsh runs compinit in oh-my-zsh.sh, so we add this BEFORE the
    # `source $ZSH/oh-my-zsh.sh` line if possible, otherwise just append.
    local fpath_line='fpath+=("'"$ZSH_CUSTOM_DIR"'/plugins/zsh-completions/src")'
    if ! grep -qxF "$fpath_line" "$ZSHRC"; then
        if grep -q '^source \$ZSH/oh-my-zsh.sh' "$ZSHRC"; then
            local tmp; tmp="$(mktemp)"
            awk -v line="$fpath_line" '
                /^source \$ZSH\/oh-my-zsh\.sh/ && !done { print line; done = 1 }
                { print }
            ' "$ZSHRC" > "$tmp"
            mv "$tmp" "$ZSHRC"
        else
            printf '%s\n' "$fpath_line" >> "$ZSHRC"
        fi
    fi

    # Quality-of-life options
    ensure_line_in_file 'setopt AUTO_CD' "$ZSHRC"

    log_ok "$ZSHRC updated."
}

# ---------------------------------------------------------------------------
# Default shell
# ---------------------------------------------------------------------------
change_default_shell() {
    local zsh_path
    zsh_path="$(command -v zsh)" || { log_warn "zsh not on PATH; skipping chsh."; return; }

    if [[ "${SHELL:-}" == "$zsh_path" ]]; then
        log_ok "Default shell is already zsh."
        return
    fi

    # Some distros refuse chsh to a shell that isn't in /etc/shells.
    if [[ -f /etc/shells ]] && ! grep -qxF "$zsh_path" /etc/shells; then
        log_info "Registering $zsh_path in /etc/shells..."
        echo "$zsh_path" | $SUDO tee -a /etc/shells >/dev/null || true
    fi

    log_step "Changing default shell to zsh ($zsh_path). You may be prompted for your password."
    if chsh -s "$zsh_path"; then
        log_ok "Default shell changed to zsh."
    else
        log_warn "chsh failed. You can change it manually with:  chsh -s $zsh_path"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    check_for_root
    detect_package_manager
    setup_sudo

    log_info "OS=$OS  ARCH=$ARCH  PKG_MGR=$PKG_MGR"

    ensure_homebrew         # macOS: bootstrap brew BEFORE anything that uses it

    # Core dependencies
    ensure_tool git
    ensure_tool curl
    ensure_tool wget
    ensure_tool zsh

    ensure_oh_my_zsh
    install_powerlevel10k
    install_zsh_plugins
    install_nerd_fonts
    update_zshrc
    change_default_shell

    format_font "After restarting your terminal, the Powerlevel10k setup wizard will run.
Run 'p10k configure' any time to reconfigure your prompt.
If glyphs render as boxes, set your terminal font to 'MesloLGS NF'." normal blue
    format_font "Install complete. Please restart your terminal." bold green
    echo
}

main "$@"
