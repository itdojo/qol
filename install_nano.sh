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

NANORC=""
SYNTAX_DIR=""
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

# Resolve paths at run time, not at source time. Tests run the script under a
# synthetic $HOME, and anything captured when the file was sourced would still
# point at the real home directory.
init_paths() {
    [[ -n "$NANORC" ]]     || NANORC="$HOME/.nanorc"
    [[ -n "$SYNTAX_DIR" ]] || SYNTAX_DIR="$HOME/.nano"
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
    # Iterate with `read` rather than `for dir in $prefixes`. Word-splitting an
    # unquoted expansion is a bash behaviour; zsh leaves it unsplit, so the
    # whole newline-separated list arrived as a single path and the function
    # silently emitted nothing when sourced into a zsh shell. A read loop
    # behaves identically under both.
    while IFS= read -r dir; do
        [[ -n "$dir" ]] || continue
        [[ -d "$dir" ]] || continue
        printf '%s/*.nanorc\n' "$dir"
        if [[ -d "$dir/extra" ]]; then
            printf '%s/extra/*.nanorc\n' "$dir"
        fi
    done <<EOF
$prefixes
EOF
}

# nano ships 39 syntax definitions (44 counting syntax/extra). The community
# pack at scopatz/nanorc carries roughly 180, covering yaml variants, toml,
# dockerfile, terraform, nginx, systemd units and the rest of what a student in
# a networking course actually opens.
sync_syntax_pack() {
    if [[ -n "$NO_SYNTAX" ]]; then
        log_info "Skipping the community syntax pack (--no-syntax)."
        return 0
    fi

    if [[ -n "$DRY_RUN" ]]; then
        log_info "[dry-run] would sync $SYNTAX_REPO → $SYNTAX_DIR"
        return 0
    fi

    if ! command -v git >/dev/null 2>&1; then
        log_warn "git is not installed; skipping the community syntax pack.
The definitions shipped with nano will still be used."
        return 0
    fi

    log_step "Syncing extra syntax definitions..."

    if [[ ! -d "$SYNTAX_DIR/.git" ]]; then
        if [[ -d "$SYNTAX_DIR" ]]; then
            log_warn "$SYNTAX_DIR exists but is not a git clone; leaving it alone."
            return 0
        fi
        if ! git clone --depth 1 --quiet "$SYNTAX_REPO" "$SYNTAX_DIR"; then
            log_warn "Could not clone the syntax pack. The definitions shipped
with nano will still be used."
            return 0
        fi
        log_ok "Cloned the community syntax pack to $SYNTAX_DIR"
        return 0
    fi

    # Never discard someone's local edits to a syntax file.
    if [[ -n "$(git -C "$SYNTAX_DIR" status --porcelain)" ]]; then
        log_warn "$SYNTAX_DIR has local changes; not pulling."
        return 0
    fi

    if ! git -C "$SYNTAX_DIR" pull --ff-only --quiet; then
        log_warn "Could not update the syntax pack; using what is already there."
    else
        log_ok "Syntax pack is up to date."
    fi
    return 0
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
# Put your own settings ABOVE this block, not below it: the block is always
# re-appended at the end of the file, so anything you add below it today
# ends up above it after the next run. Anything inside the markers is
# disposable.
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

# Stock nano leaves ^Z doing nothing at all — not undo, not suspend, just a
# dead key (confirmed with `ps`: the process stays in state S, never T). The
# man page's own EXAMPLES section gives this exact binding. Every other
# program on the system suspends on ^Z; a key that silently does nothing in
# one program teaches the wrong lesson in a course that covers job control.
# `fg` returns to nano afterward.
bind ^Z suspend main
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
# LAST_BACKUP_PATH is a result-out-of-band global, same convention as
# nano_help_cache: it lets a caller that goes on to fail on a *later* step
# clean up the backup this function just took, rather than leaving a stray
# .bak behind from a write that never actually completed.
LAST_BACKUP_PATH=""

backup_file() {
    local f="$1"
    LAST_BACKUP_PATH=""
    [[ -f "$f" ]] || return 0
    local backup
    backup="$f.pre-nano.$(date +%Y%m%d-%H%M%S).bak"
    # `cp` was previously a bare statement followed unconditionally by
    # log_info — log_info always succeeds, so it masked a failed copy behind
    # a "Backed up" message that never happened. Check it explicitly. Its
    # own stderr is suppressed: a failure here already gets a clearer ❌
    # line below, and the raw `cp: ...` text would just stack above it.
    if ! cp "$f" "$backup" 2>/dev/null; then
        log_err "Could not back up $f to $backup."
        return 1
    fi
    log_info "Backed up $f → $backup"
    LAST_BACKUP_PATH="$backup"
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
    #
    # Three SEPARATE assignments, not one command substitution chained with
    # `||`. Chained inside a single `$( )`, all three commands share one
    # stdout, so their output concatenates — and GNU stat's `-f` means
    # `--file-system`, so on Linux it read "%Lp" as a filename, printed a
    # multi-line filesystem dump to stdout, and failed. `mode` became that
    # dump with `644` appended, `chmod` rejected it, and every write path in
    # this script died. Reproduced on Debian: exit 1 with an empty ~/.nanorc.
    # GNU form goes first because Linux is where the failure was fatal.
    mode="$(stat -c '%a' "$target" 2>/dev/null)" \
        || mode="$(stat -f '%Lp' "$target" 2>/dev/null)" \
        || mode=644

    tmp="$(mktemp "${target}.XXXXXX" 2>/dev/null)" || {
        log_err "Could not create a temporary file next to $target"
        return 1
    }

    # Every command below has its own stderr suppressed: each failure path
    # already prints a clearer ❌ line of its own, and the raw tool message
    # (cat's, chmod's, mv's) would just stack a second, less useful message
    # directly above it.
    cat "$src" > "$tmp" 2>/dev/null || {
        rm -f "$tmp"
        log_err "Could not write a replacement for $target."
        return 1
    }
    chmod "$mode" "$tmp" 2>/dev/null || {
        rm -f "$tmp"
        log_err "Could not set permissions on the replacement for $target."
        return 1
    }
    # -f, not a bare `mv`: GNU mv prompts for confirmation before overwriting
    # a file whose own permission bits are read-only, even when the caller
    # owns it and the containing directory is writable (rename() only cares
    # about the latter). Unanswerable in a non-interactive script, that
    # prompt reads stdin, gets EOF, and mv exits non-zero — which previously
    # surfaced as a bare, unexplained "mv: ..." message right before the
    # whole script died under set -e. -f skips the prompt; a genuine
    # permission problem (unwritable directory) still fails, and now it is
    # caught here with a clear message instead.
    if ! mv -f "$tmp" "$target" 2>/dev/null; then
        rm -f "$tmp"
        log_err "Could not replace $target (permission denied?)."
        return 1
    fi
    rm -f "$src"
}

remove_managed_block() {
    local file="$1" tmp
    grep -qF "$BLOCK_START" "$file" || return 0
    tmp="$(mktemp 2>/dev/null)" || {
        log_err "Could not create a temporary file to update $file."
        return 1
    }
    # The exit status is checked, not assumed. `set -e` cannot help here:
    # every caller of this function sits in a `||` context, which disarms it
    # for the whole call tree below. An unchecked awk that died partway
    # through (a broken awk on PATH, a full disk, SIGPIPE) would hand a
    # truncated temp file straight to replace_file_contents, which would then
    # atomically install that truncation over the user's real config — while
    # the script went on to print "nano is ready" and exit 0.
    awk -v s="$BLOCK_START" -v e="$BLOCK_END" '
        index($0, s) { skip = 1 }
        !skip { print }
        index($0, e) { skip = 0 }
    ' "$file" > "$tmp" || {
        rm -f "$tmp"
        log_err "Could not rewrite $file while removing its previous managed block."
        return 1
    }
    replace_file_contents "$tmp" "$file"
}

