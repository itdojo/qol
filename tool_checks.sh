#!/bin/bash

source linux/base_functions.sh

check_for_wget() {
    if ! command -v wget &>/dev/null; then
        fstring "#️⃣  Installing wget..."
        if [ "$os" = "Darwin" ]; then
            brew install wget
        else
            install_packages wget
        fi
    fi
    fstring "✅  wget is installed."
}

check_for_zsh() {
    if ! command -v zsh &>/dev/null; then
        fstring "#️⃣  Installing Zsh..."
        if [[ "$os" = "Darwin" ]]; then
            brew install zsh
        else
            install_packages zsh
        fi
    fi
    fstring "✅  zsh is installed."
}

check_for_git() {
    if ! command -v git &>/dev/null; then
        fstring "#️⃣  Installing Git..."
        if [[ "$os" = "Darwin" ]]; then
            brew install git
        else
            install_packages git
        fi
    fi
    fstring "✅  Git is installed."
}

check_for_curl() {
    if ! command -v curl &>/dev/null; then
        fstring "#️⃣  Installing curl..."
        if [[ "$os" = "Darwin" ]]; then
            brew install curl
        else
            install_packages curl
        fi
    fi
    fstring "✅  curl is installed."
}
