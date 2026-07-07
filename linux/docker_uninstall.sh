#!/bin/bash
#
# docker_uninstall.sh
#
# Completely removes Docker: containers, images, volumes, networks, plugins,
# packages, and data/config directories. THERE IS NO UNDO.
#
# Usage:
#   sudo ./docker_uninstall.sh       # run directly
#   source docker_uninstall.sh       # from another script (docker_install.sh
#                                    # does this), then call: uninstall_docker
#
# Return codes from uninstall_docker:
#   0   = Docker removed, user kept Docker ('n'), or Docker not installed
#   1   = cannot uninstall (apt not available)
#   130 = user chose 'q' (the caller should abort)
#
# Expects the repo-standard output helpers (log_*, style_text) to be loaded;
# when run directly it sources linux/base_functions.sh itself.
# ----------------------------------------------------------------------------

uninstall_docker() {
    if ! command -v apt-get >/dev/null 2>&1; then
        log_err "Cannot uninstall Docker: apt package manager not found."
        return 1
    fi

    if ! command -v docker >/dev/null 2>&1; then
        log_info "Docker is not installed. Nothing to remove."
        return 0
    fi

    log_warn "You are about to completely remove Docker and ALL associated data (containers, images, volumes). There is no undo."

    local confirm=""
    while true; do
        read -r -p "Completely remove Docker? [y = remove / n = keep / q = quit]: " confirm
        case "$confirm" in
            [Yy]) break ;;
            [Nn])
                log_info "Docker uninstall cancelled. Keeping the existing installation."
                return 0
                ;;
            [Qq])
                log_warn "Quitting at user request."
                return 130
                ;;
            *) style_text "⚠️   Invalid input: '$confirm' (expected y, n, or q)." bold yellow ;;
        esac
    done

    log_step "Removing Docker in 5 seconds. Press CTRL-C to cancel..."
    sleep 5

    log_step "Stopping and removing all containers, images, volumes, networks, and plugins..."
    docker ps -aq        | xargs -r docker stop          2>/dev/null
    docker ps -aq        | xargs -r docker rm -f         2>/dev/null
    docker images -q     | xargs -r docker rmi -f        2>/dev/null
    docker volume ls -q  | xargs -r docker volume rm -f  2>/dev/null
    # Built-in networks (bridge/host/none) refuse removal; that's expected.
    docker network ls -q | xargs -r docker network rm    2>/dev/null
    docker plugin ls -q  | xargs -r docker plugin rm -f  2>/dev/null
    log_info "Note: this does not remove Docker Swarm services, nodes, or secrets."

    # Only purge packages that are actually installed — passing a name apt has
    # never heard of (e.g. docker-engine on modern releases) aborts the whole
    # apt-get purge command.
    local pkgs=(docker-engine docker docker.io docker-ce docker-ce-cli
                docker-ce-rootless-extras docker-buildx-plugin
                docker-compose-plugin containerd.io podman-docker)
    local installed=() p
    for p in "${pkgs[@]}"; do
        dpkg -s "$p" >/dev/null 2>&1 && installed+=("$p")
    done
    if [ "${#installed[@]}" -gt 0 ]; then
        log_step "Purging Docker packages: ${installed[*]}"
        DEBIAN_FRONTEND=noninteractive apt-get purge -y "${installed[@]}"
        check_status "Purging Docker packages" $?
        apt-get autoremove -y --purge
    else
        log_info "No Docker packages found to purge."
    fi

    log_step "Removing Docker data, configuration, and apt repository..."
    rm -rf /var/lib/docker /var/lib/containerd /etc/docker
    rm -rf /var/run/docker /var/run/docker.sock
    rm -f  /usr/local/bin/docker-compose
    rm -f  /etc/apt/sources.list.d/docker.list \
           /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg

    log_ok "Docker has been completely removed."
    return 0
}

# When executed directly (not sourced), load the helpers and run.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    # shellcheck source=base_functions.sh
    if ! source "${SCRIPT_DIR}/base_functions.sh" 2>/dev/null; then
        printf '%s\n' "❌  base_functions.sh not found next to this script. Get it from https://github.com/itdojo/qol." >&2
        exit 1
    fi
    as_root
    uninstall_docker
    exit $?
fi