# Replace the managed block at the end of FILE with fresh output from
# RENDERER, atomically and idempotently.
#
# Both ~/.nanorc and the shell rc files touched by --set-editor get exactly
# this treatment. They used not to: write_nanorc did it properly while
# set_default_editor appended with a bare `cat >> "$rc"` that started directly
# at its own start marker. On an rc file whose last line had no trailing
# newline, run 1 produced
#
#     export IMPORTANT_SETTING=1# >>> qol nano editor >>>
#
# which `bash -n` rejects as a syntax error, so every new terminal errored and
# stopped sourcing the file — and run 2 then matched that combined line as the
# block start and deleted the user's setting along with the block, taking no
# backup because the file already contained the marker. One helper used by
# both callers is the only way that stays fixed.
#
# Three details are load-bearing:
#   1. The previous block is excised first, so reruns cannot duplicate it.
#   2. Trailing blank lines are trimmed, so reruns are byte-identical instead
#      of growing one blank line each time. Only *trailing* blanks go — blank
#      lines inside the user's own config are their spacing and must survive,
#      which is why this records every line and prints up to the last
#      non-blank one rather than using a simpler `NF { print }`.
#   3. That trim rewrites the file through awk's `print`, which terminates
#      every line it emits — so the file is guaranteed to end in a newline
#      before the renderer appends, whatever shape it arrived in. The renderer
#      supplies its own leading blank line for separation.
#
# The caller keeps ownership of backups; this returns non-zero with a ❌ line
# already printed on every failure path.
#
#   replace_managed_block <file> <start-marker> <end-marker> <renderer-fn>
replace_managed_block() {
    local file="$1" start="$2" end="$3" renderer="$4"

    # remove_managed_block reads its markers from globals. Swap them around
    # the call and restore them unconditionally — a bare call that failed
    # would trip `set -e` and skip straight past the restore, leaving the
    # globals pointed at this block's markers for whatever ran next.
    local saved_start="$BLOCK_START" saved_end="$BLOCK_END"
    BLOCK_START="$start"
    BLOCK_END="$end"
    local remove_rc=0
    remove_managed_block "$file" || remove_rc=$?
    BLOCK_START="$saved_start"
    BLOCK_END="$saved_end"
    if [[ "$remove_rc" -ne 0 ]]; then
        log_err "Could not update $file while removing its previous managed block."
        return 1
    fi

    local tmp
    tmp="$(mktemp 2>/dev/null)" || {
        log_err "Could not create a temporary file to rewrite $file."
        return 1
    }
    # Checked for the same reason as the awk in remove_managed_block above:
    # a failing awk here previously replaced ~/.nanorc with partial output
    # while the script reported success.
    awk '{ lines[NR] = $0 }
         END {
             last = 0
             for (i = 1; i <= NR; i++) if (lines[i] ~ /[^[:space:]]/) last = i
             for (i = 1; i <= last; i++) print lines[i]
         }' "$file" > "$tmp" || {
        rm -f "$tmp"
        log_err "Could not rewrite $file while trimming its trailing blank lines."
        return 1
    }
    replace_file_contents "$tmp" "$file" || {
        log_err "Could not update $file while trimming trailing blank lines."
        return 1
    }

    # Grouped so the outer 2>/dev/null also catches the redirection-open
    # failure itself (e.g. a genuinely read-only $file), not just the
    # renderer's own stderr. A trailing `2>/dev/null` on this line alone
    # would not: `>>` is set up before that redirection takes effect, so an
    # open failure would still print to the original stderr first — confirmed
    # empirically before relying on it.
    if ! { "$renderer" >> "$file"; } 2>/dev/null; then
        log_err "Could not append the managed block to $file (permission denied?)."
        return 1
    fi
}

