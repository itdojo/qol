#!/usr/bin/env bash
#
# uninstall_omz_p10k.sh
#
# Removes Oh My Zsh and Powerlevel10k and strips their references out of
# ~/.zshrc. Your own .zshrc content is preserved: the file is edited line by
# line, not replaced, and a timestamped backup is taken first.
#
# Targets:
#   - macOS                       (also removes the brew powerlevel10k formula
#                                  and the font-meslo-for-powerlevel10k cask)
#   - Debian / Ubuntu             (and, incidentally, any other Linux — the
#                                  removal is almost entirely home-directory
#                                  paths)
#
# Usage:
#   ./uninstall_omz_p10k.sh                # confirm, then remove
#   ./uninstall_omz_p10k.sh --dry-run      # print the plan, change nothing
#   ./uninstall_omz_p10k.sh --yes          # no prompt (for automation)
#
#   source uninstall_omz_p10k.sh           # from another script
#   uninstall_omz_p10k                     # ...then call the function
#
# Return codes from uninstall_omz_p10k:
#   0   = removed, nothing to remove, or user kept the install ('n')
#   1   = failed (the .zshrc edit did not survive its syntax check and was
#         rolled back; nothing else was touched)
#   130 = user chose 'q' (the caller should abort)
#
# This script deliberately does NOT run ~/.oh-my-zsh/tools/uninstall.sh. That
# one restores ~/.zshrc.pre-oh-my-zsh, which on most machines is a handful of
# lines written the day Oh My Zsh was installed — everything added since would
# be lost. Do not run as root.
# ----------------------------------------------------------------------------

set -eo pipefail

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
OS="$(uname -s)"
ZSHRC="${ZSHRC:-$HOME/.zshrc}"
OMZ_DIR="$HOME/.oh-my-zsh"
P10K_RC="$HOME/.p10k.zsh"
DRY_RUN=""
ASSUME_YES=""
FOUND_PATHS=()
FOUND_ZSHRC=""
FOUND_BREW=()

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

usage() {
    cat <<'USAGE'
Usage: uninstall_omz_p10k.sh [options]

Removes Oh My Zsh and Powerlevel10k, and strips their lines out of ~/.zshrc.
Your own .zshrc content is preserved and the file is backed up first.

Options:
  -n, --dry-run   Print exactly what would be removed, then exit. No changes.
  -y, --yes       Skip the confirmation prompt.
  -h, --help      Show this help.
USAGE
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes|-y)     ASSUME_YES=1 ;;
            --dry-run|-n) DRY_RUN=1 ;;
            --help|-h)    usage; exit 0 ;;
            *)            log_err "Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------
# Populates FOUND_PATHS / FOUND_ZSHRC / FOUND_BREW.
# Returns non-zero when there is nothing to do.
omz_p10k_present() {
    FOUND_PATHS=()
    FOUND_ZSHRC=""
    FOUND_BREW=()

    local p
    for p in "$OMZ_DIR" "$P10K_RC" "$HOME/.cache/gitstatus" "$HOME/.cache/p10k-$USER"; do
        [[ -e "$p" ]] && FOUND_PATHS+=("$p")
    done
    # Globs that may match nothing; the -e test filters the literal pattern out.
    for p in "$HOME"/.cache/p10k-*.zsh "$HOME"/.cache/p10k-*.zsh.zwc "$HOME"/.zcompdump*; do
        [[ -e "$p" ]] && FOUND_PATHS+=("$p")
    done

    if [[ -f "$ZSHRC" ]] && grep -qE 'oh-my-zsh|p10k|powerlevel10k|POWERLEVEL9K|ZSH_THEME' "$ZSHRC"; then
        FOUND_ZSHRC=1
    fi

    if [[ "$OS" == "Darwin" ]] && command -v brew &>/dev/null; then
        brew list --formula powerlevel10k &>/dev/null && FOUND_BREW+=("powerlevel10k")
        brew list --cask font-meslo-for-powerlevel10k &>/dev/null \
            && FOUND_BREW+=("--cask font-meslo-for-powerlevel10k")
    fi

    [[ "${#FOUND_PATHS[@]}" -gt 0 || -n "$FOUND_ZSHRC" || "${#FOUND_BREW[@]}" -gt 0 ]]
}

print_plan() {
    log_info "The following will be removed:"
    local p
    for p in "${FOUND_PATHS[@]}"; do
        style_text "    rm -rf  $p"
    done
    for p in "${FOUND_BREW[@]}"; do
        style_text "    brew uninstall $p"
    done
    if [[ -n "$FOUND_ZSHRC" ]]; then
        style_text "    edit    $ZSHRC  (these lines):"
        grep -nE 'oh-my-zsh|p10k|powerlevel10k|POWERLEVEL9K|ZSH_THEME|^plugins=' "$ZSHRC" \
            | sed 's/^/        /'
    fi
    echo
    log_info "A timestamped backup of $ZSHRC is taken before any edit."
}

