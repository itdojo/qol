#!/bin/bash

# This script installs Zsh, Oh My Zsh, Powerlevel10k, and Nerd Fonts.
# It also sets up the Zsh plugins: zsh-autosuggestions, zsh-syntax-highlighting, and zsh-completions.
# It is intended to be run on a fresh install of a Debian-based Linux distribution or macOS.
# It will prompt for your password if it needs to install any packages.
# Usage: ./install_zsh.sh

check_for_root() {
    if [[ $EUID -eq 0 ]]; then
        echo
        echo "❌  Do not run as root.  You will be prompted if your password is needed."
        echo
        exit 1
    fi
}

# Define the function to be executed when SIGINT (CTRL-C) is received
handle_ctrl_c() {
    printf "%s\n" "CTRL-C detected. Exiting..."
    echo ""
    exit 1
}

printline() {
    printf "%.s─" $(seq 1 "$(tput cols)")    # Line style ─────────
    # printf "%.s∙" $(seq 1 "$(tput cols)")  # Line style ∙∙∙∙∙∙∙∙∙
    # printf "%.s⌶" $(seq 1 "$(tput cols)")  # Line style ⌶⌶⌶⌶⌶⌶⌶⌶
    # printf "%.s☆" $(seq 1 "$(tput cols)")  # Line style ☆☆☆☆☆☆☆☆☆   
    # printf "%.s⏥" "$(seq 1 "$(tput cols)") # Line style ⏥⏥⏥⏥⏥  
}

format_font() {
    local text="$1"
    local weight="$2"
    local color="$3"
    local reset="\033[0m"
    local color_code=""
    local weight_code=""

    # Define color codes
    case "$color" in
        blue) color_code="34";;
        red) color_code="31";;
        green) color_code="32";;
        yellow) color_code="33";;
        *) color_code="33";; # Default to yellow
    esac

    # Define weight codes
    case "$weight" in
        normal) weight_code="0";;
        bold) weight_code="1";;
        *) weight_code="1";; # Default to bold
    esac

    printline
    echo -e "\033[${weight_code};${color_code}m${text}${reset}"
}

check_for_zsh() {
    if ! command -v zsh &>/dev/null; then
        format_font "#️⃣  Installing Zsh..."
        if [[ "$os" = "Darwin" ]]; then
            brew install zsh
        else
            sudo apt install zsh
        fi
    fi
    format_font "✅  zsh is installed."
}

check_for_git() {
    if ! command -v git &>/dev/null; then
        format_font "#️⃣  Installing Git..."
        if [[ "$os" = "Darwin" ]]; then
            brew install git
        else
            sudo apt install git
        fi
    fi
    format_font "✅  Git is installed."
}

check_for_oh_my_zsh() {
    if [[ ! -d ~/.oh-my-zsh ]]; then
        format_font "#️⃣  Installing Oh My Zsh..."
        echo "y" | sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    fi
    format_font "✅  Oh-My-Zsh is installed."
}

update_zshrc() {
    format_font "#️⃣  Updating .zshrc..."
    sed -i.bak 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$HOME"/.zshrc
}


download_fonts() {
    set_fonts_dir
    format_font "#️⃣  Downloading Fonts..."
    for font in "${fonts_to_get[@]}"; do
        spaced_font=$(echo "$font" | sed 's|%20| |g')
        wget "$font_url""$font" -O "$fonts_dir""${spaced_font-}"
    done
    format_font "✅  Fonts are installed."
}

install_nerd_fonts() {
    format_font "#️⃣  Installing Nerd Fonts..."
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
    format_font "✅  Nerd Fonts are installed."
}

set_fonts_dir() {
    format_font "#️⃣  Setting Fonts Directory..."
    if [[ "$os" = "Darwin" ]]; then
        fonts_dir="$HOME/Library/Fonts/"
    else
        if [[ ! -d "$HOME"/.fonts ]]; then
            mkdir -p "$HOME"/.fonts/truetype/MesloLGS-NF/
        fi
        fonts_dir="$HOME"/.fonts/truetype/MesloLGS-NF/
    fi
    format_font "✅  Fonts Directory is set."
}

install_zsh_plugins() {
    format_font "#️⃣  Installing Zsh Plugins..."
    for plugin in "${plugins[@]}"; do
        rm -rf "${ZSH_CUSTOM:-"$HOME"/.oh-my-zsh/custom}/plugins/$plugin"
        git clone "https://github.com/zsh-users/$plugin.git" "${ZSH_CUSTOM:-"$HOME"/.oh-my-zsh/custom}/plugins/$plugin"
        done
    sed -i.bak 's|^plugins=.*|plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)|' "$HOME"/.zshrc
    format_font "✅  Zsh Plugins are installed."
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
        if ! command -v brew &> /dev/null
            then
            format_font "#️⃣  Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        local_dir="$HOME/Library/Fonts/"
        download_fonts "$local_dir"
        format_font "#️⃣  Installing Powerlevel10k..."
        brew install powerlevel10k
        echo "source $(brew --prefix)/share/powerlevel10k/powerlevel10k.zsh-theme" >>~/.zshrc
        format_font "✅  Powerlevel10k is installed."
        ;;
    Linux)
        if ! command -v curl &> /dev/null
        then
            format_font "#️⃣  Installing curl..."
            sudo apt install curl
            format_font "✅  curl is installed."
        fi
        local_dir="/usr/share/fonts/truetype/MesloLGS-NF/"
        download_fonts $local_dir
        format_font "#️⃣  Updating Font Cache..."
        cd && fc-cache -fv
        format_font "#️⃣  Installing Powerlevel10k...."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
        format_font "✅  Powerlevel10k is installed."
        format_font "#️⃣  Changing default shell to Zsh. Your password is required."
        chsh -s /usr/bin/zsh
        ;;
    *)
        format_font "❌  Unsupported OS. Quitting."
        exit 1
        ;;
esac

update_zshrc
install_zsh_plugins

format_font "✅  Done. Please restart your terminal." "bold" "blue"
