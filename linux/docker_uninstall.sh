#!/bin/bash

uninstall_docker() {
    if ! command -v apt > /dev/null; then
        printf "❌  Cannot uninstall Docker. apt package manager not found.\n" >&2
        return 1
    fi

    if command -v docker > /dev/null; then
        printf "%s\n" "⚠️  You are about to completely remove Docker and all associated data. $(fstring "There is no undo." "normal" "bold" "red")\n" >&2
        read -p "Do you really want to completely remove Docker? [y/n/q]: " confirm

        case "$confirm" in
            [Yy])
                printf "Removing Docker in 5 seconds. Press CTRL-C to cancel...\n"
                sleep 5
                printf "Stopping all running Docker containers...\n"
                docker stop "$(docker ps -aq)" 2>/dev/null    # Stop all running containers
                printf "Removing all Docker containers...\n"
                docker rm "$(docker ps -aq)" 2>/dev/null      # Remove all Docker containers
                printf "Removing all Docker images...\n"
                docker rmi "$(docker images -q)" 2>/dev/null  # Remove all Docker images
                printf "Removing all Docker volumes...\n"
                docker volume rm "$(docker volume ls -q)" 2>/dev/null  # Remove all Docker volumes
                printf "Removing all Docker networks...\n"
                docker network rm "$(docker network ls -q)" 2>/dev/null  # Remove all Docker networks
                printf "Removing all Docker plugins...\n"
                docker plugin rm "$(docker plugin ls -q)" 2>/dev/null  # Remove all Docker plugins
                printf "Note: This does not remove Docker Swarm services, nodes, or secrets.\n"
                printf "Uninstalling Docker...\n"
                apt purge -y docker-engine docker docker.io docker-ce docker-ce-cli
                apt autoremove -y --purge
                ;;
            [Nn])
                printf "%s\n" "Docker removal cancelled. Continuing ${0} execution..."
                sleep 3
                return 0
                ;;
            [Qq])
                printf "Terminating the script...\n" >&2
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
else
    # The script is being sourced
    echo "uninstall_docker function is now available for use."
fi
