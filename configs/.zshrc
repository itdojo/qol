# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
#                                                                                    CUSTOM EXPORTS
# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export PATH="$HOME/bin:$PATH"
# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
#                                                                                       CONFIG: FZF
# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
#!/usr/bin/env zsh
# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
# fzf + zoxide + previews — portable across macOS (Homebrew) and Ubuntu (apt)
#
# Drop this at ~/.config/zsh/fzf.zsh and add to ~/.zshrc:
#     [[ -r ~/.config/zsh/fzf.zsh ]] && source ~/.config/zsh/fzf.zsh
#
# Everything degrades gracefully: missing tools are substituted, never fatal.
# Ubuntu package notes: bat -> `batcat`, fd-find -> `fdfind`, eza is 24.04+.
# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼

autoload -Uz is-at-least

_have() { command -v "$1" >/dev/null 2>&1 }

# Cache expensive `<tool> init` output; regenerate only when the binary changes.
#   _cache_eval <cache-name> <binary> <command...>
_cache_eval() {
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/$1.zsh"
  if [[ ! -s $cache || $commands[$2] -nt $cache ]]; then
    mkdir -p "${cache:h}"
    shift 2
    "$@" >| "$cache" 2>/dev/null
  fi
  [[ -s $cache ]] && source "$cache"
}

# ── zoxide ─────────────────────────────────────────────────────────────────
_have zoxide && _cache_eval zoxide zoxide zoxide init zsh

# ── pick the best available preview tools ──────────────────────────────────
if   _have eza;  then _FZF_TREE='eza --tree --level=3 --color=always'
elif _have exa;  then _FZF_TREE='exa --tree --level=3 --color=always'
elif _have tree; then _FZF_TREE='tree -C -L 3'
else                  _FZF_TREE='ls -1'
fi

# Ubuntu ships bat as `batcat` (name clash with an existing package)
if   _have bat;    then _FZF_CAT='bat'
elif _have batcat; then _FZF_CAT='batcat'
fi
if [[ -n $_FZF_CAT ]]; then
  _FZF_CAT="$_FZF_CAT --style=numbers --color=always --line-range :500"
else
  _FZF_CAT='head -n 500'
fi

# Single source of truth for the file-or-dir preview.
# fzf already shell-quotes {}, so it must stay unquoted here.
_FZF_PREVIEW="if [ -d {} ]; then ${_FZF_TREE} {} | head -n 200; elif [ -f {} ]; then ${_FZF_CAT} {}; fi"

# ── fzf ────────────────────────────────────────────────────────────────────
if _have fzf; then
  _fzf_ver="${$(fzf --version)%% *}"

  # fzf-preview.sh only exists if you cloned the fzf repo; fall back cleanly.
  if _have fzf-preview.sh; then _fzf_p='fzf-preview.sh {}'; else _fzf_p=$_FZF_PREVIEW; fi

  if is-at-least 0.54 "$_fzf_ver"; then
    export FZF_DEFAULT_OPTS="--style full --preview '$_fzf_p' --bind 'focus:transform-header:file --brief {} 2>/dev/null'"
  else
    # Ubuntu 22.04 ships 0.29, 24.04 ships 0.44 — no --style, no transform-header
    export FZF_DEFAULT_OPTS="--border --preview '$_fzf_p'"
  fi

  export FZF_CTRL_T_OPTS="--preview '$_FZF_PREVIEW'"
  export FZF_ALT_C_OPTS="--preview '${_FZF_TREE} {} | head -n 200'"

  # Ctrl-R selects history lines, not paths. Without these it inherits the
  # file preview from FZF_DEFAULT_OPTS and bat chokes on every entry
  # ("[bat error]: ... No such file or directory"). Preview the command text
  # instead, and blank the file-based header binding.
  export FZF_CTRL_R_OPTS="--preview 'echo {}' --preview-window up:3:wrap:hidden
    --bind 'ctrl-/:toggle-preview'
    --bind 'focus:transform-header:echo'
    --header 'ctrl-/ preview · ctrl-y copy'"
  _have pbcopy && FZF_CTRL_R_OPTS+=" --bind 'ctrl-y:execute-silent(echo -n {2..} | pbcopy)+abort'"

  # Key bindings + completion
  if is-at-least 0.48 "$_fzf_ver"; then
    _cache_eval fzf fzf fzf --zsh
  else
    for _fzf_f in \
      /usr/share/doc/fzf/examples/{key-bindings,completion}.zsh \
      /usr/share/fzf/{key-bindings,completion}.zsh \
      /opt/homebrew/opt/fzf/shell/{key-bindings,completion}.zsh \
      /usr/local/opt/fzf/shell/{key-bindings,completion}.zsh
    do
      [[ -r $_fzf_f ]] && source "$_fzf_f"
    done
    unset _fzf_f
  fi
  unset _fzf_ver _fzf_p
