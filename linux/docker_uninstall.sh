#!/usr/bin/env bash
#
# docker_uninstall.sh
# Remove apt-installed Docker Engine, its data, and its apt repository.
# This deletes containers, images, volumes, and custom daemon configuration.
# Rootless user services/data and Docker Desktop are outside this script's scope.
# Usage: sudo bash docker_uninstall.sh
# May also be sourced and called as uninstall_docker.
# Returns 0 for removed/kept/absent, 1 for an error, 130 for quit or EOF.
# DOCKER_UNINSTALL_RESULT records removed, kept, or absent for a sourcing caller.

uninstall_docker() {
    DOCKER_UNINSTALL_RESULT=""
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        log_err "Run as root. Usage: sudo bash docker_uninstall.sh"
        return 1
    fi
    if ! command -v apt-get >/dev/null 2>&1 ||
       ! command -v dpkg-query >/dev/null 2>&1 ||
       ! command -v systemctl >/dev/null 2>&1; then
        log_err "apt-get, dpkg-query, and systemctl are required to remove this Docker installation."
        return 1
    fi

    local packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin
                    docker-compose-plugin docker-ce-rootless-extras docker.io
                    docker-compose docker-compose-v2 docker-buildx podman-docker)
    local installed=() package choice
    for package in "${packages[@]}"; do
        [[ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)" == 'install ok installed' ]] &&
            installed+=("$package")
    done
    if (("${#installed[@]}" == 0)) &&
       [[ ! -e /var/lib/docker &&
          ! -e /etc/docker && ! -e /etc/apt/sources.list.d/docker.sources &&
          ! -e /etc/apt/sources.list.d/docker.list ]]; then
        log_info "No apt-installed Docker packages or Docker data found."
        DOCKER_UNINSTALL_RESULT=absent
        return 0
    fi

    log_warn "This removes Docker packages, containers, images, volumes, /var/lib/containerd, and local configuration. There is no undo."
    # A three-way answer lets a sourcing installer distinguish keep from quit.
    while true; do
        log_ask "Remove Docker and all local Docker data?"
        printf '    %s❯%s %s[y = remove / n = keep / q = quit]%s ' \
            "$QOL_PASS" "$QOL_RESET" "$QOL_META" "$QOL_RESET" >&2
        if ! read -r choice; then
            log_warn "No confirmation received. Docker was kept."
            return 130
        fi
        case "$choice" in
            [Yy]) break ;;
            [Nn]) log_info "Docker was kept."; DOCKER_UNINSTALL_RESULT=kept; return 0 ;;
            [Qq]) log_info "Quit without removing Docker."; return 130 ;;
            *) log_warn "Enter y, n, or q." ;;
        esac
    done

    log_phase "SERVICES"
    log_step "Stopping Docker services..."
    systemctl disable --now docker.socket docker.service containerd.service 2>/dev/null || true
    systemctl stop docker.socket docker.service containerd.service 2>/dev/null || true
    if systemctl is-active --quiet docker.socket ||
       systemctl is-active --quiet docker.service ||
       systemctl is-active --quiet containerd.service; then
        log_err "Docker or containerd is still running. Stop it before removing data."
        return 1
    fi
    log_ok "Docker services are stopped."

    log_phase "PACKAGES"
    if (("${#installed[@]}")); then
        log_step "Purging Docker packages..."
        if ! DEBIAN_FRONTEND=noninteractive apt-get purge -y "${installed[@]}"; then
            log_err "Docker package purge failed. Resolve apt errors before deleting Docker data."
            return 1
        fi
        log_ok "Docker packages are purged."
    else
        log_ok "No Docker packages are installed."
    fi

    log_phase "DATA AND REPOSITORY"
    log_step "Removing Docker data, configuration, and apt source..."
    if ! rm -rf /var/lib/docker /var/lib/containerd /etc/docker ||
       ! rm -f /etc/apt/sources.list.d/docker.sources /etc/apt/sources.list.d/docker.list ||
       ! rm -f /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg; then
        log_err "Docker data or repository cleanup failed. Check permissions and retry."
        return 1
    fi
    # Older versions of docker_install.sh wrote this file. Leave other module
    # configuration alone.
    if [[ -f /etc/modules-load.d/docker.conf ]] &&
       grep -q '^# Loaded by docker_install.sh' /etc/modules-load.d/docker.conf; then
        if ! rm -f /etc/modules-load.d/docker.conf; then
            log_err "Could not remove the legacy Docker modules file."
            return 1
        fi
    fi
    log_ok "Docker data and repository are removed."
    DOCKER_UNINSTALL_RESULT=removed
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=linux/base_functions.sh
    if ! source "$SCRIPT_DIR/base_functions.sh" 2>/dev/null; then
        printf '%s\n' "▌ STOP   base_functions.sh is missing. Get it from https://github.com/itdojo/qol." >&2
        exit 1
    fi
    check_if_linux
    as_root
    banner "DOCKER UNINSTALLER" "packages · data · repository"
    rc=0
    uninstall_docker || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        case "$DOCKER_UNINSTALL_RESULT" in
            removed) log_complete "DOCKER REMOVED"; log_next "Reinstall with: sudo bash docker_install.sh" ;;
            kept) log_complete "DOCKER KEPT" ;;
            absent) log_complete "NO DOCKER INSTALLATION FOUND" ;;
        esac
    fi
    echo
    exit "$rc"
fi
