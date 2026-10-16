#!/usr/bin/env bash
#
# docker_install.sh
# Install Docker Engine, Buildx, and Compose from Docker's official apt repo.
# Targets: supported Ubuntu and Debian releases and compatible derivatives.
# Usage: sudo bash docker_install.sh
# Rerunning upgrades packages without deleting Docker data.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_FUNCTIONS="$SCRIPT_DIR/base_functions.sh"
BASE_FUNCTIONS_URL="https://raw.githubusercontent.com/itdojo/qol/refs/heads/main/linux/base_functions.sh"
DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
CONFLICTING_PACKAGES=(docker.io docker-doc docker-compose docker-compose-v2 docker-buildx podman-docker containerd runc)
REPO_FAMILY="" REPO_SUITE="" REPO_ARCH=""

if [[ ! -f "$BASE_FUNCTIONS" ]]; then
    printf '%s\n' "▌ STEP   Downloading base_functions.sh..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$BASE_FUNCTIONS_URL" -o "$BASE_FUNCTIONS" || {
            printf '%s\n' "▌ STOP   Could not download base_functions.sh. Get it from https://github.com/itdojo/qol." >&2
            exit 1
        }
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$BASE_FUNCTIONS_URL" -O "$BASE_FUNCTIONS" || {
            printf '%s\n' "▌ STOP   Could not download base_functions.sh. Get it from https://github.com/itdojo/qol." >&2
            exit 1
        }
    else
        printf '%s\n' "▌ STOP   Install curl or wget, then rerun this script." >&2
        exit 1
    fi
fi
# shellcheck source=linux/base_functions.sh
source "$BASE_FUNCTIONS"
command -v log_phase >/dev/null 2>&1 || {
    printf '%s\n' "▌ STOP   base_functions.sh is outdated. Update it from https://github.com/itdojo/qol." >&2
    exit 1
}
install_error() {
    local rc=$?
    log_err "Docker installation failed at line ${BASH_LINENO[0]} (exit $rc). Fix the command error above and rerun."
    exit "$rc"
}
trap install_error ERR
set -E

fail() { log_err "$1"; exit 1; }
package_installed() {
    [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null || true)" == 'install ok installed' ]]
}

select_repository() {
    REPO_ARCH="$(dpkg --print-architecture)"
    case "$OS_ID" in
        ubuntu)
            REPO_FAMILY=ubuntu
            REPO_SUITE="${OS_UBUNTU_CODENAME:-$OS_CODENAME}"
            ;;
        debian|kali|raspbian)
            REPO_FAMILY=debian
            REPO_SUITE="$OS_CODENAME"
            if [[ "$OS_ID" == kali ]]; then REPO_SUITE=trixie; fi
            ;;
        *)
            if [[ "${OS_ID_LIKE:-}" == *ubuntu* || -n "$OS_UBUNTU_CODENAME" ]]; then
                REPO_FAMILY=ubuntu
                REPO_SUITE="${OS_UBUNTU_CODENAME:-$OS_CODENAME}"
            elif [[ "${OS_ID_LIKE:-}" == *debian* ]]; then
                REPO_FAMILY=debian
                REPO_SUITE="$OS_CODENAME"
            else
                fail "Unsupported distribution: $OS_PRETTY_NAME. Use Docker's installation guide."
            fi
            ;;
    esac
    case "$REPO_FAMILY:$REPO_SUITE" in
        ubuntu:jammy|ubuntu:noble|ubuntu:resolute|ubuntu:stonking|debian:bookworm|debian:trixie) ;;
        *) fail "No supported Docker apt suite for $OS_PRETTY_NAME ($REPO_SUITE). Check Docker's install guide before changing packages." ;;
    esac
    case "$REPO_FAMILY:$REPO_ARCH" in
        ubuntu:amd64|ubuntu:armhf|ubuntu:arm64|ubuntu:ppc64el|ubuntu:s390x|debian:amd64|debian:armhf|debian:arm64|debian:ppc64el) ;;
        *) fail "Docker does not publish $REPO_FAMILY packages for $REPO_ARCH. Check Docker's supported architectures." ;;
    esac
    if [[ "$OS_ID" == raspbian && "$REPO_ARCH" == armhf ]]; then
        # Debian armhf packages target ARMv7, not Pi 1/Zero ARMv6.
        case "$(uname -m)" in
            armv7l|armv8l) ;;
            *) fail "Debian armhf Docker packages need ARMv7 or newer. This Pi appears to be ARMv6." ;;
        esac
    fi
    log_info "Using Docker's $REPO_FAMILY repository: $REPO_SUITE ($REPO_ARCH)."
}

