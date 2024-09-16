#!/usr/bin/env bash

# This script checks the current SSID of the WiFi network
# to which the device is currently associated. If the device
# is not associated with a WiFi network, it will return "No WiFi Association".

set -e

# Function to check if the script is running on Linux
check_os() {
	printf "Debug: Checking OS...\n"
	if [[ "$(uname)" != "Linux" ]]; then
		echo "This script only runs on Linux."
		exit 1
	fi
	printf "Debug: OS is Linux.\n"
}

# Function to check for required commands
check_commands() {
	printf "Debug: Checking required commands...\n"
	for cmd in iwgetid iw nmcli; do
		if command -v $cmd &> /dev/null; then
			printf "Debug: $cmd is installed\n"
			return 0
		fi
	done
	echo "Neither iw, iwgetid, nor nmcli are installed. Cannot determine WiFi status."
	exit 1
}

# Function to get the current SSID
get_ssid() {
	printf "Debug: Getting SSID...\n"
	local ssid=""
	if command -v iw &> /dev/null; then
		ssid=$(iw dev | grep ssid | sed s/'ssid'// | awk '{gsub(/\t/,""); print $0}')
		printf "Debug: iw SSID: $ssid\n"
	elif command -v nmcli &> /dev/null; then
		ssid=$(nmcli -t -f active,ssid dev wifi | grep -E '^yes' | cut -d: -f2)
		printf "Debug: nmcli SSID: $ssid\n"
	elif command -v iwgetid &> /dev/null; then
		ssid=$(iwgetid --raw)
		printf "Debug: iwgetid SSID: $ssid\n"
	else
		echo "No suitable command found to determine WiFi status."
		exit 1
	fi

	# Debug statement to check the value of ssid
	printf "Debug: SSID value is '$ssid'\n"

	if [[ -n "$ssid" ]]; then
		echo "Current SSID: $ssid"
	else
		echo "No WiFi Association"
	fi
}

# Main script execution
main() {
	printf "Debug: Starting main function...\n"
	check_os
	check_commands
	get_ssid
	printf "Debug: Finished main function.\n"
}

main
