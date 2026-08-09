#!/usr/bin/env bash
# Test harness for the IT Dojo terminal theme in linux/base_functions.sh.
#
# No test framework by design — same rationale as test-install-nano.sh.
#
# Run: ./tests/test-theme.sh
set -uo pipefail

TESTS_RUN=0
TESTS_FAILED=0
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/linux/base_functions.sh"

# shellcheck source=/dev/null
source "$LIB"

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

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '  ok   %s\n' "$label"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s\n       missing substring: %s\n' "$label" "$needle"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        printf '  ok   %s\n' "$label"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s\n       unexpected substring: %s\n' "$label" "$needle"
    fi
}

# Exit-status assertions, for helpers whose answer is 0/1 rather than stdout.
assert_ok() {
    local cmd="$1" label="$2" rc=0
    TESTS_RUN=$((TESTS_RUN + 1))
    eval "$cmd" >/dev/null 2>&1 || rc=$?
    if (( rc == 0 )); then
        printf '  ok   %s\n' "$label"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s\n       expected exit 0, got %d from: %s\n' "$label" "$rc" "$cmd"
    fi
}

assert_fail() {
    local cmd="$1" label="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if eval "$cmd" >/dev/null 2>&1; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s\n       expected nonzero exit, got 0 from: %s\n' "$label" "$cmd"
    else
        printf '  ok   %s\n' "$label"
    fi
}

# ‒‒ prefix arithmetic ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
printf '\nprefix is 9 columns for every badge\n'
QOL_COLOR_DEPTH=none qol_init_color
for pair in "log_step:STEP" "log_ok:PASS" "log_info:INFO" "log_warn:WARN" \
            "log_ask:ASK" "log_next:NEXT"; do
    fn="${pair%%:*}"; badge="${pair##*:}"
    line="$("$fn" "X")"
    assert_eq "▌ $(printf '%-4s' "$badge")   X" "$line" "$fn emits a 9-column prefix"
done
line="$(log_err "X" 2>&1)"
assert_eq "▌ STOP   X" "$line" "log_err emits a 9-column prefix"

printf '\nmessage text starts at column 10\n'
line="$(log_step "MSG")"
assert_eq "MSG" "${line:9}" "column 10 onward is the message"

# ‒‒ stderr routing ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
printf '\nlog_err goes to stderr, nothing else does\n'
assert_eq "" "$(log_err "X" 2>/dev/null)" "log_err writes nothing to stdout"
assert_eq "" "$(log_warn "X" 2>&1 1>/dev/null)" "log_warn writes nothing to stderr"

# ‒‒ depth tiers ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
printf '\ndepth tiers emit the right escapes\n'
QOL_FORCE_COLOR=1 QOL_COLOR_DEPTH=truecolor qol_init_color
assert_contains "$(log_step X)" $'\033[38;2;188;176;232m' "truecolor STEP is 188;176;232"
assert_contains "$(log_ok X)"   $'\033[38;2;78;206;106m'  "truecolor PASS is 78;206;106"

QOL_FORCE_COLOR=1 QOL_COLOR_DEPTH=256 qol_init_color
assert_contains "$(log_step X)" $'\033[38;5;140m' "256 STEP is index 140"
assert_contains "$(log_ok X)"   $'\033[38;5;77m'  "256 PASS is index 77"

QOL_FORCE_COLOR=1 QOL_COLOR_DEPTH=8 qol_init_color
assert_contains "$(log_step X)" $'\033[94m' "8-color STEP is bright blue"
assert_contains "$(log_err X 2>&1)" $'\033[91m' "8-color STOP is bright red"

QOL_COLOR_DEPTH=none qol_init_color
assert_not_contains "$(log_step X)" $'\033[' "none emits no escapes at all"

printf '\nNO_COLOR wins over a forced depth\n'
NO_COLOR=1 QOL_COLOR_DEPTH=truecolor qol_init_color
assert_not_contains "$(log_step X)" $'\033[' "NO_COLOR suppresses color"
unset NO_COLOR

# ‒‒ gutter survives every tier ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
printf '\nthe gutter bar prints at every depth\n'
for d in truecolor 256 8 none; do
    QOL_FORCE_COLOR=1 QOL_COLOR_DEPTH="$d" qol_init_color
    assert_contains "$(log_step X)" "▌" "gutter present at depth=$d"
done

# ‒‒ back-compat ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
printf '\nthe old style_text color names still resolve\n'
QOL_FORCE_COLOR=1 QOL_COLOR_DEPTH=256 qol_init_color
assert_contains "$(style_text hi normal green)"  $'\033[38;5;77m'  "green aliases jade"
assert_contains "$(style_text hi normal red)"    $'\033[38;5;168m' "red aliases wine"
assert_contains "$(style_text hi normal yellow)" $'\033[38;5;179m' "yellow aliases saffron"
assert_contains "$(style_text hi normal blue)"   $'\033[38;5;110m' "blue aliases steel"
assert_contains "$(style_text hi normal violet)" $'\033[38;5;140m' "violet is addressable by name"

