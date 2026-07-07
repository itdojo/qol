#!/bin/bash
# shellcheck shell=bash
#
# shell-login-settings.sh — personal login-shell helpers.
# Source this from .bashrc / .zshrc:
#     source /path/to/shell-login-settings.sh
#
# Output here is deliberately compact (no separator lines) because these
# functions run inside interactive login shells.

# Authenticate to GitHub over SSH, reusing a running ssh-agent when possible.
gitssh() {
    local key_name="github-office"
    local key_file="$HOME/.ssh/$key_name"

    if [ ! -f "$key_file" ]; then
        printf '%s\n' "⚠️   No SSH key named '$key_name' found in ~/.ssh." \
                      "    Cannot authenticate to GitHub without an SSH key." >&2
        return 1
    fi

    # ssh-add -l returns 2 when it can't reach an agent; only then start one,
    # so repeated calls don't leak a new ssh-agent process each time.
    local agent_rc=0
    ssh-add -l >/dev/null 2>&1 || agent_rc=$?
    if [ "$agent_rc" -eq 2 ]; then
        if ! eval "$(ssh-agent -s)" >/dev/null; then
            printf '%s\n' "❌  Could not start ssh-agent." >&2
            return 1
        fi
    fi

    if ! ssh-add "$key_file" >/dev/null 2>&1; then
        printf '%s\n' "❌  Could not add '$key_name' to the ssh-agent." >&2
        return 1
    fi

    # GitHub always closes the test connection, so check the banner text
    # rather than the ssh exit status.
    if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        printf '%s\n' "✅  GitHub Authentication: Success."
    else
        printf '%s\n' "❌  GitHub Authentication: Failed." >&2
        return 1
    fi
}
