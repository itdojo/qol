#!/usr/bin/env bash
# Proves gotime's menu repaints in place instead of clearing the screen first.
#
# No test framework by design — same rationale as test-install-nano.sh.
#
# `tput clear` emits ESC[H ESC[J: home the cursor, then erase everything from
# there to the end of the screen. Doing that at the top of draw() leaves the
# terminal blank for the ~40 separate writes it takes to repaint, which reads
# as a flicker on every keypress — measured at 33 ms per press on a 30-item
# menu, with the visible ink dropping from ~593 px to ~30.
#
# The fix is to home the cursor, overwrite each line in place (each erasing
# its own tail), and erase to end of screen only after the frame is painted.
# So: at most one screen-clear for the whole session, not one per keypress.
#
# Needs a pty — gotime suppresses all color and chrome when stdout is not a
# terminal, and never enters the menu at all without one.
#
# Run: ./tests/test-gotime-draw.sh
set -uo pipefail

TESTS_RUN=0
TESTS_FAILED=0
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAP="$(mktemp -t gotime-draw)"
trap 'rm -f "$CAP"' EXIT

# `script` takes the command differently on BSD/macOS and util-linux.
#
# Feed the keys one at a time with a gap, rather than dumping them and closing
# the pipe. Two races otherwise: gotime's first draw is slow — three `tput`
# forks per frame — so a burst can land before it is reading; and EOF on the
# pipe decodes as QUIT, cutting the session short at whatever frame it reached.
# Pacing puts each key in front of a gotime already blocked on read, and the
# trailing sleep holds stdin open until well after the final `q` is handled.
run_in_pty() {  # run_in_pty <outfile> <key>...
    local out="$1"; shift
    local k
    {
        for k in "$@"; do printf '%b' "$k"; sleep 0.2; done
        sleep 1
    } | if script -q /dev/null true >/dev/null 2>&1; then
            script -q /dev/null "$ROOT/gotime"
        else
            script -q -c "$ROOT/gotime" /dev/null
        fi > "$out" 2>&1
}

assert_le() {
    local actual="$1" limit="$2" label="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if (( actual <= limit )); then
        printf '  ok   %s (%d <= %d)\n' "$label" "$actual" "$limit"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s\n       expected at most %d, got %d\n' "$label" "$limit" "$actual"
    fi
}

assert_ge() {
    local actual="$1" floor="$2" label="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if (( actual >= floor )); then
        printf '  ok   %s (%d >= %d)\n' "$label" "$actual" "$floor"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s\n       expected at least %d, got %d\n' "$label" "$floor" "$actual"
    fi
}

# Six down-arrows then q: seven frames drawn, so a clear-per-frame
# implementation emits seven screen-clears and an in-place one emits at most
# the single clear that sets up the alternate screen.
printf '\nthe menu repaints without blanking the screen\n'
run_in_pty "$CAP" '\033[B' '\033[B' '\033[B' '\033[B' '\033[B' '\033[B' 'q'

# Count position, not just the erase. ESC[J erases from the cursor to the end
# of the screen, so what it costs depends entirely on where the cursor is:
# straight after ESC[H it wipes the whole screen (this is literally what `tput
# clear` emits, as one adjacent pair), while at the foot of a painted frame it
# only drops the tail below it. Only the first is a flicker.
clears="$(perl -ne '$c++ while /\e\[H\e\[[012]?J/g; END{print $c || 0}' "$CAP")"
wipes="$(perl -ne  '$c++ while /\e\[2J/g;           END{print $c || 0}' "$CAP")"
homes="$(perl -ne  '$c++ while /\e\[H/g;            END{print $c || 0}' "$CAP")"
eols="$(perl -ne   '$c++ while /\e\[K/g;            END{print $c || 0}' "$CAP")"

printf '     measured: clears=%s wipes=%s homes=%s eols=%s\n' "$clears" "$wipes" "$homes" "$eols"

# These two are timing-independent: they hold at any frame count above zero,
# and clearing per frame breaks the first one as soon as a second frame draws.
assert_le "$clears" 1 "at most one home-then-wipe for the whole session"
assert_le "$wipes"  0 "no full-screen ESC[2J at all"

# This one needs enough frames to be meaningful. Without a per-line erase,
# moving the highlight off a row leaves that row's selection background
# painted across the rest of the line — the clear-first implementation
# emitted exactly one CLR_EOL per frame, since only the selected row carried
# one, where repainting in place emits one per line drawn. Say so out loud if
# the pty gave us too few frames to judge; a quietly skipped check reads as a
# pass it did not earn.
if (( homes >= 2 )); then
    assert_ge "$eols" $(( homes * 5 )) "every line erases its own tail, not just the selected row"
else
    printf '  SKIP only %d frame(s) captured — cannot judge the per-line erase\n' "$homes"
    printf '       (not a pass: re-run, and investigate if it persists)\n'
fi

printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ "$TESTS_FAILED" -eq 0 ]]
