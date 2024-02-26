#!/bin/bash

uninstall_docker() {
    if ! command -v apt > /dev/null; then
        echo "❌  Cannot uninstall Docker. apt package manager not found."
        exit 1  # Terminate the script
    fi
    if command -v docker > /dev/null; then
        fstring "Docker is already installed." "warning"
        echo "⚠️  This script will remove Docker and $(fstring "all containers and images" "normal" "bold" "red")."
        echo "You $(fstring "cannot" "normal" "normal" "normal" "underline") undo this action."
        read -p "Do you really want to completely remote Docker? [y/n/q]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Docker removal cancelled."
            echo ""
            return 0 
        elif [[ "$confirm" =~ ^[Qq]$ ]]; then
            echo "Exiting..."
            return 1  # Terminate the script
        else
            echo "Stopping all running Docker containers..."
            docker stop "$(docker ps -aq)" 2>/dev/null    # Stop all running containers
            echo "Removing all Docker containers..."
            docker rm "$(docker ps -aq)" 2>/dev/null      # Remove all Docker containers
            echo "Removing all Docker images..."
            docker rmi "$(docker images -q)" 2>/dev/null  # Remove all Docker images
            echo "Removing all Docker volumes..."
            docker volume rm "$(docker volume ls -q)" 2>/dev/null  # Remove all Docker volumes
            echo "Removing all Docker networks..."
            docker network rm "$(docker network ls -q)" 2>/dev/null  # Remove all Docker networks
            echo "Removing all Docker plugins..."
            docker plugin rm "$(docker plugin ls -q)" 2>/dev/null  # Remove all Docker plugins
            echo "Note: This does not remove Docker Swarm services, nodes, or secrets."
            echo "Uninstalling Docker..."
            sudo apt purge -y docker-engine docker docker.io docker-ce docker-ce-cli
            if command -v docker-desktop > /dev/null; then
                # Uninstall Docker Desktop
                echo "Uninstalling Docker Desktop..."
                sudo apt purge -y docker-desktop
                sudo apt autoremove -y --purge docker-desktop
            fi
            if command -v docker-compose > /dev/null; then
                # Uninstall Docker Compose
                echo "Uninstalling Docker Compose..."
                sudo apt purge -y docker-compose
                sudo apt autoremove -y --purge docker-compose
            fi
            sudo apt autoremove -y --purge docker-engine docker docker.io docker-ce  
            sudo rm -rf /var/lib/docker /var/lib/containerd      # Remove Docker storage directories
            sudo rm -rf /etc/docker                              # Remove Docker config files
            sudo rm -rf ~/.docker                                # Remove Docker user directory
            if getent group docker > /dev/null; then
                sudo groupdel docker                             # Remove Docker group
            fi
            sudo rm -rf /var/run/docker.sock                     # Remove Docker socket
            echo "Docker has been uninstalled."
        fi
    fi
    echo ""
    echo "Docker is not installed."
    echo ""
}

source ./base_functions.sh