write_nanorc() {
    log_step "Writing $NANORC..."

    # Every step below that touches the filesystem is checked explicitly and
    # returns 1 with a ❌ line of its own on failure, rather than leaving a
    # bare command to fail and let `set -e` kill the whole script mid-write
    # with nothing but a raw tool error (e.g. `touch: No such file or
    # directory` for a dangling symlink, or a stray .bak with no explanation
    # of what happened next). main() wraps this call in `|| exit 1`, exactly
    # like install_nano_package and resolve_nano.
    if [[ ! -f "$NANORC" ]]; then
        if ! touch "$NANORC" 2>/dev/null; then
            log_err "Could not create $NANORC (dangling symlink to a missing directory?)."
            return 1
        fi
    fi

    # Only back up a file we have not managed before. Backing up on every
    # rerun would litter the home directory with near-identical copies.
    # backup_path is remembered so it can be removed again if a later step
    # in this same function fails — otherwise a backup taken right before an
    # aborted write is a stray artifact of a write that never completed.
    local backup_path=""
    if ! grep -qF "$BLOCK_START" "$NANORC" && [[ -s "$NANORC" ]]; then
        backup_file "$NANORC" || return 1
        backup_path="$LAST_BACKUP_PATH"
    fi

    if ! replace_managed_block "$NANORC" "$BLOCK_START" "$BLOCK_END" render_nanorc; then
        [[ -n "$backup_path" ]] && rm -f "$backup_path"
        return 1
    fi
    log_ok "Wrote the qol block to $NANORC"
}

