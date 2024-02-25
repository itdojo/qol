#!/bin/bash

# My shell settings

gitssh() {
    if [ -f ~/.ssh/github ]; then
        eval "$(ssh-agent)"
        ssh-add ~/.ssh/github
        ssh -T git@github.com
        return 0
    else
        echo "No SSH key named "github" found."
        echo "Cannot connect to GitHub without SSH key."
        return 1
    fi
}   

if ! uname -s = "Darwin"; then
    . /etc/os-release
fi

myshell=$(echo $SHELL)
case $myshell in
    /bin/bash)
        gitssh
        ;;
    /bin/zsh)
        gitssh
        ;;
    *)
        echo "Unknown shell detected"
        ;;
esac

if [ -f ~/.ssh/github ]; then
    
fi


