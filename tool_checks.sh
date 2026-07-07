#!/bin/bash
# shellcheck shell=bash
#
# tool_checks.sh
#
# Sourceable checks that make sure common CLI tools are installed, using the
# repo-standard theme from linux/base_functions.sh.
#
# Usage (from another script):
#     source /path/to/tool_checks.sh
#     check_for_tool git
#     check_for_tool fc-cache fontconfig     # command name != package name
#
# On macOS, tools are installed with Homebrew. On Debian/Ubuntu-family Linux,
# they are installed with apt via install_packages (requires root).

# Resolve this file's directory even when sourced from another location.
TOOL_CHECKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"

# shellcheck source=linux/base_functions.sh
if ! source "${TOOL_CHECKS_DIR}/linux/base_functions.sh" 2>/dev/null; then
    printf '%s\n' "❌  Could not source linux/base_functions.sh (expected at ${TOOL_CHECKS_DIR}/linux/base_functions.sh)." >&2
    return 1 2>/dev/null || exit 1
fi

# Ensure a tool is installed; install it if missing (idempotent).
# Usage: check_for_tool <command> [package-name]
check_for_tool() {
    local tool="$1" pkg="${2:-$1}"
    if command -v "$tool" >/dev/null 2>&1; then
        log_ok "$tool is already installed."
        return 0
    fi
    log_step "Installing $tool..."
    if [ "$(uname -s)" = "Darwin" ]; then
        if ! command -v brew >/dev/null 2>&1; then
            log_err "Homebrew is required to install $tool on macOS (https://brew.sh)."
            return 1
        fi
        brew install "$pkg"
    else
        install_packages "$pkg"
    fi
    if command -v "$tool" >/dev/null 2>&1; then
        log_ok "$tool is installed."
    else
        log_err "Failed to install $tool."
        return 1
    fi
}

# Backwards-compatible named wrappers.
check_for_wget() { check_for_tool wget; }
check_for_zsh()  { check_for_tool zsh;  }
check_for_git()  { check_for_tool git;  }
check_for_curl() { check_for_tool curl; }
