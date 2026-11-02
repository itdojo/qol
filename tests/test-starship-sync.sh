#!/usr/bin/env bash
# Proves configs/starship.toml matches the copy install_zsh_starship.sh writes,
# past that heredoc's generated-file header.
#
# The AI-course seats run the installer and then fetch configs/starship.toml
# over its output, so any drift between the two is what the seats show. On
# 2026-09-11 configs/ alone switched to `palette = 'catppuccin_mocha'`, a
# palette that defines none of the grove names the format uses, and every
# seat's prompt rendered with no colors until the installer was rerun by hand.
#
# Run: ./tests/test-starship-sync.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

heredoc="$(sed -n "/^write_starship_config() {/,/^TOML\$/p" "$ROOT/install_zsh_starship.sh" \
    | sed '1,/<<.TOML./d;$d' | sed '/^[^#]/,$!d')"
config="$(cat "$ROOT/configs/starship.toml")"

if [[ -z "$heredoc" ]]; then
    printf 'FAIL no starship heredoc found in install_zsh_starship.sh\n'
    exit 1
fi
if [[ "$heredoc" == "$config" ]]; then
    printf 'ok   configs/starship.toml matches the installer heredoc\n'
    exit 0
fi
printf 'FAIL configs/starship.toml has drifted from the installer heredoc\n'
diff <(printf '%s\n' "$config") <(printf '%s\n' "$heredoc") | sed 's/^/       /'
exit 1
