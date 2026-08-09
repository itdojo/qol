#!/usr/bin/env bash
# Proves gotime reads its workspace layout from config rather than from paths
# baked into the script.
#
# No test framework by design — same rationale as test-install-nano.sh.
#
# Until 2026-08-09 gotime hardcoded ~/courseware, ~/projects, and a pinned
# ~/vaults/dojobrain window, so it did nothing useful on anyone else's machine
# and published the author's directory layout in a public repo. The layout now
# comes from GOTIME_ROOTS / GOTIME_PIN, read from a config file that the
# environment can override. These checks cover the parts that can go quietly
# wrong: precedence between the two, labels defaulting to a directory's own
# name, and the window shape when there is no pin to put first.
#
# The launch checks need tmux and are skipped without it. They build real
# sessions under a test-only name and kill them afterwards; GOTIME_CMD is
# `true` so nothing long-lived is started inside them.
#
# Run: ./tests/test-gotime-config.sh
set -uo pipefail

TESTS_RUN=0
TESTS_FAILED=0
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOTIME="$ROOT/gotime"
FIXTURE="$(mktemp -d -t gotime-config)"
SESSION="gotime-test-$$"

cleanup() {
    command -v tmux >/dev/null 2>&1 && tmux kill-session -t "=$SESSION" 2>/dev/null
    rm -rf "$FIXTURE"
}
trap cleanup EXIT

# Two trees with distinct names, so a check can tell which root an item came
# from. "sandbox" carries no explicit label, which is what exercises the
# label-defaults-to-basename path.
mkdir -p "$FIXTURE/courses/wireshark" "$FIXTURE/courses/pki"
mkdir -p "$FIXTURE/work/switchboard"
mkdir -p "$FIXTURE/sandbox/scratchpad"
mkdir -p "$FIXTURE/pinned"

assert_contains() {  # assert_contains <haystack> <needle> <label>
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$1" == *"$2"* ]]; then
        printf '  ok   %s\n' "$3"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s\n       expected to find: %s\n       in:\n%s\n' "$3" "$2" "$1"
    fi
}

assert_missing() {  # assert_missing <haystack> <needle> <label>
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$1" != *"$2"* ]]; then
        printf '  ok   %s\n' "$3"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s\n       did not expect: %s\n       in:\n%s\n' "$3" "$2" "$1"
    fi
}

assert_eq() {  # assert_eq <actual> <expected> <label>
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$1" == "$2" ]]; then
        printf '  ok   %s\n' "$3"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s\n       expected: %s\n       got:      %s\n' "$3" "$2" "$1"
    fi
}

# ---------------------------------------------------------------------------
printf '\nthe config file supplies the roots and their labels\n'

cat > "$FIXTURE/config" <<EOF
GOTIME_ROOTS="COURSES:$FIXTURE/courses WORK:$FIXTURE/work
$FIXTURE/sandbox"
GOTIME_PIN="pinned:$FIXTURE/pinned"
EOF

out="$(GOTIME_CONFIG="$FIXTURE/config" "$GOTIME" --list 2>&1)"
assert_contains "$out" "COURSES"    "an explicit label heads its section"
assert_contains "$out" "wireshark"  "items are discovered under a configured root"
assert_contains "$out" "switchboard" "a second root is scanned too"
assert_contains "$out" "SANDBOX"    "a root with no label falls back to its own directory name"
assert_contains "$out" "pinned ($FIXTURE/pinned)" "--list reports the resolved pin"
assert_contains "$out" "$FIXTURE/config" "--list names the config file it read"

# Newline-separated entries are the form that lets a path survive being listed
# beside others; prove the third root above was not swallowed by the newline.
assert_contains "$out" "scratchpad" "a newline-separated root is parsed"

# ---------------------------------------------------------------------------
printf '\nthe environment outranks the config file\n'

out="$(GOTIME_CONFIG="$FIXTURE/config" GOTIME_ROOTS="ONLY:$FIXTURE/work" \
       GOTIME_PIN="" GOTIME_CMD=vim "$GOTIME" --list 2>&1)"