printf '\nstyle_text still honors weight independently of ink\n'
assert_not_contains "$(style_text hi normal green)" $'\033[1m' "normal weight is not bold"
assert_contains     "$(style_text hi bold green)"   $'\033[1m' "bold weight is bold"

printf '\nfstring still dispatches\n'
QOL_COLOR_DEPTH=none qol_init_color
assert_eq "▌ PASS   done" "$(fstring done success)" "fstring success maps to PASS"
assert_eq "▌ WARN   careful" "$(fstring careful warning)" "fstring warning maps to WARN"

printf '\ncheck_status still reports through the new helpers\n'
assert_eq "▌ PASS   Thing: SUCCESS" "$(check_status "Thing" 0)" "check_status 0 is PASS"
assert_contains "$(check_status "Thing" 3 2>&1)" "▌ STOP   Thing: FAILED (exit 3)" "check_status nonzero is STOP"

# ‒‒ helpers ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
printf '\n_repeat builds fills\n'
assert_eq "─────" "$(_repeat '─' 5)" "_repeat emits n copies"
assert_eq "" "$(_repeat '─' 0)" "_repeat 0 is empty"
assert_eq "" "$(_repeat '─' -3)" "_repeat negative is empty"

printf '\nno function shadows a bash builtin\n'
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$(type -t complete)" == "builtin" ]]; then
    printf '  ok   complete is still the bash builtin\n'
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL complete was shadowed by a function\n'
fi

_strip_ansi() {
    printf '%s' "$1" | sed -E $'s/\x1b\\[[0-9;]*m//g'
}

# ‒‒ log_phase, banner, log_complete ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
printf '\nlog_phase fill arithmetic is exact\n'
QOL_COLOR_DEPTH=none qol_init_color
cols="$(_term_cols)"
title="DOCKER ENGINE"
line="$(log_phase "$title" | sed -n '2p')"
assert_contains "$line" "── ${title} " "log_phase (none) content line reads '── TITLE '"
assert_eq "$cols" "${#line}" "log_phase (none) total rule width equals terminal width"

printf '\nlog_phase fill arithmetic holds at every depth\n'
for d in truecolor 256 8 none; do
    QOL_FORCE_COLOR=1 QOL_COLOR_DEPTH="$d" qol_init_color
    cols="$(_term_cols)"
    title="DOCKER ENGINE"
    raw="$(log_phase "$title" | sed -n '2p')"
    stripped="$(_strip_ansi "$raw")"
    assert_contains "$stripped" "$title" "log_phase carries the title at depth=$d"
    assert_eq "$cols" "${#stripped}" "log_phase total rule width equals terminal width at depth=$d"
done

printf '\nlog_phase guards a title longer than the terminal width\n'
for d in truecolor 256 8 none; do
    QOL_FORCE_COLOR=1 QOL_COLOR_DEPTH="$d" qol_init_color
    cols="$(_term_cols)"
    long_title="$(_repeat 'X' $((cols + 20)))"
    raw="$(log_phase "$long_title" | sed -n '2p')"
    stripped="$(_strip_ansi "$raw")"
    assert_contains "$stripped" "$long_title" "log_phase with an over-long title still prints the full title at depth=$d"
    assert_eq "$((${#long_title} + 4))" "${#stripped}" "log_phase with an over-long title emits zero fill (not negative) at depth=$d"
done

printf '\nbanner emits three lines; subtitle rides the middle line\n'
for d in truecolor 256 8 none; do
    QOL_FORCE_COLOR=1 QOL_COLOR_DEPTH="$d" qol_init_color

    out="$(banner "X")"
    line_count="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
    assert_eq "3" "$line_count" "banner (no subtitle) emits three lines at depth=$d"
    mid="$(printf '%s\n' "$out" | sed -n '2p')"
    assert_contains "$mid" "⛩ X ⛩" "banner (no subtitle) middle line carries the title at depth=$d"

    out_sub="$(banner "X" "sub")"
    line_count_sub="$(printf '%s\n' "$out_sub" | wc -l | tr -d ' ')"
    assert_eq "3" "$line_count_sub" "banner (with subtitle) still emits three lines at depth=$d"
    mid_sub="$(printf '%s\n' "$out_sub" | sed -n '2p')"
    assert_contains "$mid_sub" "⛩ X ⛩" "banner (with subtitle) keeps the title on the middle line at depth=$d"
    assert_contains "$mid_sub" "sub" "banner (with subtitle) puts the subtitle on the middle line at depth=$d"
