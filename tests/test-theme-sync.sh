#!/usr/bin/env bash
# Proves the two copies of the theme block have not drifted.
#
# install_zsh_starship.sh must run on macOS, where linux/base_functions.sh is
# unavailable, so it embeds a copy. This test is the only thing keeping that
# copy honest.
#
# Run: ./tests/test-theme-sync.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/linux/base_functions.sh"
EMBED="$ROOT/install_zsh_starship.sh"

# The theme section runs from the qol_init_color definition through the
# closing brace of log_title.
extract() {
    sed -n '/^qol_init_color() {/,/^# ‒‒ end theme block/p' "$1"
}

a="$(extract "$LIB")"
b="$(extract "$EMBED")"

if [[ -z "$a" ]]; then
    printf 'FAIL no theme block found in %s\n' "$LIB"
    exit 1
fi
if [[ -z "$b" ]]; then
    printf 'FAIL no theme block found in %s\n' "$EMBED"
    exit 1
fi
if [[ "$a" == "$b" ]]; then
    printf '  ok   theme block is identical in both files (%d lines)\n' "$(printf '%s\n' "$a" | wc -l | tr -d ' ')"
    printf '\n1 run, 0 failed\n'
    exit 0
fi

printf '  FAIL theme block has drifted\n'
diff <(printf '%s\n' "$a") <(printf '%s\n' "$b")
printf '\n1 run, 1 failed\n'
exit 1