remove_conflicting_packages() {
    local p installed=()
    for p in "${CONFLICTING_PACKAGES[@]}"; do
        package_installed "$p" && installed+=("$p")
    done
    if (("${#installed[@]}")); then
        log_step "Removing conflicting distribution packages..."
        DEBIAN_FRONTEND=noninteractive apt-get remove -y "${installed[@]}"
        log_ok "Conflicting packages are removed."
    else
        log_ok "No conflicting packages are installed."
    fi
}

configure_repository() {
    log_phase "REPOSITORY"
    log_step "Installing apt prerequisites..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl
    log_ok "Apt prerequisites are installed."
    log_step "Adding Docker's signing key and apt source..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$REPO_FAMILY/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    rm -f /etc/apt/sources.list.d/docker.list
    cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/$REPO_FAMILY
Suites: $REPO_SUITE
Components: stable
Architectures: $REPO_ARCH
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    apt-get update
    log_ok "Docker's apt repository is ready."
}

install_docker() {
    log_phase "DOCKER ENGINE"
    log_step "Installing Docker Engine, Buildx, and Compose..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${DOCKER_PACKAGES[@]}"
    log_ok "Docker Engine, Buildx, and Compose are installed."
    log_phase "SERVICE"
    log_step "Starting Docker..."
    systemctl enable --now docker.service || true
    if ! systemctl is-active --quiet docker.service; then
        journalctl -u docker.service --no-pager -n 25 >&2 || true
        fail "Docker did not start. Check systemctl status docker.service and the daemon log above."
    fi
    log_ok "Docker service is active."
}

offer_group_access() {
    local user="${SUDO_USER:-}"
    [[ -n "$user" && "$user" != root ]] || return 0
    id "$user" >/dev/null 2>&1 || return 0
    if id -nG "$user" | grep -qw docker; then
        log_ok "$user already belongs to the docker group."
        return 0
    fi
    log_warn "The docker group grants root-level access to this host."
    # This privilege grant requires a live answer even if ASSUME_YES is set.
    if ASSUME_YES='' ask_confirm "Add $user to the docker group?" N; then
        groupadd -f docker
        usermod -aG docker "$user"
        log_ok "$user is in the docker group."
        log_next "Log out and back in before running docker without sudo."
    else
        log_info "Keeping $user out of the docker group. Use sudo docker for now."
    fi
}

main() {
    check_if_linux
    as_root
    banner "DOCKER INSTALLER" "engine · compose · buildx"
    log_phase "PREFLIGHT"
    command -v apt-get >/dev/null 2>&1 || fail "apt-get is required. Use Docker's guide for this distribution."
    command -v dpkg-query >/dev/null 2>&1 || fail "dpkg-query is required for package checks."
    command -v systemctl >/dev/null 2>&1 || fail "This installer requires systemd. Use Docker's manual instructions on this host."
    [[ -n "$OS_ID" ]] || fail "Cannot read /etc/os-release."
    select_repository
    log_warn "Published container ports can bypass ufw/firewalld rules; review Docker's firewall guidance."
    configure_repository
    remove_conflicting_packages
    install_docker
    log_phase "VERIFY"
    log_step "Running the hello-world container..."
    if docker run --rm hello-world; then
        log_ok "The hello-world container ran successfully."
    else
        log_warn "Docker is running, but hello-world failed. Check image downloads, networking, and journalctl -u docker.service."
    fi
    offer_group_access
    log_complete "DOCKER INSTALLER COMPLETE"
    log_next "Check the installed version with: docker version"
    echo
}

main "$@"
