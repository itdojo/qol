#!/bin/bash

# Update kernel to latest version
# Usage: sudo ./kernel_update.sh

# Load the base functions
source base_functions.sh

clear # Clear the screen

as_root  # Check for root

trap handle_ctrl_c SIGINT  # Handle CTRL-C

kernel_start=$(uname -r)

printline dentistry
format_font "CHECKING FOR/INSTALLING UPDATED KERNEL" "bold" "blue"
printline dentistry

# Installing mainline
section_title="Adding Kernel Repository..."
format_font "#️⃣   $section_title" $TITLE_WEIGHT $TITLE_COLOR
apt -y --fix-broken install
add-apt-repository -y ppa:cappelikan/ppa
check_status "Checking Result for $section_title"


# Installing mainline
printline solid
section_title="Installing mainline..."
format_font "#️⃣   $section_title" $TITLE_WEIGHT $TITLE_COLOR
install_packages mainline
check_status "Checking Result for $section_title"


# Installing latest kernel
printline solid
section_title="Installing Latest Kernel..."
format_font "#️⃣   $section_title" $TITLE_WEIGHT $TITLE_COLOR
mainline install-latest
check_status "Checking Result for $section_title"
apt -y --fix-broken install

kernel_end=$(uname -r)
if [ "$kernel_start" != "$kernel_end" ]; then
    format_font "Kernel has been updated from $kernel_start to $kernel_end" "bold" "green"
    format_font "Reboot to load new kernel" "bold" "red"
else
    format_font "Kernel is already up to date" "bold" "green"
    echo "No need to reboot."
fi

printline dentistry
format_font "KERNEL UPGRADE COMPLETE" "bold" "blue"
printline dentistry
echo ""

