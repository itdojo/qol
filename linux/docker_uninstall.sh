#!/bin/bash

uninstall_docker() {
    if ! command -v apt > /dev/null; then
        printf "❌  Cannot uninstall Docker. apt package manager not found.\n" >&2
        return 1
    fi

    if command -v docker > /dev/null; then
        printf "%s\n" "⚠️  You are about to completely remove Docker and all associated data. $(fstring "There is no undo." "normal" "bold" "red")" >&2
        read -p "Do you really want to completely remove Docker? [y/n/q]: " confirm

        case "$confirm" in
            [Yy])
                printf "%s\n" "Removing Docker in 5 seconds. Press CTRL-C to cancel..."
                sleep 5
                printf "%s\n" "Stopping all running Docker containers..."
                docker stop "$(docker ps -aq)" 2>/dev/null                      # Stop all running containers
                printf "%s\n" "Removing all Docker containers..."
                docker rm "$(docker ps -aq)" 2>/dev/null                        # Remove all Docker containers
                printf "%s\n" "Removing all Docker images..."
                docker rmi "$(docker images -q)" 2>/dev/null                    # Remove all Docker images
                printf "%s\n" "Removing all Docker volumes..."
                docker volume rm "$(docker volume ls -q)" 2>/dev/null           # Remove all Docker volumes
                printf "%s\n" "Removing all Docker networks..."
                docker network rm "$(docker network ls -q)" 2>/dev/null         # Remove all Docker networks
                printf "%s\n" "Removing all Docker plugins..."
                docker plugin rm "$(docker plugin ls -q)" 2>/dev/null           # Remove all Docker plugins
                printf "%s\n" "Note: This does not remove Docker Swarm services, nodes, or secrets."
                printf "%s\n" "Uninstalling Docker..."
                apt purge -y docker-engine docker docker.io docker-ce docker-ce-cli containerd.io
                apt autoremove -y --purge
                rm -rf /var/lib/docker
                rm -rf /etc/docker
                rm -rf /var/run/docker.sock
                rm -rf /usr/local/bin/docker-compose
                rm -rf /var/lib/containerd
                ;;
            [Nn])
                printf "%s\n" "Docker uninstall cancelled. Continuing ${0} execution..."
                sleep 2
                return 0
                ;;
            [Qq])
                printf "%s\n" "Terminating the script..." >&2
                if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
                    if [[ -n "$ZSH_VERSION" ]]; then
                        kill -s TERM "$$"
                    else
                        kill -s TERM $$
                    fi
                else
                    exit 1
                fi
                ;;
            *)
                printf "Invalid input. Exiting...\n" >&2
                return 2
                ;;
        esac

        printf "Docker has been completely removed.\n"
    else
        printf "Docker is not installed.\n"
    fi
}

# Check if base_functions.sh is being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # The script is being run directly
    if ! source ./base_functions.sh 2>/dev/null; then
        printf "Error: base_functions.sh not found or contains errors.\n" >&2
        exit 1
    fi

    as_root
    uninstall_docker
    exit $?
fi
