# qol (Quality of Life) Tools

A collection of shell scripts and helpers I use to set up and maintain my machines (Linux and macOS). Rather than having scripts scattered across different computers, this repo keeps them in one place so I can use them regularly and improve them over time. The scripts aim to work for most users on most systems, not just for me on mine.

How the repo is organized:

- **Repo root** — scripts that run on both macOS and Linux, plus files meant to be sourced from your shell config.
- **[linux/](linux/)** — Linux-only scripts, plus [`base_functions.sh`](linux/base_functions.sh), the shared helper library most of them use.
- **[macos/](macos/)** — macOS-only scripts.

## Tool List

| Tool | Intended OS | Description |
|:--|:--|:--|
| [gotime](gotime) | macOS, Linux | Colorful arrow-key/number menu of courses (`~/courseware`) and projects (`~/projects`); on selection, spins up a tmux session named `gotime` with three windows — `dojobrain` (`~/vaults/dojobrain`, runs `claude`), the chosen course/project (runs `claude`), and `local` (a shell in `~`). Zero extra dependencies (bash + tmux + tput). `gotime <slug>` skips the menu; `gotime --list` shows what it sees. Wire it up with `alias gotime="$HOME/projects/qol/gotime"`. |
| [install_zsh.sh](install_zsh.sh) | macOS, Linux | Installs and configures zsh, Oh My Zsh, Powerlevel10k, MesloLGS Nerd Font, and the zsh-autosuggestions, zsh-syntax-highlighting, and zsh-completions plugins. Supports apt, dnf, pacman, apk, zypper, and Homebrew. Idempotent. |
| [shell-login-settings.sh](shell-login-settings.sh) | macOS, Linux | Personal login-shell helpers, meant to be sourced from `.bashrc`/`.zshrc`. Currently provides `gitssh`, which authenticates to GitHub over SSH and reuses a running ssh-agent when possible. |
| [tool_checks.sh](tool_checks.sh) | macOS, Linux (Debian) | Sourceable `check_for_tool` function: verifies a CLI tool is installed and installs it if missing (Homebrew on macOS, apt on Debian/Ubuntu). |
| [custom-zshrc-entries.txt](custom-zshrc-entries.txt) | macOS, Linux | My custom `.zshrc` additions: environment variables, aliases (tmux, networking, apt), and a `hint` function that prints a shortcuts reminder. |
| [linux/base_functions.sh](linux/base_functions.sh) | Linux | Shared helper library sourced by the other Linux scripts. Provides the repo-standard output theme (`log_*` helpers, `printline`, `style_text`), root checks, apt helpers, OS detection, and a CTRL-C trap. Not meant to be run directly. |
| [linux/docker_install.sh](linux/docker_install.sh) | Linux (Debian/Ubuntu family) | Installs Docker from Docker's official apt repo and adds the current user to the `docker` group. Handles Ubuntu, Debian, Kali, Mint, Pop!\_OS, and Raspberry Pi OS; removes conflicting distro packages first and verifies with `hello-world`. |
| [linux/docker_uninstall.sh](linux/docker_uninstall.sh) | Linux (Debian/Ubuntu family) | Completely removes Docker: containers, images, volumes, networks, packages, and data/config directories. Prompts for confirmation — there is no undo. Can also be sourced (`docker_install.sh` uses it). |
| [linux/internet_check.sh](linux/internet_check.sh) | Linux | Quick connectivity check: pings a well-known IP (no DNS) and resolves a well-known hostname, then prints a compact status line (`✅ Internet   ✅ DNS`). Designed to be sourced from `.bashrc`/`.zshrc`; see [linux/README.md](linux/README.md). |
| [linux/kernel_update.sh](linux/kernel_update.sh) | Linux | Updates the kernel to the latest available version using the right strategy per distro: the mainline PPA on Ubuntu and derivatives, apt full-upgrade on Debian, dist-upgrade on Kali, and apt full-upgrade (with optional, opt-in `rpi-update`) on Raspberry Pi OS. |
| [linux/nm-connection-maker.sh](linux/nm-connection-maker.sh) | Linux | Interactively builds a NetworkManager `.nmconnection` profile (Wi-Fi or Ethernet, DHCP or static IP), writes it to `/etc/NetworkManager/system-connections`, reloads NetworkManager, and optionally brings the connection up. Validates input and never writes the plaintext Wi-Fi passphrase to the profile. |
| [linux/wifi_check.sh](linux/wifi_check.sh) | Linux | Prints the SSID the device is currently associated with (or a "not connected" message), trying `nmcli`, then `iw`, then `iwgetid`. Designed to be sourced from `.bashrc`/`.zshrc`; see [linux/README.md](linux/README.md). |
| [linux/wireshark_install.sh](linux/wireshark_install.sh) | Linux (Debian/Ubuntu family) | Installs Wireshark and TShark — from the wireshark-dev/stable PPA on Ubuntu, or distro repos elsewhere. Non-interactive (preseeds the packet-capture debconf question) and adds the invoking user to the `wireshark` group. |
| [macos/install-nerd-fonts.sh](macos/install-nerd-fonts.sh) | macOS | Installs a configurable list of Nerd Fonts via Homebrew casks. Idempotent: already-installed fonts are skipped, and one failed font doesn't abort the rest. |
