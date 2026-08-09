# Why `install_zsh.sh` is deprecated in favor of Starship

**Status:** `install_zsh.sh` (zsh + Oh My Zsh + Powerlevel10k) has been deprecated since 2026-07-27. It still works and is still published, because people already depend on it. New installs should use [`install_zsh_starship.sh`](install_zsh_starship.sh). Long term, `install_zsh.sh` is removed, or the Starship script takes over the old name.

Both scripts install the same *shell*: zsh, MesloLGS Nerd Font (+ Symbols Only), and the zsh-autosuggestions / zsh-syntax-highlighting / zsh-completions plugins, across the same package-manager matrix (apt, dnf, pacman, apk, zypper, Homebrew) and the same architectures. The disagreement is only about what sits on top of zsh: a framework plus a zsh-native theme, or a standalone prompt binary and nothing else.

## The reasons

### 1. Powerlevel10k's upstream is in maintenance mode

The Powerlevel10k README leads with, verbatim:

> THE PROJECT HAS VERY LIMITED SUPPORT
> NO NEW FEATURES ARE IN THE WORKS
> MOST BUGS WILL GO UNFIXED
> HELP REQUESTS WILL BE IGNORED

That is the single decisive fact. A setup script's job is to leave a machine in a state that keeps working for years without attention, and `install_powerlevel10k()` performs a `git clone` from that repo — and a `git pull --ff-only` on every rerun — of a codebase whose maintainer has said in advance that breakage will not be fixed. This is not a knock on Oh My Zsh, which remains actively maintained; it is that the theme was the reason to run the framework in the first place.

### 2. Starship's prompt config is reproducible; Powerlevel10k's is not

`install_zsh.sh` cannot finish the job. It installs the theme and then tells you `p10k configure` — an interactive wizard that asks a few dozen questions and emits a `~/.p10k.zsh` of well over a thousand lines that lives on that one machine and is in no repo. Two machines set up from the same script do not get the same prompt unless you answer identically both times, and a rebuilt machine does not get its old prompt back.

`install_zsh_starship.sh` writes `~/.config/starship.toml` itself, from a config held in the script (`write_starship_config()`, the "grove" powerline prompt, ported from the Powerlevel10k lean frame and reusing its 256-color indices so the swap is visually continuous). No wizard, no per-machine answer file, no post-install step. Every machine the script touches gets a byte-identical prompt, and changing the house prompt is a commit to this repo rather than a re-run of a wizard on each box.

### 3. One managed block beats line surgery on `~/.zshrc`

`update_zshrc()` in `install_zsh.sh` edits the user's `.zshrc` in place, in several unrelated spots: it `sed`s any existing `ZSH_THEME=` line to point at Powerlevel10k, replaces the `plugins=(...)` block, inserts an `fpath+=` line above `source $ZSH/oh-my-zsh.sh`, appends `setopt AUTO_CD`, and runs a `cleanup_legacy_zshrc()` pass to strip stale lines earlier versions of the script left behind. Every one of those edits depends on the shape of a file the user also edits. Idempotence is a property of the patterns matching, and the existence of a legacy-cleanup function is the evidence that they sometimes did not.

The Starship script writes exactly one delimited region — `# >>> qol starship block >>>` to `# <<< qol starship block <<<` — and every rerun deletes that region and writes it again whole. Nothing outside the markers is touched, reruns cannot duplicate config by construction rather than by careful matching, and the result is validated with `zsh -n` and rolled back to the timestamped backup if it fails to parse. Paths inside the block are written as a literal `$HOME` so the same `.zshrc` is portable between a macOS `/Users/x` and a Linux `/home/x`.

### 4. A binary with a package manager beats a git clone in a framework directory

