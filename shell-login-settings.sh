#!/bin/bash

# My shell settings

gitssh() {
    local GITHUB_SSH_KEY="github-office2"

    if [ -f ~/.ssh/"$GITHUB_SSH_KEY" ]; then
        eval "$(ssh-agent)" &>/dev/null
        ssh-add ~/.ssh/"$GITHUB_SSH_KEY" &>/dev/null
        ssh -T git@github.com &>/dev/null
        if [ $? -eq 1 ]; then
            printf "%s\n" "❌  GitHub Authentication: Failed." >&2
            return 1
        else
            printf "%s\n" "✅  GitHub Authentication: Success." >&2
            return 0
        fi
        return 0
    else
        printf "%s\n" "⚠️  No SSH key named '$GITHUB_SSH_KEY' found." >&2
        printf "%s\n" "Cannot authenticate to GitHub without SSH key." >&2
        return 1
    fi
}   

if [ "$(uname -s)" = "Linux" ]; then
    echo "Linux"
    source /etc/os-release
fi


if [ -f ~/.ssh/github ]; then
    
fi


