#!/usr/bin/env bash
#
# install_zsh_starship.sh
#
# Installs zsh, the Starship prompt, MesloLGS Nerd Font (+ Symbols Only), and
# the plugins zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions.
#
# This is the Starship counterpart to install_zsh.sh, which installs the same
# stack around Oh My Zsh and Powerlevel10k instead. Pick one; they are not
# meant to coexist. If Oh My Zsh or Powerlevel10k is present, this script runs
# uninstall_omz_p10k.sh first (with a confirmation prompt) to clear them out.
#
# Starship replaces the prompt. It does not replace the rest of what Oh My Zsh
# provided, so this script also writes:
#   * a managed ~/.zshrc block with history defaults, completion styling, fzf
#     keybindings, and the plugin source lines
#   * ~/.config/zsh/git-aliases.zsh — the commonly used Oh My Zsh git aliases
#   * ~/.config/starship.toml — the "grove" powerline pill prompt
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
# Usage:  ./install_zsh_starship.sh
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
ZSH_PLUGIN_DIR="$HOME/.zsh/plugins"
STARSHIP_CONFIG="$HOME/.config/starship.toml"
GIT_ALIASES_FILE="$HOME/.config/zsh/git-aliases.zsh"
NERD_FONTS_VERSION="v3.3.0"
PLUGINS=(zsh-autosuggestions zsh-syntax-highlighting zsh-completions)
BLOCK_START="# >>> qol starship block >>>"
BLOCK_END="# <<< qol starship block <<<"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
# Remove Oh My Zsh / Powerlevel10k first
# ---------------------------------------------------------------------------
# Same pattern docker_install.sh uses with docker_uninstall.sh: source the
# uninstaller and call its function. Sourcing is inert — the uninstaller only
# runs anything when it is executed directly.
run_uninstaller() {
    local uninstaller="$SCRIPT_DIR/uninstall_omz_p10k.sh"

    if [[ ! -d "$HOME/.oh-my-zsh" && ! -f "$HOME/.p10k.zsh" ]]; then
        log_ok "No Oh My Zsh / Powerlevel10k install to remove."
        return 0
    fi
    if [[ ! -f "$uninstaller" ]]; then
        log_warn "Oh My Zsh / Powerlevel10k are installed, but uninstall_omz_p10k.sh is not
next to this script. Continuing — but the old prompt will fight the new one.
Get it from https://github.com/itdojo/qol."
        return 0
    fi

    log_step "Oh My Zsh / Powerlevel10k detected. Removing before installing Starship..."
    # shellcheck source=uninstall_omz_p10k.sh
    source "$uninstaller"

    local rc=0
    uninstall_omz_p10k || rc=$?
    case "$rc" in
        0)   return 0 ;;
        130) log_warn "Aborting install at user request."; exit 130 ;;
        *)   log_err "Uninstall failed (exit $rc). Stopping before Starship is installed."
             exit "$rc" ;;
    esac
}

# ---------------------------------------------------------------------------
# Starship
# ---------------------------------------------------------------------------
ensure_starship() {
    if command -v starship &>/dev/null; then
        log_ok "Starship is already installed ($(starship --version | head -1))."
        return
    fi
    log_step "Installing Starship..."
    if [[ "$OS" == "Darwin" ]]; then
        brew install starship
    else
        # Distro packages for starship are missing or stale on most releases,
        # so the official installer is the primary path, not a fallback.
        # It installs to /usr/local/bin, which needs root on a normal system.
        curl -fsSL https://starship.rs/install.sh | $SUDO sh -s -- --yes
    fi
    command -v starship &>/dev/null \
        || { log_err "Starship installed but 'starship' is not on PATH."; exit 1; }
    log_ok "Starship is installed ($(starship --version | head -1))."
}

