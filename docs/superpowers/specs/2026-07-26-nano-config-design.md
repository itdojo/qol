# install_nano.sh — a good nano for students, on macOS and Linux

**Date:** 2026-07-26
**Status:** approved, not yet implemented

## Goal

Give a student who is going to live in nano the best version of it their machine
can run: syntax highlighting, line numbers, sane indentation, and a keybinding
they already have muscle memory for. One command, idempotent, macOS and Linux.

The audience is not me. It is a student who opens nano because it is the editor
they were told to use, and who needs the help bar to still be there when they
forget how to quit. Every design decision below is weighed against that.

## Verified environment facts

Confirmed by direct probe on macOS 26.5.2 and against the GNU nano 9.1 source
tarball, 2026-07-26:

- **`/usr/bin/nano` on macOS is not nano.** It is `UW PICO 5.09`. It does not
  accept `--version`; running it opens an editor. It has no syntax highlighting,
  no line numbers, and none of the modern `set` directives. There is no
  `/usr/share/nano/` directory on macOS. GNU nano must be installed via Homebrew.
- **Latest GNU nano is 9.1.** It ships 39 syntax definitions in `syntax/`
  (including `yaml`, `json`, `rust`, `go`, `sh`, `python`, `markdown`,
  `nftables`) plus 5 more in `syntax/extra/` (`ada`, `fortran`, `haskell`,
  `povray`, `spec`).
- **Duplicate syntax names are not an error.** `begin_new_syntax()` in
  `src/rcfile.c` prepends a new struct to the `syntaxes` list without checking
  for an existing name. `find_and_prime_applicable_syntax()` in `src/color.c`
  walks that list from the head and breaks on the first extension match. The
  head is the most recently parsed syntax, so **the last `include` wins**. This
  is a precedence question, not a collision-avoidance one.
- **`nano --help` is an exact capability probe.** `print_opt()` calls in
  `src/nano.c` emit the long-option form of every gated directive
  (`--indicator`, `--stateflags`, `--minibar`, `--zero`, `--guidestripe`,
  `--emptyline`, `--linenumbers`). Several are wrapped in `#ifdef`, so a distro
  build configured with `--enable-tiny` omits them *regardless of its version
  number*. A version table would be wrong on those builds; a `--help` grep is
  right on all of them.
- **`scopatz/nanorc`** — 3,257 stars, last pushed 2024-05-27, not archived. The
  de-facto community syntax pack, roughly 180 definitions.
- Directive introduction versions, from the nano 9.1 `NEWS` file:
  `guidestripe` and `emptyline` 4.0 · `indicator` 5.0 · `stateflags` 5.3 ·
  `minibar` 5.5 · `zero` 6.0. Everything else in the core config predates 2.9.7.

## Deliverables

| Path | What it is |
|:--|:--|
| `install_nano.sh` | Repo-root installer. Cross-platform, idempotent, `--dry-run` / `--yes` aware, in the style of `install_zsh_starship.sh`. |
| `nanorc.template` | The config body the installer renders, with capability-gated sections. |
| `docs/nano-cheatsheet.md` | Plain-text keybinding reference. |
| `docs/nano-cheatsheet.html` | Standalone printable reference in the IT Dojo design system. |
| `README.md` | One new row in the tool table. |

## 1. Detection and install

**macOS.** `brew install nano`. Then verify that `command -v nano` resolves to
the Homebrew build and not `/usr/bin/nano`. If it resolves to `/usr/bin/nano`,
stop and tell the user their PATH puts `/usr/bin` ahead of the Homebrew prefix —
writing a modern nanorc for pico would produce an error on every launch. Do not
attempt to fix their PATH.

**Linux.** Install through the package-manager matrix already used by
`install_zsh.sh`: apt, dnf, pacman, apk, zypper.

**Both.** After install, run `nano --version`. If it does not identify as GNU
nano 4.0 or newer, refuse to write a config and print the upgrade path. 4.0 is
the floor because it is where `guidestripe` and `emptyline` land and where the
line-wrapping default flipped; below it the config would need a second tier of
gating for a population of machines that barely exists.

