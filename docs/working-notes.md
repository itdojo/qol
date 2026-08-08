# Working notes — qol

Durable repo knowledge. Point-in-time work state belongs in `docs/handoff.md`, not here.

## Constraints

- **Bash 3.2.** `install_zsh_starship.sh` and `gotime` run on macOS, which ships bash 3.2. No `declare -A`, no `${var^^}`, no `read -N`.
- **The milestone prefix is exactly 9 columns** — `▌`, space, 4-character badge, 3 spaces. Message text begins at column 10. Every badge pads to four (`ASK ` and `NEXT` alike), which is what removed the per-marker padding table the old emoji vocabulary needed.
- **The badge set is closed:** `STEP PASS INFO WARN STOP ASK NEXT`. Adding an eighth is a design-system change, not a script change — it belongs in the vault note first.
- **These public names must keep working:** `printline`, `style_text`, `format_font`, `log_title`, `fstring`, `log_info`, `log_step`, `log_ok`, `log_warn`, `log_err`, `check_status`. Eight other scripts call them.
- **Never name a shell function `complete`** — it is a bash builtin for programmable completion. The run-bookend helper is `log_complete` for exactly this reason, and `tests/test-theme.sh` asserts the builtin is still intact.

## Decisions

- **The palette's source of truth is the vault**, at `~/vaults/dojobrain/30-references/design-system/tokens/colors.css`, documented in `itdojo-terminal-design-system.md`. This repo holds copies, never originals. A second description of a color is a second thing to drift.
- **Color depth is never detected, only defaulted.** Truecolor is assumed; `QOL_COLOR_DEPTH=256|8|none` forces down. Detection would always guess low, because SSH strips `COLORTERM` (`sshd_config` ships `AcceptEnv LANG LC_*` and nothing else). A terminal that genuinely lacks 24-bit support approximates gracefully rather than printing garbage, so optimism costs less than detection.
- **The xterm-256 indices are perceptual picks, not nearest-cube matches**, and therefore cannot be computed. Nearest for violet `#BCB0E8` is 146, which reads gray beside the prose color. Three indices (violet 140, rule 60, selection 235) are chosen for separation on a projector over Euclidean accuracy.
- **The 8-color tier uses the bright set, not the dim one.** The dim six are unreadable on a near-black panel. This is the one place the brand's no-red rule yields to the medium — wine collapses onto bright red because there is nothing else.
- **The gutter bar prints at every tier including `none`**, so a log captured with `NO_COLOR=1` lines up with what was on screen and stays greppable as `grep -E '^. (WARN|STOP)'`.

## Ruled out

- **The emoji vocabulary** (`✅📦ℹ️⚠️❌`). It carried colors no script can override, `❌` renders a red the brand forbids, and its inconsistent advance widths are why the house style once had to document that "the uneven emoji padding is deliberate." The crest `⛩` survives in banners as brand furniture, not as a status marker.
- **Indenting subprocess output.** Piping `apt` or `curl` through `sed` to align it kills progress meters, swallows interactive sudo prompts, and buffers what should stream. Raw subprocess output stays flush left; only script-authored lines carry the gutter.
- **A per-line separator.** `printline` between every message meant nothing. A rule now marks a phase boundary, which is information.

## Gotchas

- **Unused color variables trip shellcheck SC2034.** This has bitten twice — `QOL_SEL` in `base_functions.sh` (commit `c680f18`) and both `C_DIM` and `C_STEEL` in `gotime`. The rule that settled it: an SGR *attribute* with no reader gets deleted, a *token ink* with no reader gets a `# shellcheck disable=SC2034` and a comment saying why. `C_DIM` was deleted — the design retired dim-on-dim in favor of `C_META`, so nothing will want it back. `C_STEEL` was kept and suppressed, because dropping a token from a palette copy makes it a worse copy, and `gotime` emits no INFO line only because it states and asks rather than narrating.
- **The `gotime` menu frame's rules are gray, not jade** — `hr()` correctly uses `C_RULE`. Task 7 step 8 of the plan says to expect "jade rules" and is wrong; the rendered reference's Interactive pane draws all three `━` lines in `--terminal-rule`, and the reference is what step 8 tells you to compare against. Jade rules are for *run bookends* (`banner`, `log_complete` in `base_functions.sh`), where the point is finding a run's edges when scrolling back. A TUI on the alternate screen has no scrollback, so the rationale does not carry.
- **`gotime` carries a third copy of the palette that nothing checks, and that is a decision, not an oversight** (2026-08-08). The vault's `build-design-tokens.py` knows only `linux/base_functions.sh` and `install_zsh_starship.sh` in its `QOL_FILES` list, so `--check` never sees `gotime` and `--write-qol` cannot reach it. Its hand-written `case` block was verified against `tokens/colors.css` when it landed — all nine truecolor triplets and all nine 256 indices — and it will drift silently from here. Wiring it up is not a one-line change: `gotime` names its inks `C_*` because ~30 `printf` call sites depend on those names, while the emitter writes `QOL_*`, so the generator would need a variable-prefix argument first. Verify by hand after any token change until someone does that work.
- **A repo-wide emoji grep will always fail, and that is correct.** The terminal-design-system plan's final verification runs `! grep -rn '✅|📦|ℹ️|⚠️|❌' --include='*.sh' --include='gotime' --include='*.md' .` and expects silence. It can never be silent: the same plan's Out of scope list keeps nine scripts on the back-compat helpers, `install_nano.sh` and `macos/install-nerd-fonts.sh` define their own emoji `log_*` wrappers, `netstatus.sh`'s `🛜 ✅ ❌` are its product output rather than log badges, and the docs under `docs/` quote the retired vocabulary on purpose. Scope the check to the five files the rebrand actually converted — `gotime`, `linux/base_functions.sh`, `install_zsh_starship.sh`, `linux/docker_install.sh`, `script-design.md` — which are clean.
- **`--write-qol` reaches only marker-bounded regions.** The vault rewrites the text between `# ‒‒ generated by dojobrain …` and `# ‒‒ end generated block`, and reports rather than guesses when a file lacks those markers. A file without them is invisible to the writer.
- **The two theme-block copies must stay byte-identical.** `install_zsh_starship.sh` embeds a copy because it must run on macOS where `linux/base_functions.sh` is unavailable. `tests/test-theme-sync.sh` is the only thing keeping that copy honest — run it after touching either file.
- **The vault never runs git here.** A `--write-qol` run lands uncommitted on purpose; committing in this repo is always a human act.
