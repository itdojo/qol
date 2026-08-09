#!/usr/bin/env bash
# Proves the full-width elements actually match the terminal's width.
#
# No test framework by design — same rationale as test-install-nano.sh.
#
# This needs a pty, and a pty of a size we choose, because the bug it guards
# is invisible at 80 columns — which is exactly the width the broken code
# reported. `tput cols 2>/dev/null` inside a command substitution returns the
# terminfo default rather than the real size: with stdout captured, ncurses
# falls back to reading the window size off stderr, and the 2>/dev/null throws
# that fd away. Every rule, bookend and selection bar in the design system was
# pinned to 80 columns by that one redirect.
#
# Run: ./tests/test-term-width.sh
set -uo pipefail

TESTS_RUN=0
TESTS_FAILED=0
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/linux/base_functions.sh"
WIDTH=137   # deliberately not 80, and not a common default

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$expected" == "$actual" ]]; then
        printf '  ok   %s\n' "$label"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' \
            "$label" "$expected" "$actual"
    fi
}

# Run a snippet on a pty forced to $WIDTH columns, with COLUMNS unset so the
# code has to ask the terminal rather than read it out of the environment.
on_pty() {  # on_pty <snippet>
    local snippet="$1"
    printf '' | script -q /dev/null bash -c \
        "stty cols $WIDTH -echo -echoctl 2>/dev/null; unset COLUMNS; $snippet" 2>&1 \
        | tr -d '\r\004\010' | sed 's/\^D//g'
}

# Longest line, in characters not bytes — the rule glyphs are three bytes each
# in UTF-8, so a byte count reports an 80-column rule as 240. perl -CSD decodes
# stdin as UTF-8 so length() counts characters; awk on macOS does not.
widest() {
    perl -CSD -ne 's/\e\[[?0-9;]*[A-Za-z]//g; chomp; $m = length if length > ($m // 0);
                   END { print $m // 0 }'
}

printf '\nthe pty really is %s columns\n' "$WIDTH"
assert_eq "$WIDTH" "$(on_pty 'stty size </dev/tty | cut -d" " -f2' | tr -d ' \n')" \
    "stty confirms the forced width"

printf '\nbase_functions reports and uses the real width\n'
assert_eq "$WIDTH" "$(on_pty "source '$LIB'; _term_cols" | tr -d ' \n')" \
    "_term_cols reports the terminal width, not the terminfo default"
assert_eq "$WIDTH" "$(on_pty "source '$LIB'; QOL_COLOR_DEPTH=none qol_init_color; printline" | widest)" \
    "printline spans the terminal"
assert_eq "$WIDTH" "$(on_pty "source '$LIB'; QOL_COLOR_DEPTH=none qol_init_color; banner TITLE" | widest)" \
    "banner rules span the terminal"
assert_eq "$WIDTH" "$(on_pty "source '$LIB'; QOL_COLOR_DEPTH=none qol_init_color; log_phase PHASE" | widest)" \
    "log_phase rule spans the terminal"

# Hold the quit key back until `stty -echo` has run inside the pty. Written
# immediately it lands while echo is still on, and the pty prints it back —
# which shows up as a rule one column wider than the terminal.
printf '\ngotime carries its own copy of this and needs the same width\n'
assert_eq "$WIDTH" "$({ sleep 1; printf 'q'; sleep 1; } | script -q /dev/null bash -c \
    "stty cols $WIDTH -echo -echoctl 2>/dev/null; unset COLUMNS; '$ROOT/gotime'" 2>&1 \
    | tr -d '\r\004\010' | sed 's/\^D//g' | widest)" \
    "gotime's rules span the terminal"

# The bar is painted with real spaces, not stretched with CLR_EOL: screen and
# tmux report no `bce`, so ESC[K there erases to the default background and
# cuts the bar off where the text ended. Measuring the row with escapes
# stripped is exactly the check — a CLR_EOL-stretched bar measures as short as
# its text, a padded one measures the full width.
printf '\ngotime paints its selection bar rather than erasing to it\n'
_bar="$({ sleep 1; printf 'q'; sleep 1; } | script -q /dev/null bash -c \
    "stty cols $WIDTH -echo -echoctl 2>/dev/null; unset COLUMNS; '$ROOT/gotime'" 2>&1 \
    | tr -d '\r\004\010' | sed 's/\^D//g' \
    | perl -CSD -ne 's/\e\[[?0-9;]*[A-Za-z]//g; chomp; if (/\x{276f}/) { print length($_); exit }')"
assert_eq "$WIDTH" "${_bar:-0}" "the selected row is padded to the full terminal width"

printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ "$TESTS_FAILED" -eq 0 ]]
