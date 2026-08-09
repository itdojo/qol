# Configure tmux-agent-sidebar with tmux and coding agents

`tmux-agent-sidebar` provides one tmux sidebar for monitoring Claude Code, Codex, and OpenCode panes across tmux sessions and windows. Installing the tmux plugin creates the sidebar, but each coding agent also needs its own event bridge before the sidebar can display live status.

**The most important setup rule is to use this machine's actual TPM installation path everywhere.** Upstream examples use `~/.tmux/plugins`; an XDG-based tmux installation uses `~/.config/tmux/plugins`. Copying an upstream OpenCode command without adjusting that path creates a broken symlink: the sidebar opens and other agents may appear, but OpenCode stays invisible.

This repository's [`configs/tmux.conf`](../configs/tmux.conf) is XDG. Its TPM launcher is the last line of the file:

```tmux
run '~/.config/tmux/plugins/tpm/tpm'
```

So on any machine using this repo's tmux config, the TPM plugin root is `~/.config/tmux/plugins`. Every command below assumes that. Substitute `~/.tmux/plugins` only if you are working on a machine with a traditional tmux layout.

## 1. Check the prerequisites

Confirm tmux 3.0 or newer:

```sh
tmux -V
```

Installation uses TPM, the tmux plugin manager, which this repo's config already bootstraps. GitHub CLI is optional and only needed to show pull-request numbers in the sidebar's Git tab. Rust is only needed to build `tmux-agent-sidebar` from source instead of downloading its prebuilt binary.

## 2. Confirm the TPM path on this machine

Do not assume. If a tmux server is running, ask it:

```sh
tmux show-environment -g TMUX_PLUGIN_MANAGER_PATH
```

Otherwise read the bottom of the active config. The directory containing `tpm/` is the TPM plugin root.

| Layout | tmux configuration | TPM plugin root |
|---|---|---|
| XDG (this repo) | `~/.config/tmux/tmux.conf` | `~/.config/tmux/plugins` |
| Traditional | `~/.tmux.conf` | `~/.tmux/plugins` |

## 3. Register the tmux plugin

Add this alongside the other `@plugin` declarations in [`configs/tmux.conf`](../configs/tmux.conf):

```tmux
set -g @plugin 'hiroppy/tmux-agent-sidebar'
```

Keep the TPM launcher last, after every `set -g @plugin` line.

Reload the config that is actually in use:

```sh
tmux source-file ~/.config/tmux/tmux.conf
```

Press `prefix + I` to install. The first run offers a prebuilt binary or a source build; the prebuilt binary avoids needing a Rust toolchain.

Verify TPM created the checkout and installed an executable:

```sh
test -d ~/.config/tmux/plugins/tmux-agent-sidebar
test -x ~/.config/tmux/plugins/tmux-agent-sidebar/bin/tmux-agent-sidebar
~/.config/tmux/plugins/tmux-agent-sidebar/bin/tmux-agent-sidebar --version
```

## 4. Open the sidebar

| Binding | Action |
|---|---|
| `prefix + e` | Toggle the sidebar in the current window |
| `prefix + E` | Toggle the sidebar in every window |

Opening the sidebar proves the tmux plugin and binary run. **It does not prove any agent bridge is installed.** Complete the relevant agent section below before expecting live entries.

## 5. Connect Claude Code

The repository doubles as a Claude Code plugin. Run these as two separate commands inside Claude Code:

```text
/plugin marketplace add ~/.config/tmux/plugins/tmux-agent-sidebar
/plugin install tmux-agent-sidebar@hiroppy
```

Activate the hooks without leaving Claude Code:

```text
/reload-plugins
```

Restarting Claude Code also activates it. Open the sidebar and submit a prompt; the Claude pane should appear and move between running and waiting states.

## 6. Connect Codex

Enable Codex hooks in `~/.codex/config.toml`:

```toml
[features]
codex_hooks = true
```

If a `[features]` table already exists, add only the `codex_hooks` line under it.

Then:

1. Open and focus a Codex pane inside tmux.
2. Press `prefix + e` to open the sidebar.
3. Click the yellow `ⓘ` badge shown when hooks are missing.
4. Click `[copy]` beside `codex` in the Notices popup.
5. Return to the Codex pane and paste the copied command.
6. Let Codex run `tmux-agent-sidebar setup codex` and merge the generated hooks into `~/.codex/hooks.json`.
7. Restart Codex so the `codex_hooks` flag takes effect.

Submit a prompt and confirm the Codex pane appears.

## 7. Connect OpenCode

OpenCode auto-discovers JavaScript and TypeScript plugins in `~/.config/opencode/plugins/`. The sidebar repository ships the bridge at `.opencode/plugins/tmux-agent-sidebar.js`. **Symlink that one file — do not link the whole directory.**

```sh
mkdir -p ~/.config/opencode/plugins
ln -sfn ~/.config/tmux/plugins/tmux-agent-sidebar/.opencode/plugins/tmux-agent-sidebar.js \
  ~/.config/opencode/plugins/tmux-agent-sidebar.js
```

Validate the link before restarting OpenCode:

