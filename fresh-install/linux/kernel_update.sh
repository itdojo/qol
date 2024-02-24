#!/bin/bash

# Update kernel to latest version
# Usage: sudo ./kernel_update.sh

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "❌ Run as root."
    exit
  fi
}

check_root

add-apt-repository -y ppa:cappelikan/ppa

apt update && apt install -y mainline

mainline install-latest
