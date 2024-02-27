#!/bin/bash

# This script installs Zsh, Oh My Zsh, Powerlevel10k, and Nerd Fonts.
# It also sets up the Zsh plugins: zsh-autosuggestions, zsh-syntax-highlighting, and zsh-completions.
# It is intended to be run on a fresh install of a Debian-based Linux distribution or macOS.
# It will prompt for your password if it needs to install any packages.
# Usage: ./install_zsh.sh

source linux/base_functions.sh
source ./tool_checks.sh


check_for_oh_my_zsh() {
    if [[ ! -d ~/.oh-my-zsh ]]; then
        fstring "#️⃣  Installing Oh My Zsh..."
        echo "y" | sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    fi
    fstring "✅  Oh-My-Zsh is installed."
}

update_zshrc() {
    fstring "#️⃣  Updating .zshrc, setting Powerlevel10 as zsh theme..."
    sed -i.bak 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$HOME"/.zshrc
}

download_fonts() {
    set_fonts_dir
    for font in "${meslo_fonts[@]}"; do
        if [[ -f "$fonts_dir""$font" ]]; then
            fstring "⚠️  $font font is already installed."
        else
            fstring "#️⃣  Downloading $font..."
            dlfont=$(sed 's| |%20|g' <<< "$font")             # Replace spaces with %20
            wget "$font_url""$dlfont" -O "$fonts_dir""$font"  # Download font
        fi
    done
    fstring "✅  MesloLGS NF Fonts are installed."
}

install_nerd_fonts() {
    fstring "#️⃣  Installing Nerd Fonts..."
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
    fstring "✅  Nerd Fonts are installed."
}

set_fonts_dir() {
    fstring "#️⃣  Setting Fonts Directory..."
    if [[ $( echo "$os") = "Darwin" ]]; then
        fonts_dir="$HOME/Library/Fonts/"
    else
        if [[ ! -d "$HOME"/.fonts ]]; then
            mkdir -p "$HOME"/.fonts/truetype/MesloLGS-NF/
        fi
        fonts_dir="$HOME"/.fonts/truetype/MesloLGS-NF/
    fi
    fstring "✅  Fonts Directory is set to $fonts_dir"
}

install_zsh_plugins() {
    for plugin in "${plugins[@]}"; do
        if [ -d "${ZSH_CUSTOM:-"$HOME"/.oh-my-zsh/custom}/plugins/$plugin" ]; then
            fstring "✅  $plugin is already installed."
        else
            fstring "#️⃣  Installing $plugin..."
            rm -rf "${ZSH_CUSTOM:-"$HOME"/.oh-my-zsh/custom}/plugins/$plugin"
            git clone "https://github.com/zsh-users/$plugin.git" "${ZSH_CUSTOM:-"$HOME"/.oh-my-zsh/custom}/plugins/$plugin"
        fi
    done
    sed -i.bak 's|^plugins=.*|plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)|' "$HOME"/.zshrc
    fstring "✅  Zsh Plugins zsh-autosuggestions, zsh-syntax-highlighting, are zsh-completions are installed."
}

not_as_root

os=$(uname -s)

fonts_to_get=(  
    https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf
    https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf
    https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf
    https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf
)   

# Fonts required to get most out of Powerlevel10k
meslo_fonts=(
    "MesloLGS NF Regular.ttf"
    "MesloLGS NF Bold.ttf"
    "MesloLGS NF Italic.ttf"
    "MesloLGS NF Bold Italic.ttf"
)
# fonts_to_get=(
#     "MesloLGS%20NF%20Regular.ttf"
#     "MesloLGS%20NF%20Bold.ttf"
#     "MesloLGS%20NF%20Italic.ttf"
#     "MesloLGS%20NF%20Bold%20Italic.ttf"
# )

font_url="https://github.com/romkatv/powerlevel10k-media/raw/master/"
plugins=(zsh-autosuggestions zsh-syntax-highlighting zsh-completions)

fonts_dir=""
set_fonts_dir
check_for_git
check_for_wget
check_for_curl
check_for_zsh
check_for_oh_my_zsh
install_nerd_fonts

case "$os" in
    Darwin)
        if ! command -v brew &> /dev/null
            then
            fstring "#️⃣  Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        local_dir="$HOME/Library/Fonts/"
        download_fonts "$local_dir"
        install_status=$(brew list powerlevel10k)
        if [ $? -eq 0 ]; then
            fstring "✅  Powerlevel10k is already installed."
        else
            fstring "#️⃣  Installing Powerlevel10k..."
            brew install powerlevel10k
            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
            echo "source $(brew --prefix)/share/powerlevel10k/powerlevel10k.zsh-theme" >>~/.zshrc
            fstring "✅  Powerlevel10k is installed."
        fi
        #git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
        ;;
    Linux)
        local_dir="/usr/share/fonts/truetype/MesloLGS-NF/"
        download_fonts $local_dir
        fstring "#️⃣  Updating Font Cache..."
        cd && fc-cache -fv
        fstring "#️⃣  Installing Powerlevel10k...."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
        fstring "✅  Powerlevel10k is installed."
        fstring "#️⃣  Changing default shell to Zsh. Your password is required."
        chsh -s /usr/bin/zsh
        ;;
    *)
        fstring "❌  Unsupported OS. Quitting."
        exit 1
        ;;
esac

update_zshrc
install_zsh_plugins

fstring "After restarting your terminal, the PowerLevel10k (p10k) setup wizard will run. Run 'p10k configure' any time to reconfigure your preferences."
fstring "✅  Install complete. Please restart your terminal." "bold" "red"

echo ""
