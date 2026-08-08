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

printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ "$TESTS_FAILED" -eq 0 ]]
