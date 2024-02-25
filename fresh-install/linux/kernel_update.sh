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

# Determine if this is a Raspberry Pi 🥧
model=$(grep Raspberry /proc/cpuinfo | cut -d: -f2)
if [ -n "$model" ]; then
    printf "%s\n" "🥧 I am a $(fstring "Raspberry Pi" "normal" "bold" "red")."
    install_packages ntpdate ca-certificates
    ntpdate -u ntp.ubuntu.com
    rpi-update
    check_status "Checking Result of Raspberry Pi Kernel Update" $?
    fstring "Reboot to load any changes." "warning"
else
    # We are not a Raspberry Pi.  Proceed normally.
    # Installing mainline
    fstring "Adding Kernel Update Repo" "section"
    apt -y --fix-broken install
    if ! command -v add-apt-repository &> /dev/null; then
        fstring "Adding add-apt-repository utility..."
        install_packages software-properties-common
        check_status "Checking Result of add-apt-repository installation" $?
    fi
    add-apt-repository -y ppa:cappelikan/ppa
    check_status "Checking Addition of Kernel Update Repo" $?

    # Installing mainline
    fstring "Installing mainline utility..." "section"
    update_repo
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
fi


# Print the completion message
fstring "🏁  KERNEL UPGRADE COMPLETE  🏁" "title"
printline dentistry
echo ""
