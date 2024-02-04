#!/bin/bash

# This script installs Zsh, Oh My Zsh, Powerlevel10k, and Nerd Fonts.
# It also sets up the Zsh plugins: zsh-autosuggestions, zsh-syntax-highlighting, and zsh-completions.
# It is intended to be run on a fresh install of a Debian-based Linux distribution or macOS.
# It will prompt for your password if it needs to install any packages.
# Usage: ./install_zsh.sh

check_for_root() {
    if [[ $EUID -eq 0 ]]; then
        echo
        echo "Do not run as root (sudo)."
        echo "You will be prompted if your password is needed."
        echo
        exit 1
    fi
}

check_for_zsh() {
    if ! command -v zsh &>/dev/null; then
        echo "Installing Zsh."
        if [[ "$os" = "Darwin" ]]; then
            brew install zsh
        else
            sudo apt install zsh
        fi
    fi
}

check_for_git() {
    if ! command -v git &>/dev/null; then
        echo "Installing Git."
        if [[ "$os" = "Darwin" ]]; then
            brew install git
        else
            sudo apt install git
        fi
    fi
}

check_for_oh_my_zsh() {
    if [[ ! -d ~/.oh-my-zsh ]]; then
        echo "Installing Oh My Zsh."
        echo "y" | sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    fi
}

update_zshrc() {
    echo "Updating .zshrc."
    sed -i.bak 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$HOME"/.zshrc
}


download_fonts() {
    set_fonts_dir
    echo "Downloading Fonts."
    for font in "${fonts_to_get[@]}"; do
        spaced_font=$(echo "$font" | sed 's|%20| |g')
        wget "$font_url""$font" -O "$fonts_dir""${spaced_font-}"
    done
}

install_nerd_fonts() {
    echo "Installing Nerd Fonts."
    if [[ "$os" = "Darwin" ]]; then
        brew tap homebrew/cask-fonts
        brew install font-hack-nerd-font
    else
        cd "$HOME"
        git clone --depth=1 https://github.com/ryanoasis/nerd-fonts.git
        cd nerd-fonts || exit
        ./install.sh
        cd "$HOME" && rm -rf nerd-fonts
    fi 
}

set_fonts_dir() {
    echo "Setting Fonts Directory."
    if [[ "$os" = "Darwin" ]]; then
        fonts_dir="$HOME/Library/Fonts/"
    else
        if [[ ! -d "$HOME"/.fonts ]]; then
            mkdir -p "$HOME"/.fonts/truetype/MesloLGS-NF/
        fi
        fonts_dir="$HOME/.fonts/truetype/MesloLGS-NF/"
    fi
}

install_zsh_plugins() {
    echo "Installing Zsh Plugins."
    for plugin in "${plugins[@]}"; do
        rm -rf "${ZSH_CUSTOM:-"$HOME"/.oh-my-zsh/custom}/plugins/$plugin"
        git clone "https://github.com/zsh-users/$plugin.git" "${ZSH_CUSTOM:-"$HOME"/.oh-my-zsh/custom}/plugins/$plugin"
        done
    sed -i.bak 's|^plugins=.*|plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)|' "$HOME"/.zshrc
}

check_for_root

os=$(uname -s)

fonts_to_get=(
    "MesloLGS%20NF%20Regular.ttf"
    "MesloLGS%20NF%20Bold.ttf"
    "MesloLGS%20NF%20Italic.ttf"
    "MesloLGS%20NF%20Bold%20Italic.ttf"
)

font_url="https://github.com/romkatv/powerlevel10k-media/raw/master/"
plugins=(zsh-autosuggestions zsh-syntax-highlighting zsh-completions)

set_fonts_dir
check_for_git
check_for_zsh
check_for_oh_my_zsh
install_nerd_fonts

case "$os" in
    Darwin)
        check_for_zsh "$os"
        if ! command -v brew &> /dev/null
            then
            echo "Installing Homebrew."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        local_dir="$HOME/Library/Fonts/"
        download_fonts "$local_dir"
        echo "Installing Powerlevel10k."
        brew install powerlevel10k
        echo "source $(brew --prefix)/share/powerlevel10k/powerlevel10k.zsh-theme" >>~/.zshrc
        ;;
    Linux)
        check_for_zsh "$os"
        if ! command -v curl &> /dev/null
        then
            echo "Installing curl."
            sudo apt install curl
        fi
        local_dir="/usr/share/fonts/truetype/MesloLGS-NF/"
        download_fonts $local_dir
        echo "Updating Font Cache."
        cd && fc-cache -fv
        echo "Installing Powerlevel10k."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
        chsh -s /usr/bin/zsh
        ;;
    *)
        echo "Unsupported OS. Quitting."
        exit 1
        ;;
esac

update_zshrc
install_zsh_plugins

echo "Done. Please restart your terminal."