# ---------------------------------------------------------------------------
# Installing nano
# ---------------------------------------------------------------------------
detect_pkg_manager() {
    local mgr
    for mgr in brew apt-get dnf pacman apk zypper; do
        if command -v "$mgr" >/dev/null 2>&1; then
            printf '%s\n' "${mgr%-get}"
            return 0
        fi
    done
    return 1
}

# The literal package-manager command line (no sudo prefix) for MGR. Used
# both to actually install (see the case in install_nano_package) and, when
# sudo turns out to be unavailable, to tell the user the exact command to
# run themselves as root — the two must never drift apart.
pkg_install_cmd() {
    case "$1" in
        brew)   printf '%s\n' "brew install nano" ;;
        apt)    printf '%s\n' "env DEBIAN_FRONTEND=noninteractive apt-get install -y nano" ;;
        dnf)    printf '%s\n' "dnf install -y nano" ;;
        pacman) printf '%s\n' "pacman -S --noconfirm nano" ;;
        apk)    printf '%s\n' "apk add nano" ;;
        zypper) printf '%s\n' "zypper install -y nano" ;;
    esac
}

install_nano_package() {
    # QOL_NANO_NO_INSTALL is a test seam. main() must never let the suite
    # reach a real package manager — the stub nano in a fixture PATH usually
    # keeps resolve_nano from ever calling this, but a bug in that guard
    # would otherwise fall through to a genuine `apt-get install` or `brew
    # install` on whatever machine runs the tests. Set unconditionally in
    # every end-to-end test rather than relied on incidentally.
    if [[ -n "${QOL_NANO_NO_INSTALL:-}" ]]; then
        log_err "install_nano_package blocked by QOL_NANO_NO_INSTALL (test seam); refusing to touch a real package manager."
        return 1
    fi

    local mgr
    mgr="$(detect_pkg_manager)" || {
        log_err "No supported package manager found (brew, apt-get, dnf, pacman, apk, zypper)."
        return 1
    }

    log_step "Installing GNU nano via $mgr..."
    if [[ -n "$DRY_RUN" ]]; then
        log_info "[dry-run] would install nano with $mgr"
        return 0
    fi

    local sudo_cmd=""
    if [[ "$mgr" != "brew" && "$(id -u)" -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            sudo_cmd="sudo"
        else
            log_err "Installing nano via $mgr needs root, and sudo is not on PATH.
Run this yourself as root:
  $(pkg_install_cmd "$mgr")"
            return 1
        fi
    fi

    # $sudo_cmd is deliberately unquoted below: when empty it must vanish
    # entirely rather than expand to an empty-string argument, which some of
    # these package managers would choke on.
    # shellcheck disable=SC2086
    case "$mgr" in
        brew)   brew install nano ;;
        apt)    $sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y nano ;;
        dnf)    $sudo_cmd dnf install -y nano ;;
        pacman) $sudo_cmd pacman -S --noconfirm nano ;;
        apk)    $sudo_cmd apk add nano ;;
        zypper) $sudo_cmd zypper install -y nano ;;
    esac
}