done

printf '\nlog_complete emits the crest and the title\n'
for d in truecolor 256 8 none; do
    QOL_FORCE_COLOR=1 QOL_COLOR_DEPTH="$d" qol_init_color
    out="$(log_complete "X")"
    assert_contains "$out" "⛩ X ⛩" "log_complete carries the crest and the title at depth=$d"
done

# ‒‒ question shapes ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Every case below runs with stdin on /dev/null, so all three helpers take
# their non-interactive path deterministically — the path cron and CI hit.
# Forcing it matters: a bare `./tests/test-theme.sh` from a terminal has a TTY
# on stdin, and these helpers would block on `read` rather than fail. The
# interactive path is driven by hand instead (Task 8 step 5); the keymap that
# makes it work is covered by the _read_key cases at the end of this block.
{
printf '\nnon-interactive questions return their defaults\n'
QOL_COLOR_DEPTH=none qol_init_color
unset ASSUME_YES

assert_eq "/var/lib/docker" "$(ask_value "Data root" "/var/lib/docker")" \
    "ask_value returns the default"
assert_eq "2" "$(ask_choice "DRIVER" 2 "overlay2|fast" "vfs|slow")" \
    "ask_choice returns the default index"
assert_fail 'ask_confirm "Proceed?" N' "ask_confirm default N is no"
assert_ok   'ask_confirm "Proceed?" Y' "ask_confirm default Y is yes"

printf '\nASSUME_YES forces the yes path\n'
assert_ok 'ASSUME_YES=1 ask_confirm "Proceed?" N' "ASSUME_YES overrides a No default"

printf '\nprompts go to stderr, answers to stdout\n'
assert_not_contains "$(ask_value "Q" "d" "hint" 2>/dev/null)" "Q" \
    "ask_value emits no prompt on stdout"
assert_eq "d" "$(ask_value "Q" "d" "hint" 2>/dev/null)" \
    "ask_value's stdout is the answer alone"
assert_not_contains "$(ask_choice "H" 1 "a|x" "b|y" 2>/dev/null)" "H" \
    "ask_choice's stdout carries no heading"
} < /dev/null

# ‒‒ ask_choice row geometry ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# The selection bar has to reach the right edge, which means the row is padded
# with real spaces rather than erased with CLR_EOL: screen and tmux have no
# `bce`, so ESC[K there erases to the default background and truncates the bar
# exactly where it started. Padding an unselected row matters just as much —
# it is what paints over the bar the row is losing.
printf '\nask_choice rows fill the width so the selection bar spans it\n'
QOL_COLOR_DEPTH=none qol_init_color
_rows="$(_ask_choice_draw "DRIVER" 0 "overlay2|fast" "vfs|slow")"
_cols="$(_term_cols)"
_sel="$(printf '%s\n' "$_rows" | sed -n '3p')"
_un="$(printf '%s\n' "$_rows" | sed -n '4p')"
assert_eq "$_cols" "${#_sel}" "the selected row is padded to the terminal width"
assert_eq "$_cols" "${#_un}"  "an unselected row is padded to the terminal width"

printf '\npadding survives a hint longer than the column it sits in\n'
_rows="$(_ask_choice_draw "DRIVER" 0 "a|$(printf 'x%.0s' $(seq 1 200))" "b|short")"
_sel="$(printf '%s\n' "$_rows" | sed -n '3p')"
TESTS_RUN=$((TESTS_RUN + 1))
if (( ${#_sel} >= _cols )); then
    printf '  ok   an over-long row is never truncated to less than the width\n'
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL an over-long row shrank below the width (%d < %d)\n' "${#_sel}" "$_cols"
fi

# A here-string, not a pipe: the right side of a pipe is a subshell, so the
# _KEY it set would be discarded before the assertion could read it.
printf '\n_read_key decodes without a TTY\n'
_KEY=""; _read_key <<< "j"
assert_eq "DOWN" "$_KEY" "_read_key maps j to DOWN"
_KEY=""; _read_key <<< "k"
assert_eq "UP" "$_KEY" "_read_key maps k to UP"
_KEY=""; _read_key <<< "3"
assert_eq "DIGIT" "$_KEY" "_read_key maps a digit to DIGIT"
assert_eq "3" "$_KEYCH" "_read_key records the digit character"
_KEY=""; _read_key <<< "q"
assert_eq "QUIT" "$_KEY" "_read_key maps q to QUIT"
_KEY=""; _read_key < /dev/null
assert_eq "QUIT" "$_KEY" "_read_key treats a closed stdin as QUIT"

printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ "$TESTS_FAILED" -eq 0 ]]