# 0 = proceed, 1 = user kept the install, 130 = user quit.
confirm_removal() {
    [[ -n "$ASSUME_YES" ]] && return 0
    local answer=""
    while true; do
        read -r -p "Remove Oh My Zsh and Powerlevel10k? [y = remove / n = keep / q = quit]: " answer
        case "$answer" in
            [Yy]) return 0 ;;
            [Nn])
                log_info "Uninstall cancelled. Nothing was changed."
                return 1
                ;;
            [Qq])
                log_warn "Quitting at user request."
                return 130
                ;;
            *) style_text "⚠️   Invalid input: '$answer' (expected y, n, or q)." bold yellow ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# .zshrc surgery
# ---------------------------------------------------------------------------
backup_zshrc() {
    local backup
    backup="$ZSHRC.pre-starship.$(date +%Y%m%d-%H%M%S).bak"
    cp "$ZSHRC" "$backup"
    printf '%s\n' "$backup"
}

# Overwrite dst with the contents of src, keeping dst's mode, owner and inode.
# `mv tmp dst` would be simpler but carries the temp file's permissions across —
# mktemp creates 0600, so that silently tightens a normal 0644 .zshrc.
replace_file_contents() {
    local src="$1" dst="$2"
    cat "$src" > "$dst"
    rm -f "$src"
}

# Remove every Oh My Zsh / Powerlevel10k line from the given file.
#
# Comments are handled as *runs*, not as individual lines. The Oh My Zsh .zshrc
# template is mostly multi-line commentary, and deleting only the lines that
# happen to say "oh-my-zsh" leaves behind half-sentences like
#   "# Set name of the theme to load --- if set to "random", it will"
# So: any unbroken run of comment lines that mentions Oh My Zsh or Powerlevel10k
# anywhere within it is dropped whole. A short list of verbatim template lines
# that carry no such marker ("# User configuration") is matched exactly.
#
# Two multi-line code constructs need state machines: the p10k instant-prompt
# `if` block and the `plugins=( ... )` array.
strip_zshrc() {
    local file="$1" tmp tmp2
    tmp="$(mktemp)"
    tmp2="$(mktemp)"

    awk '
        function flush_run(   i) {
            if (run_n && !run_drop) { for (i = 1; i <= run_n; i++) print run[i] }
            run_n = 0
            run_drop = 0
        }

        BEGIN {
            # Any of these inside a comment run condemns the whole run.
            markers = "oh-my-zsh|ohmyzsh|Oh My Zsh|p10k|Powerlevel10k|POWERLEVEL9K" \
                      "|ZSH_THEME|ZSH_CUSTOM|[$]ZSH/|plugins=\\(|CASE_SENSITIVE" \
                      "|HYPHEN_INSENSITIVE|DISABLE_MAGIC_FUNCTIONS|DISABLE_LS_COLORS" \
                      "|DISABLE_AUTO_TITLE|ENABLE_CORRECTION|COMPLETION_WAITING_DOTS" \
                      "|DISABLE_UNTRACKED_FILES_DIRTY|HIST_STAMPS|DISABLE_AUTO_UPDATE" \
                      "|ZSH_COMPDUMP|RANDOM_THEME|:omz:|auto-update"
            # Verbatim Oh My Zsh template comment lines with no marker of their own.
            phrases = "^[[:space:]]*#[[:space:]]*(If you come from bash you might have to change your [$]PATH" \
                      "|export PATH=[$]HOME/bin:|User configuration$|export MANPATH=" \
                      "|You may need to manually set your language environment|export LANG=" \
                      "|Compilation flags$|export ARCHFLAGS=|Example aliases$|alias zshconfig=" \
                      "|Add wisely, as too many plugins slow down shell startup)"
        }

        # --- p10k instant prompt if/fi block ----------------------------------
        /^[[:space:]]*if[[:space:]]*\[\[[[:space:]]*-r[[:space:]].*p10k-instant-prompt/ {
            flush_run(); in_ip = 1; next
        }
        in_ip { if ($0 ~ /^[[:space:]]*fi[[:space:]]*$/) { in_ip = 0 } next }

        # --- plugins=( ... ), single- or multi-line ---------------------------
        /^[[:space:]]*plugins=\(/ { flush_run(); if ($0 !~ /\)/) { in_plugins = 1 } next }
        in_plugins { if ($0 ~ /\)/) { in_plugins = 0 } next }

        # --- comment runs -----------------------------------------------------
        /^[[:space:]]*#/ {
            run[++run_n] = $0
            if ($0 ~ markers || $0 ~ phrases) { run_drop = 1 }
            next
        }
        { flush_run() }

        # --- single-line code removals ----------------------------------------
        /powerlevel10k\.zsh-theme/                            { next }
        /^[[:space:]]*(export[[:space:]]+)?ZSH=.*oh-my-zsh/   { next }
        /^[[:space:]]*ZSH_THEME(_RANDOM_CANDIDATES)?=/        { next }
        /^[[:space:]]*source[[:space:]]+\$ZSH\/oh-my-zsh\.sh/ { next }
        /source[[:space:]]+.*\.p10k\.zsh/                     { next }
        /^[[:space:]]*zstyle[[:space:]]+.:omz:/               { next }
        /^[[:space:]]*fpath\+=.*oh-my-zsh/                    { next }
        /^[[:space:]]*(export[[:space:]]+)?ZSH_CUSTOM=/       { next }
        /^[[:space:]]*(typeset[[:space:]]+-g[[:space:]]+)?POWERLEVEL9K_/ { next }

        { print }
        END { flush_run() }
    ' "$file" > "$tmp"

    # Removal leaves 5-10 line gaps where the Oh My Zsh comment blocks were.
    # Collapse every run of blank lines to one, and drop leading blanks.
    awk '
        /^[[:space:]]*$/ { blanks++; next }
        { if (started && blanks) print ""; started = 1; blanks = 0; print }
    ' "$tmp" > "$tmp2"

    replace_file_contents "$tmp2" "$file"
    rm -f "$tmp"
}