# Look for a real GNU nano already installed via Homebrew, checked directly
# rather than via PATH (PATH is exactly the thing that's broken when this is
# called). Only used to make the pico diagnostic below concrete instead of a
# guess.
#
# QOL_NANO_BREW_PREFIXES is a test seam, same shape as syntax_include_globs's
# QOL_NANO_PREFIXES: it lets tests point this at a fixture tree instead of
# real system paths. Unset in normal operation.
find_homebrew_nano() {
    local prefixes prefix bin
    if [[ -n "${QOL_NANO_BREW_PREFIXES:-}" ]]; then
        prefixes="$QOL_NANO_BREW_PREFIXES"
    else
        prefixes="/opt/homebrew/bin
/usr/local/bin"
    fi

    # A `read` loop, not unquoted `for prefix in $prefixes` word-splitting on
    # IFS=$'\n': this script's own usage note (and Task 7's verification
    # step) has people `source` it from their interactive login shell, which
    # on current macOS defaults to zsh — and zsh does not word-split
    # unquoted expansions the way bash does, IFS or no IFS. A `read` loop
    # behaves the same in both.
    while IFS= read -r prefix; do
        [[ -n "$prefix" ]] || continue
        bin="$prefix/nano"
        if [[ -x "$bin" ]] && nano_version "$bin" >/dev/null 2>&1; then
            printf '%s\n' "$bin"
            return 0
        fi
    done <<EOF
$prefixes
EOF
    return 1
}

# The single most likely failure a macOS student hits: /usr/bin/nano is UW
# pico, not GNU nano. Split out of resolve_nano so the message logic —
# "is GNU nano already installed somewhere, and if so where" — is easy to
# follow and to test on its own.
pico_diagnostic() {
    local bin="$1" brew_nano rc_file

    if brew_nano="$(find_homebrew_nano)"; then
        case "$(basename "${SHELL:-/bin/bash}")" in
            zsh)  rc_file="$HOME/.zshrc" ;;
            bash) rc_file="$HOME/.bashrc" ;;
            *)    rc_file="your shell's rc file" ;;
        esac
        log_err "'$bin' is UW pico, not GNU nano. GNU nano is already installed at
$brew_nano — add this line to $rc_file, then open a new terminal:
  export PATH=\"$(dirname "$brew_nano"):\$PATH\""
    else
        log_err "'$bin' is UW pico, not GNU nano, and GNU nano is not installed yet.
Run this script normally (without overriding PATH) to install it."
    fi
}

# Find a usable GNU nano on PATH, or explain precisely why there isn't one.
#
# Exit status distinguishes two different situations a caller needs to react
# to differently:
#   1 — nothing answers to `nano` at all. Installing is the right next step.
#   2 — something answers to `nano`, but it is not usable (pico, some other
#       non-GNU nano, or a GNU nano too old for MIN_NANO_VERSION). A specific
#       diagnostic has already been printed, and running the installer would
#       not fix what it describes — on macOS in particular, `brew install
#       nano` does not change what `/usr/bin/nano` resolves to on PATH.
resolve_nano() {
    local bin version
    bin="$(command -v nano 2>/dev/null)" || {
        # Not found is an expected precondition on a fresh machine, not a
        # failure of anything — most students hit this branch on their very
        # first run. log_err's ❌ reads as "something went wrong" right
        # before a successful install; log_info here, and main() follows up
        # with its own "installing it now" once it decides to install rather
        # than this function presuming that's what happens next.
        #
        # >&2 is load-bearing, not stylistic: callers use resolve_nano's
        # stdout as its actual return value (`bin="$(resolve_nano)"`), the
        # same convention nano_version and pkg_install_cmd use. log_err
        # already redirects itself to stderr, which is why the pico/too-old
        # diagnostics below were never affected by this — but log_info does
        # not, so without >&2 here this message would silently vanish into
        # $bin instead of ever reaching the terminal. Caught by actually
        # running the script end to end, not just the unit tests, which
        # capture stderr and stdout together and could not have told the
        # difference.
        log_info "No GNU nano found on PATH." >&2
        return 1
    }

    if ! version="$(nano_version "$bin")"; then
        # Test seams: let the suite force this branch without a real
        # /usr/bin/nano and without pretending the test host is Darwin.
        local pico_path="${QOL_NANO_PICO_PATH:-/usr/bin/nano}"
        local os_name="${QOL_NANO_UNAME:-$(uname -s)}"

        if [[ "$os_name" == "Darwin" && "$bin" == "$pico_path" ]]; then
            pico_diagnostic "$bin"
        else
            log_err "'$bin' is not GNU nano."
        fi
        return 2
    fi

    if ! version_at_least "$version" "$MIN_NANO_VERSION"; then
        log_err "Found GNU nano $version, but this config needs $MIN_NANO_VERSION or newer.
Upgrade nano and run this script again."
        return 2
    fi

    printf '%s\n' "$bin"
}

