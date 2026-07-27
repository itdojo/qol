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
# True when HAVE is the same version as WANT or newer.
#
# Compares field by field rather than sorting. An earlier version piped both
# through `sort -t. -k1,1n -k2,2n -k3,3n` and took the first line, but a missing
# field and an explicit 0 tie under those keys, so `4.0` vs `4.0.0` fell through
# to a lexical whole-line tiebreak and reported the shorter string as older.
#
# The `-ne`/`-gt` numeric tests below need pure-digit fields to avoid erroring
# out or misparsing as arithmetic. That is enforced here, by this function's
# own normalisation below, not by the caller — version_at_least is called with
# the literal MIN_NANO_VERSION too, not only with nano_version output.
version_at_least() {
    local have="$1" want="$2"
    local h1 h2 h3 w1 w2 w3 rest

    # The fourth variable absorbs any remaining fields. Without it, `read`
    # slurps the whole remainder into h3 — "9.1.2.3" would give h3="2.3", which
    # is still digits-and-dots (so nano_version's guard passes it) but blows up
    # the arithmetic test below with an invalid-operator error.
    IFS=. read -r h1 h2 h3 rest <<< "$have"
    IFS=. read -r w1 w2 w3 rest <<< "$want"

    # Truncate each field at its first non-digit, so a suffix like "1-rc1"
    # becomes 1 rather than being handed to bash arithmetic, which would parse
    # it as a subtraction against an unset variable and silently return 1.
    h1="${h1%%[!0-9]*}"; h2="${h2%%[!0-9]*}"; h3="${h3%%[!0-9]*}"
    w1="${w1%%[!0-9]*}"; w2="${w2%%[!0-9]*}"; w3="${w3%%[!0-9]*}"

    : "${h1:=0}" "${h2:=0}" "${h3:=0}"
    : "${w1:=0}" "${w2:=0}" "${w3:=0}"

    if   [[ "$h1" -ne "$w1" ]]; then [[ "$h1" -gt "$w1" ]]
    elif [[ "$h2" -ne "$w2" ]]; then [[ "$h2" -gt "$w2" ]]
    else [[ "$h3" -ge "$w3" ]]
    fi
}

# Print the bare version of a GNU nano binary, or fail.
#
# TERM=dumb and </dev/null are load-bearing, not defensive. macOS's
# /usr/bin/nano is UW PICO, which does not understand --version and will open
# a full-screen editor. Under TERM=dumb with stdin closed it bails out with
# "Incomplete terminfo entry" instead. GNU nano prints its version and exits
# before it ever calls initscr(), so it is unaffected.
nano_version() {
    local bin="$1" line version
    [[ -x "$bin" ]] || return 1
    line="$(TERM=dumb "$bin" --version </dev/null 2>&1 | head -1)" || return 1
    case "$line" in
        *"GNU nano"*) ;;
        *) return 1 ;;
    esac
    version="$(printf '%s\n' "$line" \
        | sed -E 's/.*GNU nano,? version ([0-9][0-9.]*).*/\1/')"
    # If the version group didn't match, sed echoes the line unchanged. Reject
    # anything that isn't purely digits and dots so version_at_least's numeric
    # comparisons never see a partial or garbage version string.
    [[ "$version" =~ ^[0-9][0-9.]*$ ]] || return 1
    printf '%s\n' "$version"
}

# `nano --help` lists the long-option form of every rc directive that this
# particular binary was compiled with. Several are wrapped in #ifdef in
# src/nano.c, so a distro build configured with --enable-tiny omits them
# regardless of its version number. Probing --help is therefore exact where a
# version table would be wrong.
nano_help_cache=""

load_nano_help() {
    local bin="$1"
    nano_help_cache=""
    [[ -x "$bin" ]] || return 1

    # Only output from a successful --help run is trustworthy. An earlier
    # version merged stderr in and ignored the exit status, so a failed probe
    # left a shell error message in the cache — and an error that echoes the
    # binary's path back could then satisfy nano_supports.
    nano_help_cache="$(TERM=dumb "$bin" --help </dev/null 2>/dev/null)" || {
        nano_help_cache=""
        return 1
    }
}

# Match on the whole option token so that `line` cannot match `--linenumbers`.
# The option is always followed by a comma, an equals sign, or whitespace.
# LONGOPT is spliced into an ERE unescaped: callers must pass a hardcoded
# literal option name, never user input or anything containing regex
# metacharacters.
nano_supports() {
    printf '%s\n' "$nano_help_cache" | grep -qE -- "--$1([,= ]|\$)"
}

