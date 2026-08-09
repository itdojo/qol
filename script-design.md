# qol script design

The house style for every shell script in this repo. `install_zsh_starship.sh` is the living reference — when this doc and that script disagree, fix one of them, never a third way. `install_nano.sh` is the reference for scripts that take flags. `linux/base_functions.sh` is the sourced library for Linux-only scripts.

Status note (2026-07-27): `install_zsh.sh` was the original reference and is now deprecated — still published because people depend on it; long-term it will be removed or replaced by the starship script under the old name.

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
#                                                                       GLOBALS
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
```

Titles are short noun phrases in UPPERCASE (`GLOBALS`, `SAFETY`, `PLUGINS`, `DEFAULT SHELL`, `MAIN`); a parenthetical qualifier may stay lowercase (`GENERIC TOOL INSTALLER (idempotent)`). A title may carry an ordering note when order is load-bearing: `HOMEBREW (MACOS ONLY) — MUST HAPPEN BEFORE ANYTHING CALLS BREW`. Explanatory prose goes in normal `#` comments *below* the fence, not in the title.

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

**The palette has one source of truth, and it is not this repo:** `~/vaults/dojobrain/30-references/design-system/itdojo-terminal-design-system.md`. The rendered reference beside it shows every surface at real hex values. Read it before changing anything about how a script looks.

**The theme text has one source of truth in this repo:** the `Pretty output` block in `linux/base_functions.sh`, running from `qol_init_color() {` to `# ‒‒ end theme block`. Copy it verbatim; never retype it, never restyle it per-script.

Which mechanism a script uses follows from where it can run, not from taste:

| Script | Mechanism |
|---|---|
| `linux/base_functions.sh` | The canonical block. Everything else is a copy of this. |
| `install_zsh_starship.sh` · `install_nano.sh` · `install_zsh.sh` · `uninstall_omz_p10k.sh` · `macos/install-nerd-fonts.sh` | Embed the full block — they run on macOS, where the Linux-only library is unavailable. |
| `linux/docker_install.sh` · `linux/docker_uninstall.sh` · `linux/kernel_update.sh` · `linux/wireshark_install.sh` · `linux/nm-connection-maker.sh` · `tool_checks.sh` | Source `base_functions.sh`, with the auto-download-from-GitHub fallback (see `linux/kernel_update.sh`). |
| `netstatus.sh` | Embeds the generated ink block **only**. It prints a one-line readout at shell startup, so it takes the palette and none of the badge grammar. |
| `shell-login-settings.sh` | Neither. Sourced into login shells, so it must stay dependency-free; it hand-writes the badge words with no ink, which is exactly what the helpers emit at `QOL_COLOR_DEPTH=none`. |
| `gotime` | A third hand-written copy under `C_*` names, which the generator cannot reach. See the gotcha in `docs/working-notes.md`. |

`tests/test-theme-sync.sh` proves every copy in the first four rows still matches the canonical block. Run it after touching any of them, and after a `--write-qol` run in the vault.

A script that embeds the block embeds **all** of it, including the `ask_*` helpers it may not call. A partial copy is a restyle, and the sync test is byte-exact on purpose.

The ink `case` block inside that section is generated — everything between `# ‒‒ generated by dojobrain …` and `# ‒‒ end generated block`. Never hand-edit it. To change a color, edit `tokens/colors.css` in the vault, then write the result back:

```
cd ~/vaults/dojobrain && uv run scripts/build-design-tokens.py --write-qol
```

That rewrites the region in both files and touches nothing else here. `--emit-bash` still prints the block to stdout if you want to inspect it first, and `--check` reports drift without fixing anything — it flags a stale triplet found *outside* the generated region separately, because that one is hand-written and no regeneration will repair it.

The vault never runs git in this repo. A `--write-qol` run leaves the change uncommitted on purpose; review and commit it here yourself.

What the block provides, and the contract each piece carries:

| Helper | Contract |
|---|---|
| `qol_init_color` | Decides color and depth **once**, at source time. Re-callable, which is how the tests force a tier. `NO_COLOR` wins over everything; `QOL_FORCE_COLOR` keeps color on without a TTY; `QOL_COLOR_DEPTH` selects `truecolor` (default), `256`, `8`, or `none`. |
| `_term_cols` · `_repeat` | Width and fill primitives. Private; call the helpers below instead. |
| `_log_line` | The 9-column prefix: gutter, space, 4-char badge, 3 spaces. Private. |
| `log_step` … `log_next` | The only vocabulary for milestone output — see next section. |
| `log_phase "TITLE"` | Phase boundary: a gray rule carrying the phase name. Replaces the old per-line separator. |
| `banner "TITLE" ["sub"]` · `log_complete "TITLE"` | Run bookends, in jade so a run's edges stay findable. Not named `complete` — that is a bash builtin. |
| `printline` · `style_text` · `format_font` · `log_title` · `fstring` | Vestigial as of 2026-08-09: **no script in this repo calls them any more**. Kept only because they are the published API other people's scripts may source, and exercised by `tests/test-theme.sh`. Never call them in new code. |

## STDOUT vocabulary and voice

| Helper | Badge | Ink | Use for |
|---|---|---|---|
| `log_info` | `INFO` | steel | Neutral facts: environment summary, "already cloned; pulling latest..." |
| `log_step` | `STEP` | violet | Starting work: `"Installing X..."` — present progressive, trailing `...` |
| `log_ok` | `PASS` | jade | Completion: `"X is installed."` / short-circuit: `"X is already installed."` |
| `log_warn` | `WARN` | saffron | Non-fatal problems the script survives: `"p10k pull failed; continuing."` |
| `log_err` | `STOP` | wine | Fatal problems, **to stderr**. State what failed *and* what to do. |
| `log_ask` | `ASK` | violet | A question that determines a value. |
| `log_next` | `NEXT` | steel | What the user must do after the run ends. |

Every badge pads to four characters, so message text always starts at column 10. Do not add padding of your own.

Voice rules:

- Steps announce in present progressive with `...`; results state a fact with a period. The pair `"Installing zsh..."` → `"zsh is installed."` is the heartbeat of every script.
- Idempotent short-circuits still speak: `"Oh My Zsh is already installed."` A rerun narrates its skips — silence reads as failure.
- Warnings name the failure and the decision: `"chsh failed. You can change it manually with:  chsh -s $zsh_path"`.
- Errors are the only output on stderr.
- Subprocess output is never indented. Piping `apt` or `curl` through `sed` to align it kills progress meters and swallows sudo prompts.

### Ending

Every script closes `main()` the same way:

```bash
    log_complete "WHAT FINISHED"
    log_next "Anything the user must still do, one line each."
    echo
```

Jade-ruled completion block, then `NEXT` lines, then a trailing `echo` for breathing room before the prompt.

**Bookends belong to a run, not to a function.** A file that is both runnable and sourceable — `linux/docker_uninstall.sh`, `uninstall_omz_p10k.sh` — puts `banner` and `log_complete` in its `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` branch, never inside the worker function. When `docker_install.sh` sources the uninstaller and calls it mid-run, that run already has a banner and owns its own ending; a second pair of jade rules in the middle of it says "the run ended" when it did not. A pure library (`tool_checks.sh`, `linux/base_functions.sh`) has no bookends at all.

**A completion block must not claim work that did not happen.** A `--dry-run`, a declined prompt, or a "nothing was installed" short-circuit still ends cleanly, but `log_complete "X REMOVED"` over a run that removed nothing is a lie the user reads as success. Track it — `uninstall_omz_p10k.sh` sets `NOTHING_DONE`, `install_nano.sh` tracks `nanorc_written`/`editor_written` — and say which kind of nothing it was.

## Asking questions