# ---------------------------------------------------------------------------
# Optional: make nano the default editor
# ---------------------------------------------------------------------------
# Off unless asked for. Setting EDITOR touches a second file and changes what
# happens when `git commit` or `crontab -e` opens — a surprise nobody asked for
# when all they wanted was syntax highlighting.
EDITOR_BLOCK_START="# >>> qol nano editor >>>"
EDITOR_BLOCK_END="# <<< qol nano editor <<<"

# The editor block's counterpart to render_nanorc: emit the whole block,
# markers included, with its own leading blank line. Written as a renderer
# function rather than an inline `cat >>` precisely so replace_managed_block
# can own the framing — see that function's comment for what the inline
# version got wrong.
render_editor_block() {
    printf '\n%s\n' "$EDITOR_BLOCK_START"
    cat <<'BODY'
# Managed by install_nano.sh — rewritten on every rerun.
# Put your own settings ABOVE this block, not below it: the block is always
# re-appended at the end of the file, so anything you add below it today
# ends up above it after the next run.
export EDITOR=nano
export VISUAL=nano
BODY
    printf '%s\n' "$EDITOR_BLOCK_END"
}

set_default_editor() {
    # `rc` is declared here, with the others. It used to be declared halfway
    # down the function, below a `while IFS= read -r rc` in the dry-run
    # branch that ran first — so on a dry run it was assigned before it was
    # ever made local, which dynamically clobbered main()'s own `local rc`
    # (the variable holding resolve_nano's exit status).
    local shell_name rcs rc
    shell_name="$(basename "${SHELL:-/bin/bash}")"
    case "$shell_name" in
        zsh)
            rcs="$HOME/.zshrc"
            ;;
        bash)
            # Both, not just .bashrc: on macOS, Terminal.app (and any other
            # login shell) reads .bash_profile, not .bashrc, and a plain
            # .bashrc-only write left --set-editor with no effect there. A
            # non-login interactive shell (many Linux terminal emulators)
            # reads .bashrc instead. Writing the same idempotent block to
            # both covers whichever one actually gets sourced; if a user's
            # .bash_profile already sources .bashrc, the second export is
            # harmless.
            rcs="$HOME/.bash_profile
$HOME/.bashrc"
            ;;
        *)
            log_warn "Unrecognised shell ${SHELL:-unset}; not setting EDITOR.
Add these lines to your shell's startup file yourself:
  export EDITOR=nano
  export VISUAL=nano"
            return 0
            ;;
    esac

    if [[ -n "$DRY_RUN" ]]; then
        log_info "[dry-run] would export EDITOR=nano and VISUAL=nano in:"
        while IFS= read -r rc; do
            [[ -n "$rc" ]] && style_text "  $rc"
        done <<EOF