# ---------------------------------------------------------------------------
# Syntax highlighting
# ---------------------------------------------------------------------------
# Emit include globs in nano's parse order. Order is load-bearing:
# begin_new_syntax() in src/rcfile.c prepends each syntax to a list, and
# find_and_prime_applicable_syntax() in src/color.c walks that list from the
# head and stops at the first extension match. The last file included therefore
# wins. The definitions shipped with the nano binary are versioned alongside it
# and are the better ones where both packs define a language, so they go last;
# the community pack fills in the ~140 languages nano does not ship.
#
# Only directories that exist are emitted. nano prints a warning for an include
# glob that matches nothing, and a warning on every launch is exactly the kind
# of thing that makes a student distrust their editor.
syntax_include_globs() {
    local prefixes dir

    # QOL_NANO_PREFIXES is a test seam: it lets tests point this function at a
    # fixture tree instead of real system paths. Unset in normal operation.
    if [[ -n "${QOL_NANO_PREFIXES:-}" ]]; then
        prefixes="$QOL_NANO_PREFIXES"
    else
        prefixes="/usr/share/nano
/usr/local/share/nano
/opt/homebrew/share/nano
/usr/share/nano-syntax-highlighting"
    fi

    # Community pack first — lowest precedence.
    if [[ -d "$SYNTAX_DIR" ]]; then
        printf '%s/*.nanorc\n' "$SYNTAX_DIR"
    fi

    # Shipped packs last — they win ties.
    #
    # Split on newlines only. An unscoped split would also break on spaces,
    # silently discarding any prefix whose path contains one — the directory
    # would simply never appear in the output, and the user would see missing
    # highlighting with nothing explaining it.
    local old_ifs="$IFS"
    IFS=$'\n'
    # shellcheck disable=SC2086  # deliberate word-splitting, scoped to newlines by IFS above
    for dir in $prefixes; do
        [[ -d "$dir" ]] || continue
        printf '%s/*.nanorc\n' "$dir"
        if [[ -d "$dir/extra" ]]; then
            printf '%s/extra/*.nanorc\n' "$dir"
        fi
    done
    IFS="$old_ifs"
}

# ---------------------------------------------------------------------------
# nanorc rendering
# ---------------------------------------------------------------------------
# Emit one gated directive. When the running nano supports it, write it live;
# when it does not, write it as a comment naming the version that would enable
# it, so someone who later upgrades can see what they gained.
#
#   gated_directive <long-option> <rc-line> <version-that-added-it>
gated_directive() {
    local opt="$1" line="$2" since="$3"
    if nano_supports "$opt"; then
        printf '%s\n' "$line"
    else
        printf '# %s   # unavailable — needs nano %s (or a non-tiny build)\n' \
            "$line" "$since"
    fi
}

render_nanorc() {
    local glob

    # Leading newline: this block gets appended directly after the last
    # non-blank line of the user's existing ~/.nanorc, so it must supply its
    # own separating blank line.
    printf '\n%s\n' "$BLOCK_START"
    cat <<'BODY'
# Managed by install_nano.sh — this whole block is rewritten on every rerun.
# Put your own settings OUTSIDE the markers; anything inside is disposable.
# Full directive reference: `man nanorc`

# --- editing ---------------------------------------------------------------
set autoindent          # keep the current indent on Enter
set tabsize 4           # a tab is four columns wide
set tabstospaces        # ...and typing Tab inserts spaces, not a tab character
set trimblanks          # strip trailing whitespace from wrapped lines
set smarthome           # Home goes to the first non-blank first, then column 1
set matchbrackets "(<[{)>]}"   # M-] jumps to the matching bracket

# --- display ---------------------------------------------------------------
set linenumbers         # line numbers down the left margin
set softwrap            # wrap long lines on screen without inserting newlines
set atblanks            # ...and wrap at spaces rather than mid-word
set constantshow        # always show the cursor position on the status bar
set guidestripe 80      # faint vertical rule at column 80
BODY

    gated_directive indicator "set indicator" "5.0"
    gated_directive stateflags "set stateflags" "5.3"

    cat <<'BODY'

# --- state -----------------------------------------------------------------
set positionlog         # reopen a file where you left off
set historylog          # remember search and replace history between sessions
set multibuffer         # ^R reads a file into a new buffer instead of inline

# --- keys ------------------------------------------------------------------
# ^S to save, because everyone's fingers already do this. nano's own ^O
# ("WriteOut") stays bound as well.
#
# ^Q is deliberately NOT bound to exit: it is XOFF on many terminals, and a
# student who hits it on a serial console gets what looks like a frozen
# machine. ^X remains the way out, and it is on the help bar at all times.
bind ^S savefile main
BODY

    printf '\n# --- syntax highlighting ---------------------------------------------------\n'
    printf '# Later includes win: nano matches the most recently parsed syntax first,\n'
    printf '# so the definitions shipped with nano override the community pack.\n'
    while IFS= read -r glob; do
        [[ -n "$glob" ]] && printf 'include "%s"\n' "$glob"
    done <<EOF
$(syntax_include_globs)
EOF

    printf '%s\n' "$BLOCK_END"
}

