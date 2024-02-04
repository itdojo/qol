# qol (Quality of Life) Tools

This is a collection of tools I find useful.  Unless otherwise stated, I wrote them.  Generally, this means they are not as efficient as they could or should be.  They may lack some error checking and they may not be the most elegant solution for accomplishing the task.  But, as I figure out better ways to do things, I will update the code.  I am trying to write code that will work for most users on most computers (MacOS and/or Linux), not just code that works for me on mine. 

Rather than having scripts spread all over the place on different computers, this is my effort to better organize my tools so that I can A) make use of them more regularly and B) imporve upon them as I learn to write better code.

How this repo is organized:

**[fresh-install](fresh-install/zsh_install.sh)** - Scripts in this folder are useful when I am doing a fresh install of Linux or MacOS.  The folder has Linux and MacOS subfolders for any scripts that are system-specific.  If the script is written to run on either OS, it will be in the root folder.

## Tool List

| Tool | Location | Intended OS | Description |
|:--|:--|:--|:--|
| **[kernel_update.sh](fresh-install/linux/kernel_update.sh)** | [fresh-install/linux](fresh-install/linux/) | Linux | Updates Linux to the latest mainline kernel version. |
| **[macos_alias_installer.sh](fresh-install/macos/macos_alias_installer.sh)** | [fresh-install/macos](fresh-install/macos/) | MacOS | A collection of alias entries I find useful for MacOS commands I never seem to remember the syntax for.
| **[install_zsh.sh](fresh-install/install_zsh.sh)** | [fresh-install/](fresh-install/) | MacOS or Linux (Debian) |  Installs (if needed) and configures: Homebrew, zsh, oh-my-zsh, NerdFonts, the MesloLGS NF font family, powerlevel10k ZSH theme and and zsh extensions (zsh-autosuggestions zsh-syntax-highlighting zsh-completions).