## 2. Capability probe

Capture `nano --help` once. For each gated directive, test for its long-option
form:

```
nano --help | grep -q -- '--indicator'
```

This is exact per build and immune to both version skew and `--enable-tiny`.
The version check in section 1 remains as a floor and as the source of the
message shown when the build is too old; the probe decides what gets written.

## 3. Config rendering

One managed block in `~/.nanorc`, delimited by comment markers and rewritten
whole on every run — the same contract `install_zsh_starship.sh` uses for
`.zshrc`. Reruns cannot duplicate, and anything the user added outside the block
survives. If a `~/.nanorc` exists with no managed block in it, it is copied to a
timestamped backup before the block is inserted.

Core directives, all safe at 4.0+:

```
set linenumbers          set tabsize 4
set softwrap             set tabstospaces
set atblanks             set autoindent
set constantshow         set matchbrackets "(<[{)>]}"
set positionlog          set smarthome
set historylog           set trimblanks
set multibuffer          set guidestripe 80
```

Capability-gated, written only when the probe finds them:

```
set indicator            # a scrollbar-like position marker
set stateflags           # shows M (modified), I (autoindent) etc. in the title bar
```

Each directive the probe rejects leaves behind a comment naming it and the nano
version that would enable it, so a student who later upgrades can see what they
gained.

Deliberately excluded: `set mouse` (captures drag, breaking terminal
click-to-select copy), `set minibar` and `set zero` (hide the help bar — wrong
for this audience), `set backup` (litters the working directory with `~` files
that confuse a beginner reading `ls` output).

Also excluded: the interface colour directives (`set titlecolor`, `set
numbercolor`, `set keycolor`, and friends). Nano's defaults adapt to the
terminal's own palette; a hardcoded value that reads well on a dark terminal can
be illegible on a light one, and we do not know which our students use.

## 4. Syntax highlighting

`git clone https://github.com/scopatz/nanorc` to `~/.nano/`. On rerun, `git pull`
if the clone is clean; leave it alone and warn if it is dirty.

Include order, following the last-wins precedence established above:

```
include "~/.nano/*.nanorc"                    # community pack — broad coverage
include "/usr/share/nano/*.nanorc"            # shipped — authoritative, wins ties
include "/usr/share/nano/extra/*.nanorc"
```

The shipped definitions are versioned with the nano binary and are the better
ones where both packs define a language, so they go last and take precedence.
The community pack fills the roughly 140 gaps. No collision scan is needed.

Paths are resolved at install time — the Homebrew prefix on macOS
(`/opt/homebrew/share/nano` on Apple silicon, `/usr/local/share/nano` on Intel),
`/usr/share/nano` on Linux, plus Debian's `/usr/share/nano-syntax-highlighting/`
when present. Only paths that exist get an `include` line.

`--no-syntax` skips the clone entirely, for lab machines without outbound
network access. The shipped includes still get written.

## 5. Keybindings

```
bind ^S savefile main
bind ^Z suspend main
```

`^S` **already saves** on every build this config supports. GNU nano bound it
to `savefile` by default in 2.9.0 (2017-11-18), and the floor here is 4.0. The
line is kept anyway — it is explicit about a key students are told to use, it
costs nothing, and it still does the right thing on a terminal configured to
hand `^S` to nano differently or on a future nano that reassigns it — but it
**restates a default rather than adding a feature**, and neither cheat sheet
may badge it as something this config gives you.

`^Q` is left alone rather than rebound to exit. Since 2.9.0 it starts a
**backward search**, which is useful and which `^C` cancels; rebinding it would
take that away. `^X` remains the exit key and is printed on the help bar at all
times. `^B` is also a backward search on nano 8.0 and newer; below that it
moves the cursor left. Both belong in the cheat sheets' search section.

`^Z` is rebound to `suspend`. Stock nano leaves plain `^Z` doing nothing at all
— not undo, not suspend — and `man 5 nanorc`'s own EXAMPLES section gives this
exact binding. Every other program on the system suspends on `^Z`; a dead key
teaches the wrong lesson in a course that covers job control. `fg` returns.
Undo and redo stay on `M-U` and `M-E`, and go on the cheat sheet.

