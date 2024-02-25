#!/bin/bash

# Update kernel to latest version
# Usage: sudo ./kernel_update.sh

# Load the base functions
. base_functions.sh        # Source the base functions
clear                      # Clear the screen
as_root                    # Check for root, exit if not
trap handle_ctrl_c SIGINT  # Handle CTRL-C
kernel_start=$(uname -r)   # Get the current kernel version

fstring "KERNEL UPDATER FOR LINUX" "title"
printline dentistry

# Installing mainline
fstring "Adding Kernel Update Repo" "section"
apt -y --fix-broken install
add-apt-repository -y ppa:cappelikan/ppa
check_status "Checking Addition of Kernel Update Repo" $?

# Installing mainline
fstring "Installing mainline utility..." "section"
install_packages mainline
check_status "Checking Result mainline installation" $?

# Installing latest kernel
fstring "Installing Latest Kernel..." "section"
mainline install-latest
check_status "Checking Result of Kernel Installation" $?
apt -y --fix-broken install

kernel_end=$(uname -r)  # Get the new kernel version

if [ "$kernel_start" != "$kernel_end" ]; then
    echo ""
    fstring "Kernel has been updated." "normal" "normal" "green"
    fstring "$kernel_start ---> $kernel_end."
    echo ""
    fstring "Reboot to load the new $kernel_end kernel." "normal" "normal" "bold" "red"
    echo ""
else
    echo ""
    fstring "Kernel is already up to date ($kernel_end).  No need to reboot."
    echo ""
fi

# Print the completion message
fstring "🏁  KERNEL UPGRADE COMPLETE  🏁" "title"
printline dentistry
echo ""