Starship installs as a single static binary — `brew install starship` on macOS, the vendor installer elsewhere — so upgrades are the machine's ordinary package upgrade. Powerlevel10k installs as a git working tree under `$ZSH_CUSTOM/themes/`, kept current by a `git pull` the script runs on every invocation and whose failure it can only warn about and continue past (`log_warn "p10k pull failed; continuing."`). One of those is a dependency; the other is a checkout you now own.

### 5. Dropping the framework removes a layer without losing its features

Oh My Zsh's real value was never the theme loader; it was the defaults it set quietly. So the Starship script does not simply delete them — it writes them explicitly and visibly, which is the point. Plugins become plain `git clone`s under `~/.zsh/plugins`, the same layout on macOS and Linux, no plugin manager and no root. The managed block then re-provides, in about forty readable lines, what Oh My Zsh had been supplying invisibly:

| Was provided by | Now provided by |
|:--|:--|
| Oh My Zsh history defaults | `HISTFILE`/`HISTSIZE`/`SAVEHIST` plus seven explicit `setopt`s in the managed block |
| Oh My Zsh completion styling | `compinit` (skipped when your own config already runs it) and four `zstyle` lines |
| Oh My Zsh `fzf` plugin | `source <(fzf --zsh)`, with pre-0.48 fallbacks, skipped entirely if something earlier in `.zshrc` already bound the widgets |
| Oh My Zsh `git` plugin aliases | `~/.config/zsh/git-aliases.zsh`, written by the script |
| `ZSH_THEME="powerlevel10k/powerlevel10k"` | `eval "$(starship init zsh)"` |

The result is a `.zshrc` whose behavior you can read, in one place, instead of inheriting it from a framework you would have to go read the source of.

### 6. The prompt outlives the shell choice

Powerlevel10k is zsh-only. Starship renders the same prompt from bash, fish, and nushell, which matters on the machines in this repo's blast radius where the login shell is not zsh, and on any machine where that changes later. The prompt config stops being a zsh artifact.

## What this is *not* about: speed

Powerlevel10k is faster, and it is worth being precise about that rather than pretending otherwise. Its instant prompt paints a usable prompt before `.zshrc` has finished loading, and `gitstatusd` keeps a persistent daemon so git status in a large repository costs nothing on redraw. Starship forks a process per prompt and has no instant-prompt equivalent. On a huge monorepo over a slow filesystem you will notice.

That cost was accepted deliberately. Perceived latency on a fast local repo is small, Starship's `command_timeout` bounds the worst case, and a prompt that is reproducible from a file in this repo and maintained upstream is worth more than a few milliseconds. If prompt latency in a specific repo is the dominant problem on some machine, that is a legitimate reason to stay on `install_zsh.sh` there — it is why the script is deprecated rather than deleted.

## Migrating

```bash
./install_zsh_starship.sh
```

The script detects an existing Oh My Zsh or Powerlevel10k install and runs [`uninstall_omz_p10k.sh`](uninstall_omz_p10k.sh) first, after a confirmation prompt. That uninstaller removes the `~/.oh-my-zsh` tree, `~/.p10k.zsh`, the p10k caches, and on macOS the `powerlevel10k` formula and `font-meslo-for-powerlevel10k` cask. It strips their lines out of `~/.zshrc` surgically rather than restoring `.zshrc.pre-oh-my-zsh`, so anything you added since installing Oh My Zsh survives; the file is backed up first and rolled back if the result fails `zsh -n`. It supports `--dry-run` and `--yes`, so a dry run is the cheap way to see the removal before it happens.

The two stacks are not meant to coexist. Pick one.

## Consequences for this repo

`install_zsh_starship.sh` is now the living reference implementation for the house shell-script style — when [`script-design.md`](script-design.md) and that script disagree, one of them is wrong and the fix goes into one of them, never into a third way. `install_zsh.sh` still carries the branded theme block and still passes `tests/test-theme-sync.sh`, so it does not rot silently, but it receives no new features. Bugs in it are fixed only where the fix is cheap and does not require touching the Oh My Zsh or Powerlevel10k halves.