> **2026-07-27 — correction.** Two claims in the original text of this section
> were factually wrong on every supported build, and shipped into both cheat
> sheets and the config's own comments before being caught.
>
> 1. It said `^S` was a binding this config adds. It is a nano default from
>    2.9.0, seven major versions below our 4.0 floor. Verified by driving real
>    GNU nano 9.1 in a pty with an **empty** rcfile: `^S` reported
>    `[ Wrote 1 line ]` and the edit landed on disk.
> 2. It said `^Q` was left unbound because it "collides with XOFF terminal flow
>    control" and would freeze a serial console. Both halves are wrong. `^Q` is
>    bound — to backward search, since 2.9.0 (nano's `NEWS`: *"makes ^Q and ^S
>    do something useful by default"*). And nano disables terminal flow control
>    by default, which is precisely why `set preserve` exists to turn it back
>    on; the XOFF story describes the state that directive opts into, not the
>    state a student is in. Verified in the same pty: `^Q` opens
>    `Search [Backwards]:`, as does `^B`.
>
> The right conclusion survived — do not rebind `^Q` — but for the opposite
> reason: not because the key is dangerous, but because it already does
> something worth keeping.

## 6. Flags

| Flag | Effect |
|:--|:--|
| `--dry-run` | Print every action; write nothing. |
| `--yes` | No prompts. |
| `--no-syntax` | Skip the community-pack clone. |
| `--set-editor` | Also export `EDITOR=nano` and `VISUAL=nano` into the shell rc. Off by default — that is a second file and an unrelated surprise. |

## 7. Cheat sheet

Two renderings of one source of truth.

`docs/nano-cheatsheet.md` is the plain-text version, readable in the repo and in
a terminal.

`docs/nano-cheatsheet.html` is a standalone, printable page built on the IT Dojo
design system. Its `:root` and `[data-theme="dark"]` token blocks are copied from
`~/vaults/dojobrain/30-references/design-system/itdojo-design-system.html`, per
the machine-wide convention. Constraints:

- Self-contained: no external fonts, no CDN, no network at render time. The
  design-system reference pulls Roboto and Fira Code from Google Fonts; this page
  must instead declare those families with full system fallback chains, because
  it has to render correctly on a lab machine with no internet.
- Light and dark, honouring `prefers-color-scheme`, with a toggle.
- A print stylesheet — the point is that a student can tape it to a monitor.
- Keys rendered as `<kbd>`, styled from the inline-code rule (lavender surface,
  violet text, mono, `--r-xs`).
- Grouped by task, not alphabetically: Save & Quit · Move · Edit · Search &
  Replace · Select & Copy · Files & Buffers · Help.
- `^X` (exit) and `^S` (save) get visual priority — they are the two a
  panicking student needs. Given by the accent-stripe card variant on the
  "Get out" section rather than by a separate hero card duplicating those two
  rows above it.
- Notes where the config changes stock behaviour, so the sheet is true for a
  machine set up by this installer and flags what is ours.

## Testing

- Rerun the installer twice; assert `~/.nanorc` is byte-identical and the managed
  block appears exactly once.
- Assert `--dry-run` creates and modifies no files.
- Force each capability probe to fail and assert the resulting config contains no
  ungated directive and that `nano` launches clean.
- Assert the macOS pico path refuses rather than writing a config.
- Open a `.yaml`, a `.tf`, and a `.sh` file and confirm highlighting is applied
  and that the shipped `yaml` definition wins over the community one.
- Validate the HTML cheat sheet renders with no network access and prints to one
  page. "One page" is measured, not eyeballed: render headless to PDF and count
  `/Type /Page` objects. Do it from a dark-themed browser too — the print token
  reset is what keeps that case legible, and a hardcoded colour that escapes it
  is invisible rather than obviously wrong.

## Out of scope

Nano plugin managers, `.nanorc` colour-theme kits, and any change to existing
repo scripts.
