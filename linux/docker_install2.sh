#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

DOCKER_GPG_URL="https://download.docker.com/linux/ubuntu/gpg"
DOCKER_REPO_URL="https://download.docker.com/linux/ubuntu"
BASE_FUNCTIONS_URL="https://raw.githubusercontent.com/itdojo/qol/refs/heads/main/linux/base_functions.sh"
DOCKER_LIST_PATH="/etc/apt/sources.list.d/docker.list"
DOCKER_KEYRING="/etc/apt/keyrings/docker.gpg"

main() {
    validate_base_functions
    check_existing_docker
    initialize_environment
    install_prerequisites
    detect_platform
    install_docker
    add_users_to_docker_group
    finalize_installation
}

validate_base_functions() {
    local script_dir; script_dir=$(dirname "$(realpath "$0")")
    if [[ ! -f "${script_dir}/base_functions.sh" ]]; then
        printf "❌  base_functions.sh not found. Downloading from GitHub.\n" >&2
        if ! wget -q -O "${script_dir}/base_functions.sh" "$BASE_FUNCTIONS_URL"; then
            printf "❌  Failed to download base_functions.sh\n" >&2
            exit 1
        fi
    fi
    # shellcheck disable=SC1090
    source "${script_dir}/base_functions.sh"
}

check_existing_docker() {
    if command -v docker >/dev/null; then
        printf "Docker is already installed (%s).\n" "$(docker --version)"
        read -rp "Do you want to continue with the installation? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            printf "Exiting...\n"
            exit 0
        fi
        read -rp "Do you want to uninstall existing Docker install first? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            source "$(dirname "$(realpath "$0")")/docker_uninstall.sh"
            uninstall_docker
        fi
    fi
}

initialize_environment() {
    clear
    as_root
    check_if_linux
    trap handle_ctrl_c SIGINT
    fstring "🐳  DOCKER INSTALLER FOR LINUX" "title"
    printline dentistry
}

install_prerequisites() {
    if ! command -v curl >/dev/null; then
        printf "Installing curl...\n"
        apt update && apt install -y curl
    fi
    if ! command -v needrestart >/dev/null; then
        printf "Installing needrestart...\n"
        apt update && apt install -y needrestart
    fi
}

detect_platform() {
    fstring "Gathering Linux Release Info... " "section"
    local model; model=$(grep -m1 'Raspberry' /proc/cpuinfo | cut -d: -f2 | xargs)
    if [[ -n "$model" ]]; then
        printf "🥧 I am a %s.\n" "$(fstring "Raspberry Pi" "normal" "bold" "red")"
    fi

    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        printf "OS Version: %s (%s)\n" "$PRETTY_NAME" "$VERSION_CODENAME"
    fi

    PLATFORM_MODEL="$model"
    PLATFORM_CODENAME="$VERSION_CODENAME"
    PLATFORM_NAME="$PRETTY_NAME"
}

install_docker() {
    if [[ -n "$PLATFORM_MODEL" ]]; then
        install_docker_raspberry_pi
    elif [[ "$PLATFORM_CODENAME" == "kali-rolling" ]]; then
        install_docker_kali
    else
        install_docker_generic
    fi
}

install_docker_raspberry_pi() {
    fstring "Installing Docker for Raspberry Pi... " "section"
    if ! curl -sSL https://get.docker.com | sh; then
        printf "❌ Failed to install Docker for Raspberry Pi\n" >&2
        exit 1
    fi
}

install_docker_kali() {
    fstring "Installing Docker for Kali... " "section"
    printf '%s\n' "deb https://download.docker.com/linux/debian bullseye stable" | tee "$DOCKER_LIST_PATH"
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker-ce-archive-keyring.gpg
    update_repo
    install_packages docker-ce docker-ce-cli containerd.io
    systemctl enable docker --now
    printf "🐳 Docker Service Status: %s\n" "$(systemctl is-active docker)"
}

install_docker_generic() {
    fstring "Installing Docker for $PLATFORM_NAME... " "section"
    install_packages ca-certificates gnupg apt-transport-https lsb-release software-properties-common

    fstring "🔑  Adding Docker's GPG key... " "section"
    mkdir -p /etc/apt/keyrings
    rm -f "$DOCKER_KEYRING"
    curl -fsSL "$DOCKER_GPG_URL" | gpg --dearmor -o "$DOCKER_KEYRING"
    chmod a+r "$DOCKER_KEYRING"

    fstring "Adding Docker repository to apt sources... " "section"
    local arch; arch=$(dpkg --print-architecture)
    echo "deb [arch=$arch signed-by=$DOCKER_KEYRING] $DOCKER_REPO_URL $PLATFORM_CODENAME stable" | tee "$DOCKER_LIST_PATH" >/dev/null

    update_repo
    install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

add_users_to_docker_group() {
    fstring "Adding $USER to docker group... " "section"
    usermod -aG docker "$USER" || printf "❌ Failed to add %s to docker group\n" "$USER" >&2

    if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "$USER" ]]; then
        fstring "Adding $SUDO_USER to docker group... " "section"
        usermod -aG docker "$SUDO_USER" || printf "❌ Failed to add %s to docker group\n" "$SUDO_USER" >&2
    fi

    fstring "Membership changes will take effect at next login." "section"
}

finalize_installation() {
    fstring "🐳  DOCKER INSTALLER COMPLETE" "title"
    printline dentistry
    printf "\n"
}

main "$@"
