# qol script design

The house style for every shell script in this repo. `install_zsh_starship.sh` is the living reference — when this doc and that script disagree, fix one of them, never a third way. `install_nano.sh` is the reference for scripts that take flags. `linux/base_functions.sh` is the sourced library for Linux-only scripts.

Status notes (2026-07-27): `install_zsh.sh` was the original reference and is now deprecated — still published because people depend on it; long-term it will be removed or replaced by the starship script under the old name. Known drift: `install_zsh_starship.sh`'s section titles are not yet right-aligned — realign them the next time the script is touched.

Two goals: every script **reads** the same (section layout) and **runs** the same (what the user sees on STDOUT).

## File anatomy, in order

1. `#!/usr/bin/env bash`
2. **Header comment block** — see template below.
3. `set -eo pipefail`
4. **Globals** — all mutable state, up top: `OS`/`ARCH` detection, empty `PKG_MGR`/`SUDO`, paths, pinned versions, arrays. No naked globals mid-file.
5. **Pretty output** — the repo-standard theme (see *Output theme*).
6. **Safety** — CTRL-C trap (exit 130), `ERR` trap reporting `$LINENO`, `check_for_root`.
7. **Package manager detection** — `detect_package_manager`, `setup_sudo`, `pkg_install`.
8. **Work sections** — one concern per section, in execution order. Bootstrap dependencies first (e.g. Homebrew before anything that calls `brew` — say so in the section title). Config-file editing helpers live in their own section.
9. **Main** — `main()` orchestrates, one call per line, inline comments only for ordering constraints. Ends with the closing STDOUT block (see *Ending*). Last line of the file: `main "$@"`.

## Section rules

Every section is fenced by figure-dash rules, exactly **79 columns**: `# ` + 77 × `‒` (U+2012 FIGURE DASH — not ASCII `-`, not en-dash). The title line is **right-aligned to column 79**:

```bash
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
#                                                                       Globals
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
```

Titles are short noun phrases (`Globals`, `Safety`, `Plugins`, `Default shell`, `Main`). A title may carry an ordering note when order is load-bearing: `Homebrew (macOS only) — must happen before anything that calls brew`. Explanatory prose goes in normal `#` comments *below* the fence, not in the title.

## Header block template

```bash
#!/usr/bin/env bash
#
# script_name.sh
#
# One or two lines: what it installs/does, in plain words.
#
# Targets:
#   - macOS                       (Homebrew)
#   - Debian / Ubuntu / Pi OS     (apt-get)
#   - Fedora / RHEL / Rocky / Alma (dnf)
#   ...only the ones the script actually supports
#
# Architecture note if relevant (x86_64, arm64/aarch64, armv7l).
#
# Usage:  ./script_name.sh [flags if any]
# Do not run as root.
#
# The script is idempotent: rerunning it should not duplicate config or fail.
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
```

The idempotency line is a promise, not decoration — see *Behavioral conventions*.

## Output theme

**The theme text has one source of truth: the `Pretty output` block in `install_zsh_starship.sh`.** Copy it verbatim; never retype it, never restyle it per-script.

- Scripts that can run on **macOS** embed the block (self-contained — `linux/base_functions.sh` is Linux-only). Mark the copy: `keep in sync with linux/base_functions.sh`.
- Scripts under **`linux/`** source `base_functions.sh` instead (with the auto-download-from-GitHub fallback — see `linux/kernel_update.sh`).

What the block provides, and the contract each piece carries:

| Helper | Contract |
|---|---|
| `QOL_COLOR` | Decided **once**, at the top: colors only when stdout is a TTY and `NO_COLOR` is unset. No per-call TTY checks. |
| `printline [style]` | Full-terminal-width separator; falls back to 80 cols with no TTY. Styles: `solid ─` (default), `bullet •`, `ibeam ⌶`, `star ★`, `plus ✛`, `diamond ◆`, `dentistry ⏥`. |
| `style_text "text" [weight] [color]` | Weights `normal\|bold\|light`; colors `red\|green\|yellow\|blue`. Plain text when colors are off. |
| `format_font` | `printline` + `style_text` — the repo-standard log line. Every user-facing milestone is a separator plus one styled line. |
| `log_info` … `log_err` | The only vocabulary for milestone output — see next section. |

## STDOUT vocabulary and voice