$rcs
EOF
        return 0
    fi

    while IFS= read -r rc; do
        [[ -n "$rc" ]] || continue

        if [[ ! -f "$rc" ]]; then
            if ! touch "$rc" 2>/dev/null; then
                log_err "Could not create $rc (dangling symlink to a missing directory?)."
                return 1
            fi
        fi

        # Only back up a file we have not managed before, same rule as
        # write_nanorc — this is the more valuable of the two files (it is
        # someone's whole shell startup, not just their editor config), so
        # it does not get skipped just because it's the second file this
        # script touches. backup_path is remembered so it can be removed
        # again if a later step for this same rc file fails, same reasoning
        # as write_nanorc.
        local backup_path=""
        if ! grep -qF "$EDITOR_BLOCK_START" "$rc" && [[ -s "$rc" ]]; then
            backup_file "$rc" || return 1
            backup_path="$LAST_BACKUP_PATH"
        fi

        # Exactly the same block treatment ~/.nanorc gets, through exactly
        # the same helper. This used to be a hand-rolled `cat >> "$rc"` that
        # skipped the trailing-blank trim and the leading newline, which is
        # how it came to corrupt an rc file with no final newline and then
        # delete a line from it on the next run.
        if ! replace_managed_block "$rc" \
                "$EDITOR_BLOCK_START" "$EDITOR_BLOCK_END" render_editor_block; then
            [[ -n "$backup_path" ]] && rm -f "$backup_path"
            return 1
        fi
        log_ok "Set nano as the default editor in $rc"
    done <<EOF
$rcs
EOF
}

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------
# Ask before a state-changing step. Three rules, in priority order:
#   1. --yes (ASSUME_YES) skips the prompt entirely and proceeds.
#   2. A non-tty stdin (piped, redirected, cron, this test suite) skips the
#      prompt too and proceeds — prompting into a black hole would just hang
#      forever, and that is the automation case this flag family exists for.
#   3. Otherwise a real prompt is shown; an empty reply (bare Enter) or
#      anything but an explicit yes defaults to declining, not proceeding.
#
# Callers never see --dry-run here: main() only calls confirm() from the
# branch that runs after the dry-run early exit, so a dry run never prompts.
#
# QOL_NANO_FORCE_TTY is a test seam: it lets the suite exercise the real
# prompt-and-read path by feeding input through a pipe, which is never a
# tty on its own, without needing an actual pty.
confirm() {
    local prompt="$1"
    [[ -n "$ASSUME_YES" ]] && return 0

    if [[ -z "${QOL_NANO_FORCE_TTY:-}" ]] && [[ ! -t 0 ]]; then
        return 0
    fi

    # A plain `read -p` was tried first and dropped: bash's own -p suppresses
    # the prompt entirely whenever it decides stdin isn't a real terminal —
    # which defeats QOL_NANO_FORCE_TTY, since that seam controls our own
    # branch above but not bash's internal read -p heuristic. Printing the
    # prompt ourselves means it appears exactly when this function decided
    # to ask, on a real tty or a forced one alike.
    local answer=""
    printf '%s [y/N]: ' "$prompt" >&2
    read -r answer
    case "$answer" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *)                 return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    init_paths

    log_step "nano setup"
    [[ -n "$DRY_RUN" ]] && log_info "Dry run — nothing will be written."

    # resolve_nano's exit status distinguishes "nothing found, install it"
    # (1) from "found something, but it's not usable and installing will not
    # help" (2 — pico, some other non-GNU nano, or too old). The pico case is
    # the single most likely failure a macOS student hits, and it used to be
    # buried: `resolve_nano 2>/dev/null` discarded pico_diagnostic's specific
    # message, and a bare `if ! bin=...; then install_nano_package` treated
    # both cases identically, so a pico-on-PATH student with no package
    # manager reachable saw "No supported package manager found" instead of
    # being told GNU nano is already installed at $brew_nano, or that it
    # needs to be installed with PATH left alone. Stderr is no longer
    # redirected, and the two cases are handled separately.
    local bin rc=0
    bin="$(resolve_nano)" || rc=$?
    if [[ "$rc" -eq 2 ]]; then
        exit 1
    fi
    if [[ "$rc" -ne 0 ]]; then
        log_info "Installing it now."
        install_nano_package || exit 1
        if [[ -n "$DRY_RUN" ]]; then
            log_info "[dry-run] stopping here; nano is not actually installed."
            exit 0
        fi
        bin="$(resolve_nano)" || exit 1
    fi

    log_ok "Using $bin ($(nano_version "$bin"))"

    # load_nano_help returns non-zero when the binary is missing, not
    # executable, or not GNU nano. resolve_nano just vetted $bin, so this is
    # not expected to fail — but main runs under set -e, and a bare call to a
    # function that can legitimately return non-zero would kill the script
    # with no message if it ever did. Handle it explicitly instead.
    if ! load_nano_help "$bin"; then
        log_err "Could not probe $bin for its supported nano options."
        exit 1
    fi

    sync_syntax_pack

    if [[ -n "$DRY_RUN" ]]; then
        log_info "[dry-run] would write this block to $NANORC:"
        render_nanorc
        [[ -n "$SET_EDITOR" ]] && set_default_editor
        exit 0
    fi

    # Tracked explicitly so the closing summary can tell the truth. Without
    # this, declining both prompts (or just hitting Enter, the documented
    # default) still fell through to the normal "Config: ... nano is ready"
    # summary and exit 0 — the ⚠️  Skipped lines above had already scrolled
    # past, and a student who declines out of habit was told the job was
    # done over an empty home directory.
    local nanorc_written="" editor_written=""

    if confirm "Write the qol block to $NANORC?"; then
        # write_nanorc, like install_nano_package and resolve_nano, gives its
        # own callers a meaningful non-zero return with a ❌ line already
        # printed on every failure path (dangling symlink, permission
        # denied, disk full) rather than letting a bare internal command
        # fail and take the whole script down under set -e with nothing but
        # a raw tool error.
        write_nanorc || exit 1
        nanorc_written=1
    else
        log_warn "Skipped writing $NANORC at your request."
    fi

    if [[ -n "$SET_EDITOR" ]]; then
        if confirm "Export EDITOR=nano and VISUAL=nano in your shell rc?"; then
            set_default_editor || exit 1
            editor_written=1
        else
            log_warn "Skipped setting EDITOR/VISUAL at your request."
        fi
    fi

    echo
    if [[ -z "$nanorc_written" && -z "$editor_written" ]]; then
        # Every prompt this run offered was declined (or every reply was
        # empty, which defaults to the same thing). Say so plainly instead
        # of the normal "ready" summary — nothing changed, so nothing
        # should sound finished.
        format_font "Nothing was changed — every prompt was declined.