fi

# ── completion sources (fd is much faster than the default find walker) ────
if   _have fd;     then _FZF_FIND=fd
elif _have fdfind; then _FZF_FIND=fdfind   # Ubuntu package name
fi

if [[ -n $_FZF_FIND ]]; then
  _fzf_compgen_path() { $_FZF_FIND --hidden --follow --exclude .git . "$1" }
  _fzf_compgen_dir()  { $_FZF_FIND --type d --hidden --follow --exclude .git . "$1" }
fi

# ── per-command previews ───────────────────────────────────────────────────
_fzf_comprun() {
  local command=$1
  shift

  case "$command" in
    cd)
      fzf --preview "${_FZF_TREE} {} | head -n 200" "$@"
      ;;
    export|unset)
      fzf --preview "eval 'echo \${}'" "$@"
      ;;
    ssh)
      if command -v dig >/dev/null 2>&1; then
        fzf --preview 'dig {}' "$@"
      else
        fzf "$@"
      fi
      ;;
    *)
      fzf --preview "$_FZF_PREVIEW" "$@"
      ;;
  esac
}

unset _FZF_CAT
unfunction _have _cache_eval

# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
#                                                                       📂 FUNCTION: DIRECTORY MARK
# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
here() {  # Mark the current directory.
    export HERE_MARK_DIR="$PWD"
    printf 'Directory marked: %s\n' "$HERE_MARK_DIR"
}

back() {  # Return to the marked directory.
    if [ -z "${HERE_MARK_DIR:-}" ]; then
        printf 'No directory marked.\n' >&2
        return 1
    fi

    if [ ! -d "$HERE_MARK_DIR" ]; then
        printf 'Marked directory no longer exists: %s\n' "$HERE_MARK_DIR" >&2
        return 1
    fi

    cd -- "$HERE_MARK_DIR"
}

# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
#                                                                   ⌨️ FUNCTION: CREATE & CD TO DIR
# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
mkcd() {
    if [ $# -eq 0 ]; then
        echo "Usage: mkcd <directory>" >&2
        return 1
    fi

    mkdir -p -- "$1" && cd -- "$1"
}

# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
#                                                                         🛜 FUNCTION: SET SS ALIAS
# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
# On MacOS, `brew install somo`
somo_check() {
    if [[ "$(uname)" == "Darwin" ]] && command -v somo >/dev/null 2>&1; then
    alias ss='somo -c --no-pager'
    fi
}

somo_check

# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
#                                                                              🤫 PRIVATE VARIABLES
# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
# Secrets live in ~/.config/secrets.zsh (mode 600), never in this file.
[[ -r "$XDG_CONFIG_HOME/secrets.zsh" ]] && source "$XDG_CONFIG_HOME/secrets.zsh"

# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
#                                                                          🌅 ENVIRONMENT VARIABLES
# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
# Do not put secrets in this file. Use ~/.config/secrets.zsh (mode 600) instead.
export PATH="$HOME/.local/bin:$PATH"
export PAGER='less'
export GITHUB_KEY=~/.ssh/github                # Path to your GitHub SSH key
export BAT_THEME="Catppuccin Mocha"            # Bat theme
export EZA_CONFIG_DIR=$XDG_CONFIG_HOME/eza     # Eza config dir
# export CAVEMAN_DEFAULT_MODE=lite             # Claude CaveMan mode: lite, full, or none
                                               # See https://github.com/juliusbrussee/caveman
if [[ -n $SSH_CONNECTION ]]; then
    export EDITOR='vim'
    export VISUAL='vim'
else
    export EDITOR='vim'                        # 'nano' if you are an insane person
    export VISUAL='vim'                        # Set to 'code' for VS Code.
fi

# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
#                                                                                 🛜 NETWORK STATUS
# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
# Sourcing only defines functions; netstatus_boot decides whether to print.
# Inside tmux it prints in the first shell of a session, then stays quiet.
if [[ -r "$HOME/projects/qol/netstatus.sh" ]]; then
    source "$HOME/projects/qol/netstatus.sh"
    netstatus_boot
fi

# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
#                                                                              ▶️ ALIASES: COMMANDS
# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
alias c=clear
alias lsz="eza -l --group-directories-last --icons=always --group --mounts --git"
alias ls="lsz"
alias less="bat"
alias python=python3
alias p=python3
alias z='cp ~/.zshrc ~/.zshrc.bak && ${EDITOR:-vim} ~/.zshrc'
alias zshrc="z"
alias sz="source ~/.zshrc"
alias cat="bat --style=plain"
alias bat="bat --style=full"
alias tmuxconfig='${EDITOR:-vim} $XDG_CONFIG_HOME/tmux/tmux.conf'
alias ghosttyconfig='${EDITOR:-vim} $XDG_CONFIG_HOME/ghostty/config.ghostty'
alias vimconfig='${EDITOR:-vim} $HOME/.vimrc'
alias claude="claude --chrome"   # https://code.claude.com/docs/en/chrome
alias dcl="docker container ls"
alias dcdu="docker compose down && docker compose up -d"

# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
#                                                                                  🪟 ALIASES: TMUX
# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
alias tks="tmux kill-server"         # Kill all tmux sessions
alias tkserver="tmux kill-server"    # Kill all tmux sessions
alias tksess="tmux kill-session"     # Kill current tmux session
alias tksession="tmux kill-session"  # Kill current tmux session
alias tkp="tmux kill-pane"           # Kill tmux pane
alias tkw="tmux kill-window"         # Kill tmux window
alias td="tmux detach"               # Detach from tmux session
alias ta="tmux attach"               # Attach to tmux session
alias tn="tmux new"                  # New tmux session (default name)
alias tns="tmux new -s"              # New tmux session named <session_name>

# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
#                                                                           📂 ALIASES: DIRECTORIES
# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
# Add your own aliases here. For example:
# alias f1="cd path/to/folder"
# alias f2="cd path/to/another/folder"
# add each alias to your 'hints' array below so that it shows up in the hints menu.

# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
#                                                                                     🫆 HINTS MENU
# ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
# fzf trainer hints
echo " ⌃R - 🗿 command history        (ctrl+r)"
echo " ⌃T - 📌 paste to CLI           (ctrl+t)"
echo " ⌥C - 📂 cd to folder           (alt+c)"
echo " cmd **<tab> - 📌 paste to CLI"
# end fzf trainer hints
echo "'hint' ► shortcut reminders"
function hint() {
    command cat << 'EOF'
⎼⎼ 📍 SHORTCUTS ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
•  z                 → edit .zshrc
•  sz                → source .zshrc
•  c                 → clear screen
•  p                 → python3
•  mkcd path/to/dir  → create & cd to path/to/dir
•  here / back       → mark dir / return to marked dir
•  netstatus [-f]    → wi-fi + internet status (-f = fresh check)
•  vimconfig         → edit vim config file
•  tmuxconfig        → edit tmux config file
•  ghosttyconfig     → edit ghostty config file
•  ⌃ R               → command history (fzf) (ctrl+r)
•  ⌃ T               → paste to CLI (fzf) (ctrl+t)
•  ⌥ C               → cd to folder (fzf) (alt+c)
•  <cmd> **<tab>     → paste to CLI after <cmd> (fzf)
•  ⌃ ⌘ ␠             → MacOS emoji menu (ctrl+cmd+space)

⎼⎼ ⚙️ TMUX ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
•  tks               → kill server
•  tksess            → kill session
•  tkp               → kill pane
•  tkw               → kill window
•  td                → detach session
•  ta                → attach session
•  tn                → new session
•  tns <name>        → new session <name>

⎼⎼ 📂 DIRECTORIES ⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
•  <slug1>           → 📚 <folder1>
•  <slug2>           → 📒 <folder2>
⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼⎼
EOF
}
