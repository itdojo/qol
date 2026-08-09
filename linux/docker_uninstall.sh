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
# Expects the IT Dojo terminal theme helpers (log_*, log_phase) to be loaded;
# when run directly it sources linux/base_functions.sh itself.
#
# The run bookends live in the run-directly branch at the bottom, not in
# uninstall_docker: when docker_install.sh sources this file and calls the
# function mid-run, that run already has a banner and owns its own ending.
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒

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

    # Not ask_confirm: this is a three-way question (remove / keep / quit) and
    # the 130 return is what tells a sourcing caller to abort. Borrow the shape
    # of ask_confirm's prompt — ASK badge, then a jade caret — without its
    # two-way semantics.
    local confirm=""
    while true; do
        log_ask "Completely remove Docker?"
        printf '    %s❯%s %s[y = remove / n = keep / q = quit]%s ' \
            "$QOL_PASS" "$QOL_RESET" "$QOL_META" "$QOL_RESET"
        read -r confirm
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
            *) log_warn "Invalid input: '$confirm' (expected y, n, or q)." ;;
        esac
    done

    log_step "Removing Docker in 5 seconds. Press CTRL-C to cancel..."
    sleep 5

    log_phase "CONTAINERS AND IMAGES"
    log_step "Stopping and removing all containers, images, volumes, networks, and plugins..."
    docker ps -aq        | xargs -r docker stop          2>/dev/null
    docker ps -aq        | xargs -r docker rm -f         2>/dev/null
    docker images -q     | xargs -r docker rmi -f        2>/dev/null
    docker volume ls -q  | xargs -r docker volume rm -f  2>/dev/null
    # Built-in networks (bridge/host/none) refuse removal; that's expected.
    docker network ls -q | xargs -r docker network rm    2>/dev/null
    docker plugin ls -q  | xargs -r docker plugin rm -f  2>/dev/null
    log_info "Note: this does not remove Docker Swarm services, nodes, or secrets."

    # Stop and disable the services BEFORE purging packages and deleting data.
    # Tearing /var/lib/docker out from under a live daemon (overlay2 mounts,
    # busy files) is how you leave the machine in a half-broken state.
    log_phase "SERVICES"
    log_step "Stopping Docker services..."
    systemctl disable --now docker.socket docker.service containerd.service 2>/dev/null || true
    systemctl stop docker.socket docker.service containerd.service 2>/dev/null || true

    # Only purge packages that are actually installed — passing a name apt has
    # never heard of (e.g. docker-engine on modern releases) aborts the whole
    # apt-get purge command.
    local pkgs=(docker-engine docker docker.io docker-ce docker-ce-cli
                docker-ce-rootless-extras docker-buildx-plugin
                docker-compose-plugin containerd.io podman-docker)
    log_phase "PACKAGES"
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

    log_phase "DATA AND CONFIG"
    log_step "Removing Docker data, configuration, and apt repository..."
    rm -rf /var/lib/docker /var/lib/containerd /etc/docker
    rm -rf /var/run/docker /var/run/docker.sock
    rm -f  /usr/local/bin/docker-compose
    rm -f  /etc/apt/sources.list.d/docker.list \
           /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg

    log_ok "Docker has been completely removed."
    return 0
}

# When executed directly (not sourced), load the helpers and run. This branch
# owns the run bookends; a sourcing caller does not reach it.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    # shellcheck source=base_functions.sh
    if ! source "${SCRIPT_DIR}/base_functions.sh" 2>/dev/null; then
        # log_err is not available yet — this is the failure to load it. Hand-write
        # the same 9-column prefix log_err emits at QOL_DEPTH=none.
        printf '%s\n' "▌ STOP   base_functions.sh not found next to this script." \
                      "▌ STOP   Get it from https://github.com/itdojo/qol." >&2
        exit 1
    fi
    banner "DOCKER UNINSTALLER" "containers · images · volumes · packages"
    as_root
    uninstall_docker
    rc=$?
    if [ "$rc" -eq 0 ]; then
        log_complete "DOCKER UNINSTALLER COMPLETE"
        log_next "Reinstall with:  ./docker_install.sh"
        echo
    fi
    exit "$rc"
fi