# ---------------------------------------------------------------------------
# Writing ~/.nanorc
# ---------------------------------------------------------------------------
backup_file() {
    local f="$1" backup
    [[ -f "$f" ]] || return 0
    backup="$f.pre-nano.$(date +%Y%m%d-%H%M%S).bak"
    cp "$f" "$backup"
    log_info "Backed up $f → $backup"
}

# Overwrite dst with the contents of src, atomically.
#
# An earlier version was `cat "$src" > "$dst"`, which truncates dst at
# redirection time — a disk-full or killed process left the user's ~/.nanorc
# half-written with no way back. Renaming a fully-written temp file over the
# target closes that window: the rename either happens or it doesn't.
#
# Two details are load-bearing. The temp file is created in the DESTINATION's
# directory, not $TMPDIR, because a rename is only atomic within a single
# filesystem, and $TMPDIR is not guaranteed to share one with $HOME — a tmpfs
# /tmp on Linux, or a user-set TMPDIR, would silently turn the rename into a
# copy instead. And symlinks are resolved first, because renaming onto a
# symlink replaces the link with a regular file — which would quietly detach
# a ~/.nanorc that a user has symlinked into a dotfiles repo. That second
# reason holds regardless of filesystem layout and is why the destination
# directory is the right place for the temp file either way.
#
# What survives is the path, the mode, and the symlink if there is one — not
# the inode: the atomic rename necessarily replaces it.
replace_file_contents() {
    local src="$1" dst="$2" target tmp mode link guard=0

    target="$dst"
    while [[ -L "$target" ]] && [[ "$guard" -lt 20 ]]; do
        link="$(readlink "$target")"
        case "$link" in
            /*) target="$link" ;;
            *)  target="$(dirname "$target")/$link" ;;
        esac
        guard=$((guard + 1))
    done

    # BSD and GNU stat disagree on flags; try both before giving up.
    mode="$(stat -f '%Lp' "$target" 2>/dev/null \
        || stat -c '%a' "$target" 2>/dev/null \
        || echo 644)"

    tmp="$(mktemp "${target}.XXXXXX")" || {
        log_err "Could not create a temporary file next to $target"
        return 1
    }

    cat "$src" > "$tmp" || { rm -f "$tmp"; return 1; }
    chmod "$mode" "$tmp"
    mv "$tmp" "$target"
    rm -f "$src"
}

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

write_nanorc() {
    log_step "Writing $NANORC..."
    [[ -f "$NANORC" ]] || touch "$NANORC"

    # Only back up a file we have not managed before. Backing up on every rerun
    # would litter the home directory with near-identical copies.
    if ! grep -qF "$BLOCK_START" "$NANORC" && [[ -s "$NANORC" ]]; then
        backup_file "$NANORC"
    fi

    remove_managed_block "$NANORC"

    # Strip trailing blank lines left behind by block removal. Without this,
    # every rerun would add one more blank line above the block and the
    # "byte-identical rerun" guarantee would fail on the second run.
    # Only *trailing* blanks go — blank lines inside the user's own config are
    # their spacing and must survive.
    #
    # Records every line in an array and remembers the index of the last
    # non-blank one, then prints up to that index. A simpler `NF { print }`
    # would drop every blank line in the file, including the user's own
    # interior spacing — not just the trailing run left by block removal.
    local tmp; tmp="$(mktemp)"
    awk '{ lines[NR] = $0 }
         END {
             last = 0
             for (i = 1; i <= NR; i++) if (lines[i] ~ /[^[:space:]]/) last = i
             for (i = 1; i <= last; i++) print lines[i]
         }' "$NANORC" > "$tmp"
    replace_file_contents "$tmp" "$NANORC"

    render_nanorc >> "$NANORC"
    log_ok "Wrote the qol block to $NANORC"
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