| Helper | Emoji | Style | Use for |
|---|---|---|---|
| `log_info` | `ℹ️` (three spaces after) | bold blue | Neutral facts: environment summary, "already cloned; pulling latest..." |
| `log_step` | `📦` (two spaces) | bold yellow | Starting work: `"Installing X..."` — present progressive, trailing `...` |
| `log_ok` | `✅` (two spaces) | bold green | Completion: `"X is installed."` / short-circuit: `"X is already installed."` |
| `log_warn` | `⚠️` (three spaces) | bold yellow | Non-fatal problems the script survives: `"p10k pull failed; continuing."` |
| `log_err` | `❌` (two spaces) | bold red, **to stderr** | Fatal problems. State what failed *and* what to do: `"Do not run as root. You'll be prompted for sudo if needed."` |

The uneven emoji padding is deliberate — `ℹ️` and `⚠️` carry a variation selector and render narrow; three spaces makes all five align on screen. Copy the strings, don't eyeball them.

Voice rules:

- Steps announce in present progressive with `...`; results state a fact with a period. The pair `"Installing zsh..."` → `"zsh is installed."` is the heartbeat of every script.
- Idempotent short-circuits still speak: `"Oh My Zsh is already installed."` A rerun narrates its skips — silence reads as failure.
- Warnings name the failure and the decision: `"chsh failed. You can change it manually with:  chsh -s $zsh_path"`.
- Errors are the only output on stderr.

### Ending

Every script closes `main()` the same way:

```bash
    format_font "Any next steps the user must take, as plain lines.
Second line if needed." normal blue
    format_font "Install complete. Please restart your terminal." bold green
    echo
```

Blue normal block = what happens next / what the user should do. Green bold line = done. Trailing `echo` = breathing room before the prompt.

## Behavioral conventions

- **Idempotent, always.** State-changing work lives in `ensure_*` functions that check before acting. Rerunning must not duplicate config lines, re-clone repos, or fail on existing state.
- **Never run as root** — `check_for_root` exits 1; privilege comes from a `$SUDO` prefix variable set once (empty on macOS).
- **Traps:** CTRL-C exits 130 through `handle_ctrl_c`; `ERR` trap reports the line number and exit code. Both installed right after the theme block.
- **Back up before touching a user dotfile** — one-time, timestamped, never clobber an existing backup: `cp "$f" "$f.pre<script>.$(date +%Y%m%d-%H%M%S).bak"` guarded by an `ls`-check.
- **Edit files without changing their identity.** `replace_file_contents` (cat-over, not `mv`) keeps the destination's mode, owner, and inode — `mv` from `mktemp` silently tightens a 0644 file to 0600.
- **Line-level edits are `ensure_line_in_file`** (grep `-qxF` then append); block-level edits are awk to a temp file. Portable sed = sed to temp + `replace_file_contents` (BSD + GNU).
- **Clean up your own past** — a `cleanup_legacy_*` function sweeps artifacts older versions of the script left behind, so reruns converge instead of accreting.
- **Package installs go through `pkg_install`** — one case statement over `brew|apt-get|dnf|pacman|apk|zypper`, quiet and non-interactive flags baked in. Support only the managers the header's *Targets* list claims.

## Scripts that take flags

Reference: `install_nano.sh`. Adds two sections after the theme block:

- **Arguments** — `usage()` as a single quoted heredoc (`cat <<'USAGE'`), then `parse_args`. Flags set SCREAMING_CASE globals declared in *Globals*.
- **Confirmation** — `confirm()` before each state-changing step, three rules in priority order: `--yes` (`ASSUME_YES`) skips the prompt; a non-TTY stdin (pipes, cron, test suites) skips it; otherwise ask and default to No.

## New script checklist

- [ ] Header block matches the template; Targets list is honest
- [ ] `set -eo pipefail`; Globals → theme → Safety → detection → work → Main, in that order
- [ ] Section fences: 79-col figure-dash rules, right-aligned titles
- [ ] Theme block copied verbatim from `install_zsh_starship.sh` (or sourced from `base_functions.sh` if Linux-only)
- [ ] All user-facing output goes through `log_*` / `format_font` — no naked `echo` milestones
- [ ] Step/ok pairs read `"...ing X..."` → `"X is installed."`; reruns narrate skips
- [ ] Errors to stderr, actionable; warnings name what continues anyway
- [ ] Idempotent rerun verified; dotfile backup taken once, timestamped
- [ ] Ends with blue next-steps, green completion line, `echo`; `main "$@"` is the last line