verify_zshrc() {
    local file="$1"
    command -v zsh &>/dev/null || { log_warn "zsh not found; skipping syntax check."; return 0; }
    zsh -n "$file" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Removal
# ---------------------------------------------------------------------------
remove_paths() {
    log_step "Removing Oh My Zsh and Powerlevel10k files..."
    local p
    for p in "${FOUND_PATHS[@]}"; do
        rm -rf "$p"
        style_text "    removed  $p"
    done
}

remove_brew_packages() {
    [[ "$OS" == "Darwin" ]] || return 0
    [[ "${#FOUND_BREW[@]}" -gt 0 ]] || return 0
    command -v brew &>/dev/null || return 0

    log_step "Removing Homebrew packages..."
    if brew list --formula powerlevel10k &>/dev/null; then
        brew uninstall powerlevel10k || log_warn "brew uninstall powerlevel10k failed; continuing."
    fi
    # font-meslo-lg-nerd-font and font-symbols-only-nerd-font are deliberately
    # left alone — Starship uses them.
    if brew list --cask font-meslo-for-powerlevel10k &>/dev/null; then
        brew uninstall --cask font-meslo-for-powerlevel10k \
            || log_warn "brew uninstall of the p10k Meslo cask failed; continuing."
    fi
}

# ---------------------------------------------------------------------------
# Entry point (also the sourceable API)
# ---------------------------------------------------------------------------
uninstall_omz_p10k() {
    if ! omz_p10k_present; then
        log_ok "Oh My Zsh and Powerlevel10k are not installed. Nothing to remove."
        return 0
    fi

    print_plan

    if [[ -n "$DRY_RUN" ]]; then
        log_info "Dry run — no changes made."
        return 0
    fi

    local rc=0
    confirm_removal || rc=$?
    # 'n' means keep the install: that is a successful no-op, not a failure.
    [[ "$rc" -eq 1 ]] && return 0
    [[ "$rc" -eq 0 ]] || return "$rc"

    # .zshrc goes first: it is the only step that can fail recoverably, and
    # nothing has been deleted yet if it does.
    local backup=""
    if [[ -n "$FOUND_ZSHRC" ]]; then
        log_step "Editing $ZSHRC..."
        backup="$(backup_zshrc)"
        style_text "    backup   $backup"
        strip_zshrc "$ZSHRC"
        if ! verify_zshrc "$ZSHRC"; then
            log_err "The edited $ZSHRC failed 'zsh -n'. Restoring the backup; nothing else was removed."
            cp "$backup" "$ZSHRC"
            return 1
        fi
        log_ok "$ZSHRC cleaned."
    fi

    remove_paths
    remove_brew_packages

    log_ok "Oh My Zsh and Powerlevel10k have been removed."
    [[ -n "$backup" ]] && style_text "    your previous .zshrc: $backup"
    format_font "Gone with Oh My Zsh: its git aliases (gst, gco, ...), its fzf keybindings
(ctrl-R / ctrl-T), and the zsh-autosuggestions, zsh-syntax-highlighting and
zsh-completions plugins it hosted. install_zsh_starship.sh restores
equivalents for all of them." normal blue
    return 0
}

# When executed directly (not sourced), parse flags and run.
# The `|| rc=$?` is load-bearing: a bare call would let the ERR trap fire on the
# expected non-zero returns (130 when the user quits) and print a spurious error.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_for_root
    parse_args "$@"
    UNINSTALL_RC=0
    uninstall_omz_p10k || UNINSTALL_RC=$?
    exit "$UNINSTALL_RC"
fi