# ---------------------------------------------------------------------------
# Plugins
# ---------------------------------------------------------------------------
# Plain git clones under ~/.zsh/plugins. Same layout on every OS, no plugin
# manager, no root. The .zshrc block sources them directly.
install_zsh_plugins() {
    log_step "Installing Zsh plugins into $ZSH_PLUGIN_DIR..."
    mkdir -p "$ZSH_PLUGIN_DIR"
    local plugin dest
    for plugin in "${PLUGINS[@]}"; do
        dest="$ZSH_PLUGIN_DIR/$plugin"
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
# Config file helpers
# ---------------------------------------------------------------------------
backup_file() {
    local f="$1" backup
    [[ -f "$f" ]] || return 0
    backup="$f.pre-starship.$(date +%Y%m%d-%H%M%S).bak"
    cp "$f" "$backup"
    log_info "Backed up $f → $backup"
}

# Overwrite dst with the contents of src, keeping dst's mode, owner and inode.
# `mv tmp dst` would be simpler but carries the temp file's permissions across —
# mktemp creates 0600, so that silently tightens a normal 0644 .zshrc.
replace_file_contents() {
    local src="$1" dst="$2"
    cat "$src" > "$dst"
    rm -f "$src"
}

# ---------------------------------------------------------------------------
# Git aliases
# ---------------------------------------------------------------------------
# Starship replaces the Oh My Zsh prompt but not the Oh My Zsh git plugin.
# These are the aliases most people actually reach for, kept verbatim.
write_git_aliases() {
    log_step "Writing $GIT_ALIASES_FILE..."
    mkdir -p "$(dirname "$GIT_ALIASES_FILE")"
    backup_file "$GIT_ALIASES_FILE"
    cat > "$GIT_ALIASES_FILE" <<'ALIASES'
# Git aliases — the commonly used subset of the Oh My Zsh `git` plugin, kept
# after the move to Starship. Sourced from the qol block in ~/.zshrc.
# Written by install_zsh_starship.sh; edits here are overwritten on rerun.

alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gb='git branch'
alias gba='git branch --all'
alias gbd='git branch --delete'
alias gc='git commit --verbose'
alias gcam='git commit --all --message'
alias gcb='git checkout -b'
alias gcl='git clone --recurse-submodules'
alias gco='git checkout'
alias gd='git diff'
alias gds='git diff --staged'
alias gf='git fetch'
alias gfa='git fetch --all --prune'
alias gl='git pull'
alias glog='git log --oneline --decorate --graph'
alias glol='git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset"'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gr='git remote'
alias grb='git rebase'
alias grbi='git rebase --interactive'
alias gst='git status'
alias gsta='git stash push'
alias gstp='git stash pop'
alias gsw='git switch'
alias gswc='git switch --create'

# Check out the repo's default branch, whatever it is called.
gcm() {
  local head
  head="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)" \
    && git checkout "${head##*/}" \
    || git checkout main 2>/dev/null \
    || git checkout master
}
ALIASES
    log_ok "$GIT_ALIASES_FILE written."
}

# ---------------------------------------------------------------------------
# Starship prompt config
# ---------------------------------------------------------------------------
# The "grove" pill prompt: powerline segments on a violet → moss → jade → orchid
# ramp, ending in a clock, with the prompt character on its own line below. Needs
# a Nerd Font for the separator and language glyphs.
write_starship_config() {
    log_step "Writing $STARSHIP_CONFIG..."
    mkdir -p "$(dirname "$STARSHIP_CONFIG")"
    backup_file "$STARSHIP_CONFIG"
    cat > "$STARSHIP_CONFIG" <<'TOML'
# Starship prompt — the "grove" pill style: powerline segments on a violet →
# moss → jade → orchid ramp, prompt character on its own line below.
# Written by install_zsh_starship.sh. Rerunning that script overwrites this
# file (after backing it up), so keep local tweaks somewhere you'll remember.
# Reference: https://starship.rs/config/

"$schema" = 'https://starship.rs/config-schema.json'

format = """
[](violet_deep)\
$os\
$hostname\
[](fg:violet_deep bg:violet)\
$directory\
[](fg:violet bg:moss_deep)\
$git_branch\
$git_status\
[](fg:moss_deep bg:moss)\
$c\
$rust\
$golang\
$nodejs\
$bun\
$php\
$java\
$kotlin\
$haskell\
$python\
$conda\
[](fg:moss)\
$line_break\
$character"""

palette = 'grove'

[os]
disabled = false
style = "bg:violet_deep fg:text"

[os.symbols]
Windows = ""
Ubuntu = "󰕈"
SUSE = ""
Raspbian = "󰐿"
Mint = "󰣭"
Macos = "󰀵"
Manjaro = ""
Linux = "󰌽"
Gentoo = "󰣨"
Fedora = "󰣛"
Alpine = ""
Amazon = ""
Android = ""
AOSC = ""
Arch = "󰣇"
Artix = "󰣇"
CentOS = ""
Debian = "󰣚"
Redhat = "󱄛"
RedHatEnterprise = "󱄛"

[hostname]
ssh_only = false
style = "bg:violet_deep fg:text"
format = '[ $hostname]($style)'
trim_at = "."

[directory]
style = "bg:violet fg:text"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = "󰝚 "
"Pictures" = " "
"Developer" = "󰲋 "

[git_branch]
symbol = ""
style = "bg:moss_deep"
format = '[[ $symbol $branch ](fg:text bg:moss_deep)]($style)'

[git_status]
style = "bg:moss_deep"
format = '[[($all_status$ahead_behind )](fg:text bg:moss_deep)]($style)'

[nodejs]
symbol = ""
style = "bg:moss"
format = '[[ $symbol( $version) ](fg:crust bg:moss)]($style)'

[bun]
symbol = ""
style = "bg:moss"
format = '[[ $symbol( $version) ](fg:crust bg:moss)]($style)'

[c]
symbol = " "
style = "bg:moss"
format = '[[ $symbol( $version) ](fg:crust bg:moss)]($style)'

[rust]
symbol = ""
style = "bg:moss"
format = '[[ $symbol( $version) ](fg:crust bg:moss)]($style)'

[golang]
symbol = ""
style = "bg:moss"
format = '[[ $symbol( $version) ](fg:crust bg:moss)]($style)'

[php]
symbol = ""
style = "bg:moss"
format = '[[ $symbol( $version) ](fg:crust bg:moss)]($style)'

[java]
symbol = " "
style = "bg:moss"
format = '[[ $symbol( $version) ](fg:crust bg:moss)]($style)'

[kotlin]
symbol = ""
style = "bg:moss"
format = '[[ $symbol( $version) ](fg:crust bg:moss)]($style)'

[haskell]
symbol = ""
style = "bg:moss"
format = '[[ $symbol( $version) ](fg:crust bg:moss)]($style)'

[python]
symbol = ""
style = "bg:moss"
format = '[[ $symbol( $version)(\(#$virtualenv\)) ](fg:crust bg:moss)]($style)'

[docker_context]
symbol = ""
style = "bg:jade"
format = '[[ $symbol( $context) ](fg:crust bg:jade)]($style)'

[conda]
symbol = "  "
style = "fg:crust bg:moss"
format = '[$symbol$environment ]($style)'
ignore_base = false

[line_break]
disabled = false

[character]
disabled = false
success_symbol = '[❯](bold fg:jade)'
error_symbol = '[❯](bold fg:danger)'
vimcmd_symbol = '[❮](bold fg:jade)'
vimcmd_replace_one_symbol = '[❮](bold fg:orchid)'
vimcmd_replace_symbol = '[❮](bold fg:orchid)'
vimcmd_visual_symbol = '[❮](bold fg:violet)'

[cmd_duration]
show_milliseconds = true
format = " in $duration "
style = "fg:crust bg:jade"
disabled = false
show_notifications = true
min_time_to_notify = 45000

[palettes.grove]
violet_deep = "#2e2447"
violet      = "#4c3d78"
orchid      = "#9b83c9"
moss_deep   = "#1f4634"
moss        = "#3f8f5c"
jade        = "#6fc98d"
text        = "#e6e1f2"
crust       = "#101018"
danger      = "#a8334a"

[palettes.catppuccin_mocha]
rosewater = "#f5e0dc"
flamingo = "#f2cdcd"
pink = "#f5c2e7"
mauve = "#cba6f7"
red = "#f38ba8"
maroon = "#eba0ac"
peach = "#fab387"
yellow = "#f9e2af"
green = "#a6e3a1"
teal = "#94e2d5"
sky = "#89dceb"
sapphire = "#74c7ec"
blue = "#89b4fa"
lavender = "#b4befe"
text = "#cdd6f4"
subtext1 = "#bac2de"
subtext0 = "#a6adc8"
overlay2 = "#9399b2"
overlay1 = "#7f849c"
overlay0 = "#6c7086"
surface2 = "#585b70"
surface1 = "#45475a"
surface0 = "#313244"
base = "#1e1e2e"
mantle = "#181825"
crust = "#11111b"

[palettes.catppuccin_frappe]
rosewater = "#f2d5cf"
flamingo = "#eebebe"
pink = "#f4b8e4"
mauve = "#ca9ee6"
red = "#e78284"
maroon = "#ea999c"
peach = "#ef9f76"
yellow = "#e5c890"
green = "#a6d189"
teal = "#81c8be"
sky = "#99d1db"
sapphire = "#85c1dc"
blue = "#8caaee"
lavender = "#babbf1"
text = "#c6d0f5"
subtext1 = "#b5bfe2"
subtext0 = "#a5adce"
overlay2 = "#949cbb"
overlay1 = "#838ba7"
overlay0 = "#737994"
surface2 = "#626880"
surface1 = "#51576d"
surface0 = "#414559"
base = "#303446"
mantle = "#292c3c"
crust = "#232634"

[palettes.catppuccin_latte]
rosewater = "#dc8a78"
flamingo = "#dd7878"
pink = "#ea76cb"
mauve = "#8839ef"
red = "#d20f39"
maroon = "#e64553"
peach = "#fe640b"
yellow = "#df8e1d"
green = "#40a02b"
teal = "#179299"
sky = "#04a5e5"
sapphire = "#209fb5"
blue = "#1e66f5"
lavender = "#7287fd"
text = "#4c4f69"
subtext1 = "#5c5f77"
subtext0 = "#6c6f85"
overlay2 = "#7c7f93"
overlay1 = "#8c8fa1"
overlay0 = "#9ca0b0"
surface2 = "#acb0be"
surface1 = "#bcc0cc"
surface0 = "#ccd0da"
base = "#eff1f5"
mantle = "#e6e9ef"
crust = "#dce0e8"

[palettes.catppuccin_macchiato]
rosewater = "#f4dbd6"
flamingo = "#f0c6c6"
pink = "#f5bde6"
mauve = "#c6a0f6"
red = "#ed8796"
maroon = "#ee99a0"
peach = "#f5a97f"
yellow = "#eed49f"
green = "#a6da95"
teal = "#8bd5ca"
sky = "#91d7e3"
sapphire = "#7dc4e4"
blue = "#8aadf4"
lavender = "#b7bdf8"
text = "#cad3f5"
subtext1 = "#b8c0e0"
subtext0 = "#a5adcb"
overlay2 = "#939ab7"
overlay1 = "#8087a2"
overlay0 = "#6e738d"
surface2 = "#5b6078"
surface1 = "#494d64"
surface0 = "#363a4f"
base = "#24273a"
mantle = "#1e2030"
crust = "#181926"
TOML
    log_ok "$STARSHIP_CONFIG written."
}

# ---------------------------------------------------------------------------
# .zshrc managed block
# ---------------------------------------------------------------------------
# Everything this script adds to .zshrc lives between BLOCK_START and BLOCK_END
# and is rewritten in full on every run. That is what makes reruns idempotent:
# there is never more than one block, and never a stale line inside one.
remove_managed_block() {
    local file="$1" tmp
    grep -qF "$BLOCK_START" "$file" || return 0
    tmp="$(mktemp)"
    awk -v s="$BLOCK_START" -v e="$BLOCK_END" '
        index($0, s) { skip = 1 }
        !skip { print }
        index($0, e) { skip = 0 }
    ' "$file" > "$tmp"
    replace_file_contents "$tmp" "$file"
}

update_zshrc() {
    log_step "Updating $ZSHRC..."
    [[ -f "$ZSHRC" ]] || touch "$ZSHRC"
    backup_file "$ZSHRC"
    remove_managed_block "$ZSHRC"

    # Only add compinit if the user's own config does not already run it.
    # Running it twice is slow and can produce duplicate completion warnings.
    local compinit_line
    if grep -qE '^[[:space:]]*compinit' "$ZSHRC"; then
        compinit_line="# compinit already runs elsewhere in this file — not duplicated here."
    else
        compinit_line='autoload -Uz compinit && compinit'
    fi

    # Write paths as a literal $HOME rather than an expanded one, so the same
    # .zshrc works on a machine where $HOME differs (macOS /Users/x vs
    # Linux /home/x). zsh expands them at load time.
    local plugin_dir_lit="${ZSH_PLUGIN_DIR/#$HOME/\$HOME}"
    local aliases_lit="${GIT_ALIASES_FILE/#$HOME/\$HOME}"

    cat >> "$ZSHRC" <<EOF

$BLOCK_START
# Managed by install_zsh_starship.sh — this whole block is rewritten on rerun.

# zsh-completions must be on fpath before compinit runs.
fpath+=("$plugin_dir_lit/zsh-completions/src")
$compinit_line

# History — replaces the defaults Oh My Zsh used to set.
HISTFILE="\$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY        # record timestamps
setopt SHARE_HISTORY           # share history across running shells
setopt INC_APPEND_HISTORY      # write as you go, not only on exit
setopt HIST_IGNORE_ALL_DUPS    # drop older duplicates
setopt HIST_IGNORE_SPACE       # a leading space keeps a command out of history
setopt HIST_VERIFY             # expand !! for review instead of running it
setopt HIST_REDUCE_BLANKS

# Completion behaviour and navigation
setopt AUTO_CD
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "\${(s.:.)LS_COLORS}"
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'

# fzf keybindings (ctrl-R history, ctrl-T files). Oh My Zsh's fzf plugin used
# to wire these up. Skipped entirely when something earlier in this file already
# did it — double-sourcing works but is wasted startup time. 'fzf --zsh' needs
# fzf 0.48+; older versions ship the same bindings as files next to the binary.
if [[ -o interactive ]] && command -v fzf &>/dev/null && ! (( \${+widgets[fzf-history-widget]} )); then
  if fzf --zsh >/dev/null 2>&1; then
    source <(fzf --zsh)
  else
    [[ -r /opt/homebrew/opt/fzf/shell/key-bindings.zsh ]] && source /opt/homebrew/opt/fzf/shell/key-bindings.zsh
    [[ -r /usr/share/doc/fzf/examples/key-bindings.zsh ]] && source /usr/share/doc/fzf/examples/key-bindings.zsh
    [[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
  fi
fi

# Git aliases carried over from the Oh My Zsh git plugin.
[[ -r "$aliases_lit" ]] && source "$aliases_lit"

# Plugins. zsh-syntax-highlighting must be sourced last — that is the plugin's
# documented requirement, not a stylistic choice.
[[ -r "$plugin_dir_lit/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && source "$plugin_dir_lit/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -r "$plugin_dir_lit/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && source "$plugin_dir_lit/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# Prompt.
command -v starship &>/dev/null && eval "\$(starship init zsh)"
$BLOCK_END
EOF

    if command -v zsh &>/dev/null && ! zsh -n "$ZSHRC" 2>/dev/null; then
        log_err "$ZSHRC failed 'zsh -n' after the update. Restoring the newest backup."
        # The backup timestamp is YYYYmmdd-HHMMSS, so lexical glob order is
        # chronological order — the last match is the newest.
        local newest="" f
        for f in "$ZSHRC".pre-starship.*.bak; do
            [[ -e "$f" ]] && newest="$f"
        done
        [[ -n "$newest" ]] && cp "$newest" "$ZSHRC"
        exit 1
    fi

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

    run_uninstaller         # Oh My Zsh / Powerlevel10k must go before Starship
    ensure_starship
    install_zsh_plugins
    install_nerd_fonts
    write_git_aliases
    write_starship_config
    update_zshrc
    change_default_shell

    format_font "Prompt config:  ~/.config/starship.toml   (docs: https://starship.rs/config/)
Git aliases:    ~/.config/zsh/git-aliases.zsh
Plugins:        ~/.zsh/plugins/
If glyphs render as boxes, set your terminal font to 'MesloLGS NF'." normal blue
    format_font "Install complete. Please restart your terminal." bold green
    echo
}

main "$@"