assert_contains "$out" "switchboard" "GOTIME_ROOTS from the environment is used"
assert_missing  "$out" "wireshark"   "the file's GOTIME_ROOTS is not merged in"
assert_contains "$out" "command: vim" "GOTIME_CMD from the environment wins"

# An empty GOTIME_PIN in the environment cannot be told from an unset one, so
# the file's pin still applies — documented behavior, asserted so a future
# change to it is a deliberate one.
assert_contains "$out" "pinned ($FIXTURE/pinned)" \
    "an empty GOTIME_PIN in the environment leaves the file's pin in place"

# ---------------------------------------------------------------------------
printf '\nwith no config at all it falls back to built-in defaults\n'

out="$(GOTIME_CONFIG="$FIXTURE/does-not-exist" "$GOTIME" --list 2>&1)"
assert_contains "$out" "none — using built-in defaults" "the absent config is reported, not invented"
assert_contains "$out" "pinned:  none" "no pinned window is configured by default"

# ---------------------------------------------------------------------------
printf '\n--init writes a starter config and refuses to clobber one\n'

target="$FIXTURE/fresh/config"
out="$(GOTIME_CONFIG="$target" "$GOTIME" --init 2>&1)"
assert_contains "$out" "wrote $target" "--init reports the file it wrote"

if [[ -f "$target" ]]; then
    printf '  ok   --init created the file\n'; TESTS_RUN=$((TESTS_RUN + 1))
    body="$(cat "$target")"
    assert_contains "$body" 'GOTIME_ROOTS='   "the starter carries GOTIME_ROOTS"
    assert_contains "$body" 'GOTIME_PIN=""'   "the starter leaves the pin empty"
    assert_contains "$body" '$HOME/'          "roots are written as \$HOME/... , not expanded"
    assert_missing  "$body" "$HOME/vaults"    "the starter carries no personal paths"
else
    TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL --init created the file\n'
fi

GOTIME_CONFIG="$target" "$GOTIME" --init >/dev/null 2>&1
assert_eq "$?" "1" "a second --init exits non-zero rather than overwriting"

# ---------------------------------------------------------------------------
if ! command -v tmux >/dev/null 2>&1; then
    printf '\n  SKIP tmux is not installed — the window-shape checks cannot run\n'
    printf '       (not a pass: install tmux and re-run)\n'
else
    windows() {  # windows <config-file> — the session's window names, in order
        tmux kill-session -t "=$SESSION" 2>/dev/null
        GOTIME_CONFIG="$1" GOTIME_SESSION="$SESSION" GOTIME_CMD=true \
            GOTIME_NO_ATTACH=1 "$GOTIME" wireshark >/dev/null 2>&1
        tmux list-windows -t "=$SESSION" -F '#{window_name}' 2>/dev/null | tr '\n' ' '
    }

    printf '\na pinned window is built ahead of the selection\n'
    assert_eq "$(windows "$FIXTURE/config")" "pinned wireshark local " \
        "three windows, pin first"

    printf '\nwithout a pin the selection is the first window\n'
    cat > "$FIXTURE/config-nopin" <<EOF
GOTIME_ROOTS="COURSES:$FIXTURE/courses"
GOTIME_PIN=""
EOF
    assert_eq "$(windows "$FIXTURE/config-nopin")" "wireshark local " \
        "two windows, no empty pin left behind"

    printf '\na configured pin that does not exist is reported, not substituted\n'
    cat > "$FIXTURE/config-badpin" <<EOF
GOTIME_ROOTS="COURSES:$FIXTURE/courses"
GOTIME_PIN="ghost:$FIXTURE/no-such-dir"
EOF
    tmux kill-session -t "=$SESSION" 2>/dev/null
    out="$(GOTIME_CONFIG="$FIXTURE/config-badpin" GOTIME_SESSION="$SESSION" \
           GOTIME_CMD=true GOTIME_NO_ATTACH=1 "$GOTIME" wireshark 2>&1)"
    assert_contains "$out" "not found" "the missing pin is warned about"
    assert_eq "$(tmux list-windows -t "=$SESSION" -F '#{window_name}' 2>/dev/null | tr '\n' ' ')" \
        "wireshark local " "and the session is built without it"
fi

printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ "$TESTS_FAILED" -eq 0 ]]