```sh
readlink ~/.config/opencode/plugins/tmux-agent-sidebar.js
readlink -f ~/.config/opencode/plugins/tmux-agent-sidebar.js
test -e ~/.config/opencode/plugins/tmux-agent-sidebar.js
```

The first shows the configured target. The second must resolve to an existing file inside the real TPM checkout. The third must exit successfully. **A symlink can exist while failing the last two checks if its target path is wrong** — that is the failure this document exists to prevent.

Ask OpenCode to resolve its configuration:

```sh
opencode debug config
```

Expect an entry equivalent to:

```json
{
  "plugin": [
    "file:///home/USER/.config/opencode/plugins/tmux-agent-sidebar.js"
  ]
}
```

No explicit `plugin` entry is needed in `~/.config/opencode/opencode.json`; files under `~/.config/opencode/plugins/` are auto-discovered.

Quit every OpenCode process that should use the bridge and restart it inside tmux. **OpenCode loads plugins only at startup** and does not hot-reload a newly created or corrected symlink.

## 8. Verify tmux's agent metadata directly

The bridge records agent state in tmux pane options:

```sh
tmux list-panes -a -F '#{session_name}\t#{window_index}.#{pane_index}\t#{pane_id}\t#{pane_current_command}\t#{@pane_agent}\t#{@pane_status}\t#{@pane_session_id}'
```

A registered OpenCode pane looks like:

```text
session-name    5.2    %8    opencode    opencode    idle    ses_...
```

If `pane_current_command` is `opencode` but `@pane_agent`, `@pane_status`, and `@pane_session_id` are blank, tmux sees the process but the bridge has not sent a session event. Recheck the symlink, run `opencode debug config`, restart OpenCode.

For one pane in detail:

```sh
tmux show-options -p -t %8
```

Sidebar-owned options are `@pane_agent`, `@pane_cwd`, `@pane_session_id`, and `@pane_status`.

## 9. Troubleshoot common failures

### The sidebar opens, but OpenCode is absent

The tmux plugin is healthy and the OpenCode bridge did not load.

1. Run `readlink -f ~/.config/opencode/plugins/tmux-agent-sidebar.js`.
2. If it prints nothing, recreate the link using the actual TPM root.
3. Run `test -e ~/.config/opencode/plugins/tmux-agent-sidebar.js`.
4. Run `opencode debug config` and confirm the `file://` entry appears.
5. Fully restart OpenCode.

The failure diagnosed on 2026-08-07 was exactly this: a valid filename pointing into a nonexistent `~/.tmux/plugins`, while TPM had installed under `~/.config/tmux/plugins`.

### A similarly named file exists but OpenCode ignores it

The bridge must be named `tmux-agent-sidebar.js` and end in `.js`. A truncated artifact such as `tmux-agent-sidebar.j` is not a JavaScript plugin and does not repair a broken `.js` link.

### `command -v tmux-agent-sidebar` prints nothing

Not necessarily a failure. The repository's `hook.sh` wrapper can invoke the binary from the plugin checkout even when it is not on `PATH`. Check the checkout's binary directly:

```sh
~/.config/tmux/plugins/tmux-agent-sidebar/bin/tmux-agent-sidebar --version
```

### TPM installed the repository but no binary exists

Re-run the install wizard through TPM. To update an existing installation, press `prefix + U`, select `tmux-agent-sidebar`, and let the wizard download or rebuild.

### Configuration changes seem to have no effect

Reloading tmux and restarting an agent solve different problems:

- After editing `tmux.conf` — `tmux source-file ~/.config/tmux/tmux.conf`, or the configured reload binding (`prefix + r` in this repo's config).
- After changing Claude Code plugin registration — `/reload-plugins`, or restart Claude Code.
- After changing `~/.codex/config.toml` or Codex hooks — restart Codex.
- After creating or correcting the OpenCode symlink — restart OpenCode.

## 10. Operate the sidebar

Inside the sidebar: `j`/`k` or arrow keys to move, `Enter` to jump to the selected agent pane, `Tab` to cycle the status filter, `Shift+Tab` to switch between Activity and Git, `r` to filter by repository, `Esc` to return focus or close a popup.

The yellow `ⓘ` badge means missing hook or plugin setup. Treat it as an agent-integration warning, not a tmux-plugin installation failure.

## Sources

- [tmux-agent-sidebar repository](https://github.com/hiroppy/tmux-agent-sidebar)
- [Installation](https://hiroppy.github.io/tmux-agent-sidebar/getting-started/installation/)
- [Claude Code setup](https://hiroppy.github.io/tmux-agent-sidebar/getting-started/claude-code/)
- [Codex setup](https://hiroppy.github.io/tmux-agent-sidebar/getting-started/codex/)
- [OpenCode setup](https://hiroppy.github.io/tmux-agent-sidebar/getting-started/opencode/)
- [Keybindings](https://hiroppy.github.io/tmux-agent-sidebar/reference/keybindings/)

Verified locally on 2026-08-07 against tmux, OpenCode 1.18.15, and tmux-agent-sidebar 0.13.0.
