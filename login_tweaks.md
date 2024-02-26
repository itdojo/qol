# .zhsrc or .bashrc Additions

***

**==All of the additions in this file can be added by running== `add_all_login_tweaks.sh`.**

***


## Shortcut Reminders

I have added a lot of shortcuts to my **.bashrc** and **.zshrc** over the years.  And then promptly forgot about most of them.  To try and fix that, I add some reminder text for when I open a shell or connect via SSH.  An example of the reminder is below.  It adds a brief reminder of the shortcuts I have added so I see them each time I log in.

To add the reminder, add the following to your **.bashrc** or **.zshrc**.  Add others to the list as you create more shortcuts.

```
cat << EOF
Shortcuts:
🐍 pyvenv

EOF
```

***

## Quickly make python3 virtual environments

Add the following to your **.bashrc** or **.zshrc**.

```bash
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

alias pyvenv="mkvenv "$1"; runvenv"
```

### Usage

```bash
pyenv
# or
pyenv <foldername>
```

| Command | What it does | 
|:--|:--|
| `pyvenv` | Creates a temporary folder, switches to it and activates a python3 virtual environemt.  Does not launch python3; stays at a prompt so you can `pip install`.   
| `pyvenv <somedir>` | Creates a folder named `<somedir>` in $HOME activate a python3 virtul environment. Does not launch python3; stays at a prompt so you can `pip install`.

***