Re-run without --yes and answer y, or pass --yes, to actually write the config." bold yellow
        echo
        exit 0
    fi

    if [[ -n "$nanorc_written" ]]; then
        local syntax_line
        if [[ -d "$SYNTAX_DIR" ]]; then
            syntax_line="Syntax:      $SYNTAX_DIR (community) + the definitions shipped with nano"
        else
            # Covers both --no-syntax and a clone that never happened (no
            # git, or a failed clone) — printing a path that doesn't exist
            # would be its own small trust-eroding bug, same spirit as
            # never warning about a syntax include that matches nothing.
            syntax_line="Syntax:      the definitions shipped with nano (no community pack)"
        fi
        format_font "Config:      $NANORC
$syntax_line
Cheat sheet: $SCRIPT_DIR/docs/nano-cheatsheet.html
^S saves. ^X exits. ^Z suspends (fg to resume). M-U undoes, M-E redoes." normal blue
    else
        # Mixed case: EDITOR was set but the qol block itself was declined.
        # nano is still installed and usable — just not configured by this
        # run — so say that plainly rather than showing a Config: block for
        # a file that was never written.
        format_font "$NANORC was not written (declined). nano itself is installed and usable." normal blue
    fi

    if [[ -n "$SET_EDITOR" && -z "$editor_written" ]]; then
        format_font "EDITOR/VISUAL were not set (declined)." normal blue
    fi

    format_font "nano is ready. Open a new file to see it." bold green
    echo
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
