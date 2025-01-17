# Fresh Install Tools

The tools in this folder are ones that I find useful when rebuilding a new system.  I install linux ***a lot*** and configuring it the way I like it becomes tedious.  The scrpits that I put here are meant to help with I am setting up a new Linux machine or a new MacOS install (which is way less often).

## Tool List

| Tool | Location | Intended OS | Description |
|:--|:--|:--|:--|
| **[add_all_login_tweaks.sh](add_all_login_tweaks.sh)** | root folder | MacOS or Linux (Debian) | Adds useful shortuct funnctions and alias' to your shell profile (**.zshrc** or **.bashrc**).  Also adds reminder text when you login.
| **[install_zsh.sh](fresh-install/install_zsh.sh)** | [fresh-install](install_zsh.sh) | MacOS or Linux (Debian) |  Installs (if needed) and configures: Homebrew, zsh, oh-my-zsh, NerdFonts, the MesloLGS NF font family, powerlevel10k ZSH theme and and zsh extensions (zsh-autosuggestions zsh-syntax-highlighting zsh-completions).
| **[kernel_update.sh](linux/kernel_update.sh)** | [fresh-install/linux](linux/) | Linux | Updates Linux to the latest mainline kernel version. |
| **[macos_alias_installer.sh](macos/macos_alias_installer.sh)** | [macos](fresh-install/macos/) | MacOS | A collection of alias entries I find useful for MacOS commands I never seem to remember the syntax for.
