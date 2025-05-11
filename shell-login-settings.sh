#!/bin/bash

# My shell settings

gitssh() {
    local github_ssh_key="github-office"

    if [[ ! -f ~/.ssh/"$github_ssh_key" ]]; then
        printf "%s\n" "⚠️  No SSH key named '$github_ssh_key' found." "Cannot authenticate to GitHub without SSH key." >&2
        return 1
    fi

    eval "$(ssh-agent)" >/dev/null
    ssh-add ~/.ssh/"$github_ssh_key" >/dev/null

    if ! ssh -T git@github.com 2>&1 | grep -q "You've successfully authenticated"; then
        printf "%s\n" "❌  GitHub Authentication: Failed." >&2
        return 1
    else
        printf "%s\n" "✅  GitHub Authentication: Success." >&2
    fi
} 