Three shapes, all in `base_functions.sh`. Prompts go to **stderr**, answers to **stdout**, so `$(...)` capture returns the answer alone.

| Helper | Returns | Notes |
|---|---|---|
| `ask_confirm "q" [Y\|N]` | exit 0 = yes, 1 = no | Replaces the old `confirm()` pattern. |
| `ask_value "q" "default" ["hint"]` | echoes the answer | `⏎` accepts the default. |
| `ask_choice "HEADING" n "label\|hint" ...` | echoes a 1-based index | Arrow keys, `j`/`k`, digit jump, `⏎` selects. |

All three skip the prompt and return the default when `ASSUME_YES` is set or stdin is not a TTY, in that priority order. `ask_choice` redraws in place rather than taking the alternate screen — an installer that blanks the scrollback has destroyed the record of what it just did. Close a question sequence with a `log_ok` restating every collected value, so nothing installs before the user has seen what they agreed to.

**When a question does not fit one of the three shapes, borrow the chrome and not the helper.** Print `log_ask "$q"`, then the jade caret — `printf '    %s❯%s %s[hint]%s ' "$QOL_PASS" "$QOL_RESET" "$QOL_META" "$QOL_RESET"` — and keep your own `read`. The question then looks identical to every other question in the repo while keeping semantics the helper cannot express. Four live reasons to do this, all of them load-bearing:

- **Three-way questions.** `linux/docker_uninstall.sh` and `uninstall_omz_p10k.sh` ask remove / keep / quit, and the `130` return is what tells a sourcing caller to abort. `ask_confirm` only answers yes or no.
- **A dangerous default that `ASSUME_YES` must not flip.** `linux/kernel_update.sh` gates `rpi-update` — unreleased firmware that can brick a Pi — behind a `[y/N]`. That script has no `--yes` flag, so it never documented `ASSUME_YES`, and a stray one in the environment must not be what flashes the firmware.
- **Hidden input.** `ask_value` echoes. The Wi-Fi passphrase prompt in `linux/nm-connection-maker.sh` needs `read -rs`.
- **A test seam the helper would bypass.** `install_nano.sh`'s `confirm()` routes every prompt through `QOL_NANO_FORCE_TTY`, which is how its 296-test suite drives them; `ask_confirm`'s own non-TTY rule would short-circuit ahead of it.

Say which reason applies in a comment at the call site. "Not `ask_confirm`, because…" is the difference between a considered exception and someone not knowing the helper existed.

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
- [ ] Section fences: 79-col figure-dash rules, right-aligned UPPERCASE titles
- [ ] Theme block copied verbatim from `linux/base_functions.sh` (or sourced from it if Linux-only); `tests/test-theme-sync.sh` passes
- [ ] All user-facing output goes through `log_*` — no naked `echo` milestones, no `style_text`/`format_font` in new code
- [ ] Detail lines under a milestone are indented to column 10, matching where the badge's message starts
- [ ] Step/ok pairs read `"...ing X..."` → `"X is installed."`; reruns narrate skips
- [ ] `main()` opens with `banner` and closes with `log_complete` + `log_next`; phases marked with `log_phase`
- [ ] Bookends are in the run, not in a sourceable function; a dry run or declined prompt does not print a completion block claiming work
- [ ] Questions use `ask_confirm`/`ask_value`/`ask_choice`, or say in a comment why they cannot
- [ ] No `clear` at the top — the banner is the boundary; blanking the scrollback destroys the record of what came before
- [ ] Any pre-source bootstrap failure prints the `▌ STOP   ` prefix by hand, so it greps alongside every other error
- [ ] No emoji anywhere in user-facing output — the badge carries the meaning
- [ ] Errors to stderr, actionable; warnings name what continues anyway
- [ ] Idempotent rerun verified; dotfile backup taken once, timestamped
- [ ] Ends with `log_complete`, `log_next` lines, `echo`; `main "$@"` is the last line
- [ ] `shellcheck -x` reports nothing new against the previous revision
