#!/bin/zsh

# This script adds all the tweaks to the shell file. It is meant to be run
# after a fresh install of the OS. It will add the following lines to the
# shell file:

# Create a temporary file
tempfile=$(mktemp)
version=1

# Add lines to the temporary file. These will be added to 
# the shell file if they don't already exist.

cat << EOF > "$tempfile"
# CMW shell tweaks - version $version

### SHORTCUTS ############################################

cat <<'TheEnd'

Shortcuts:
🐍 pyvenv - python3 venv

TheEnd

### FUNCTION SECTION ######################################

mkvenv() {
    if [[ ! -n "$1" ]]; then
        dir=$(mktemp -d /tmp/python3-XXXX)
    else
        dir="$1"
    fi

    if [[ ! -d "$dir" ]]; then
        cd $HOME
        mkdir -p "$dir"
    fi

    cd "$dir" || return
    python3 -m venv venv
    if [ $? -ne 0 ]; then
        echo "Failed to create virtual environment."
        return
    fi
}

runvenv() {
    mkvenv "$@"
    source venv/bin/activate
}

### ALIAS SECTION ##########################################
alias pyvenv="mkvenv "$1"; runvenv"

clear
### END OF TWEAKS ##########################################
EOF
# End of tweaks


# ##########################################################
# #### NOTHING BELOW THIS LINE IS WRITTEN TO SHELL FILE ####
# ##########################################################

# Determine the shell file
if [ $SHELL = "/bin/zsh" ] || [ $SHELL = "/usr/bin/zsh" ]; then
    shellfile="$HOME/.zshrc"
elif [ $SHELL = "/bin/bash" ]; then
    shellfile="$HOME/.bashrc"
else
    echo "Shell "$SHELL" not supported"
    exit 1
fi

# Make a backup of the shell file
backup="$shellfile.cmw.bak"

# Make a backup of the current shellfile
cp "$shellfile" "$backup"

string_to_find="# CMW shell tweaks"

if grep -q "$string_to_find" "$shellfile"; then
    sed -i '/# CMW shell tweaks/,/# End of tweaks/d' "$shellfile"
fi

# Add the tweaks to the shell file
cat "$tempfile" > "$shellfile"
cat "$backup" >> "$shellfile"

# Clean up the temporary file
rm "$tempfile"
