# IT Dojo Terminal Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the emoji-and-basic-ANSI output theme in the qol scripts with the IT Dojo terminal palette, and give the vault a generator so the shell copy of those token values cannot silently drift.

**Architecture:** Token values live in the Dojobrain vault at `30-references/design-system/tokens/colors.css` and are the only source of truth. `scripts/build-design-tokens.py` gains an `--emit-bash` mode that renders the shell color block from those tokens, a `--check` pass that reports drift in the qol repo, and (added 2026-08-08, after Task 2 shipped) a `--write-qol` mode that repairs that drift in place. On the qol side, `linux/base_functions.sh` holds the canonical theme block and `install_zsh_starship.sh` holds a verbatim copy for macOS-capable scripts; every other script inherits the new look by sourcing or copying, so most need only phase rules and bookends added.

**Tech Stack:** Bash 3.2+ (macOS ships 3.2, so no associative arrays, no `read -N`), Python 3.11+ under `uv` for the vault generator, hand-rolled bash test harness with no framework.

## Global Constraints

- Two repos are touched. Tasks 1–2 commit in `~/vaults/dojobrain`; Tasks 3–8 commit in `~/projects/qol`. Never stage across repos.
- Two repos are touched, and the vault may write into this one. Dojobrain hard rule 9 was split on 2026-08-08 (`~/vaults/dojobrain/30-references/setup-decisions/vault-authors-into-its-repos.md`): rule 9 now governs vault-to-vault traffic only, and the new rule 10 lets the vault author into `~/courseware/<slug>/` and `~/projects/<slug>/`. **This constraint originally read "the vault must never write into `~/projects/qol`… the generator prints to stdout; a human pastes."** That is no longer true, and Tasks 1–6 were executed under it — which is why the block was hand-pasted rather than written. `--write-qol` now rewrites the generated region in place. What has *not* changed: the vault never runs git here. A rewrite lands uncommitted and the commit stays a human act.
- Bash 3.2 compatibility is required — `install_zsh_starship.sh` runs on macOS. No `declare -A`, no `${var^^}`, no `read -N`.
- Milestone prefix is exactly 9 columns: `▌`, space, 4-character badge, 3 spaces. Message text begins at column 10.
- The seven badges are `STEP PASS INFO WARN STOP ASK  NEXT`, all padded to 4 characters.
- Never name a shell function `complete` — it is a bash builtin for programmable completion. Use `log_complete`.
- Public function names `printline`, `style_text`, `format_font`, `log_title`, `fstring`, `log_info`, `log_step`, `log_ok`, `log_warn`, `log_err`, `check_status` must keep working. Eight other scripts call them and are out of scope for this plan.
- Filenames are lowercase letters, digits, hyphens.
- Dates in any persisted file are absolute (`2026-08-08`), never relative.
- Spec: `~/vaults/dojobrain/30-references/design-system/itdojo-terminal-design-system.md`.

## File Structure

| File | Responsibility |
| --- | --- |
| `~/vaults/dojobrain/30-references/design-system/tokens/colors.css` | The nine new `--terminal-*` ink tokens. Source of truth for every hex below. |
| `~/vaults/dojobrain/scripts/build-design-tokens.py` | Adds `--emit-bash`, terminal-note drift check, qol drift check, and `--write-qol` to repair it. |
| `~/projects/qol/linux/base_functions.sh` | Canonical theme block: depth selection, ink variables, badge helpers, bookends. |
| `~/projects/qol/install_zsh_starship.sh` | Verbatim copy of the theme block (macOS-capable, cannot source Linux-only lib) plus its own phases. |
| `~/projects/qol/linux/docker_install.sh` | Phase rules and bookends only — inherits ink by sourcing. |
| `~/projects/qol/gotime` | Standalone TUI. Own copy of the ink block plus rebranded chrome. |
| `~/projects/qol/script-design.md` | Output theme section becomes a pointer to the vault note; bash contract stays. |
| `~/projects/qol/tests/test-theme.sh` | New. Column arithmetic, depth tiers, stderr routing, back-compat aliases. |
| `~/projects/qol/tests/test-theme-sync.sh` | New. Proves the two copies of the theme block are byte-identical. |

---

### Task 1: Add the terminal ink tokens to the vault

**Files:**
- Modify: `~/vaults/dojobrain/30-references/design-system/tokens/colors.css:29-33`

**Interfaces:**
- Consumes: nothing.
- Produces: CSS custom properties `--terminal-step`, `--terminal-pass`, `--terminal-info`, `--terminal-warn`, `--terminal-stop`, `--terminal-meta`, `--terminal-rule`, `--terminal-sel`, `--terminal-ok-bg` in the base `:root` block, as literal hex values.

These go in base `:root`, not in `[data-theme="dark"]`. A token serving a permanently dark panel does not flip with theme — the existing `--terminal-kw:#B69CFF` sets that precedent.

- [x] **Step 1: Confirm the generator is currently clean**

```bash
cd ~/vaults/dojobrain && uv run scripts/build-design-tokens.py --check
```

Expected: `30-references/design-system/itdojo-design-system.html: up to date` and exit 0. If it already fails, stop and report — this plan assumes a clean starting state.

- [x] **Step 2: Add the nine tokens**

In `tokens/colors.css`, find this block inside `:root`:

```css
  /* terminal panel — stays dark in both themes */
  --terminal-bg:var(--gray-900);
  --terminal-fg:var(--lavender);
  --terminal-str:var(--mint);
  --terminal-kw:#B69CFF;
  --terminal-comment:var(--gray-500);
```

Replace it with:

```css
  /* terminal panel — stays dark in both themes */
  --terminal-bg:var(--gray-900);
  --terminal-fg:var(--lavender);
  --terminal-str:var(--mint);
  --terminal-kw:#B69CFF;
  --terminal-comment:var(--gray-500);
  /* terminal ink — shell script STDOUT and TUIs. Literals, not theme-flipped:
     a terminal has no light mode, so these hold their dark values always.
     See 30-references/design-system/itdojo-terminal-design-system.md */
  --terminal-step:#BCB0E8;
  --terminal-pass:#4ECE6A;
  --terminal-info:#7AA0D8;
  --terminal-warn:#E0B45A;
  --terminal-stop:#E06B82;
  --terminal-meta:#9A93B5;
  --terminal-rule:#4A4170;
  --terminal-sel:#241D3D;
  --terminal-ok-bg:#15321F;
```

- [x] **Step 3: Rebuild the HTML token block**

```bash
cd ~/vaults/dojobrain && uv run scripts/build-design-tokens.py
```

Expected: `rebuilt token blocks in 30-references/design-system/itdojo-design-system.html`, exit 0.

- [x] **Step 4: Verify the new tokens landed in the generated block**

```bash
cd ~/vaults/dojobrain && grep -c 'terminal-step\|terminal-pass\|terminal-ok-bg' 30-references/design-system/itdojo-design-system.html
```

Expected: `3`.

- [x] **Step 5: Verify check passes**

```bash
cd ~/vaults/dojobrain && uv run scripts/build-design-tokens.py --check
```

Expected: `up to date`, exit 0.

- [x] **Step 6: Commit**

```bash
cd ~/vaults/dojobrain
git add 30-references/design-system/tokens/colors.css 30-references/design-system/itdojo-design-system.html
git commit -m "feat: add terminal ink tokens to the design system

Nine --terminal-* inks for shell script STDOUT and TUIs. Literals in
:root rather than theme-flipped, following --terminal-kw: a terminal
has no light mode."
```

---

### Task 2: Teach the generator to emit the shell block and detect qol drift

**Files:**
- Modify: `~/vaults/dojobrain/scripts/build-design-tokens.py`

**Interfaces:**
- Consumes: the nine `--terminal-*` tokens from Task 1.
- Produces: `uv run scripts/build-design-tokens.py --emit-bash` prints a bash `case` block on stdout, consumed verbatim by Task 3. `--check` additionally reports drift in `itdojo-terminal-design-system.md` and in the two qol files, and exits 1 when any is found.

The qol check reads and never writes. Reading across the repo boundary is permitted (hard rule 8); writing is not (hard rule 9).

> **Superseded 2026-08-08, after this task shipped.** Hard rule 9 was split and the prohibition on writing here is gone (see Global Constraints). The generator gained `--write-qol`, which rewrites the region between `# ‒‒ generated by dojobrain …` and `# ‒‒ end generated block` in the two files above. The code snippets in this task are left as written — they are the record of what was actually executed, and the script has since moved past them. Read the script, not this task, for its current shape.

- [x] **Step 1: Add the terminal ink table and helpers**

Insert after the `NOTE = DS / "itdojo-design-system.md"` line:

```python
TERMINAL_NOTE = DS / "itdojo-terminal-design-system.md"

# Token -> (shell variable, xterm-256 index, "fg"|"bg").
# The 256 indices are PERCEPTUAL picks, not nearest-cube matches, so they
# cannot be computed — nearest for --terminal-step is 146, which reads gray
# beside --terminal-fg. See the terminal design system note.
TERMINAL_INK = [
    ("--terminal-step",   "QOL_STEP", 140, "fg"),
    ("--terminal-pass",   "QOL_PASS",  77, "fg"),
    ("--terminal-info",   "QOL_INFO", 110, "fg"),
    ("--terminal-warn",   "QOL_WARN", 179, "fg"),
    ("--terminal-stop",   "QOL_STOP", 168, "fg"),
    ("--terminal-fg",     "QOL_FG",   189, "fg"),
    ("--terminal-meta",   "QOL_META", 103, "fg"),
    ("--terminal-rule",   "QOL_RULE",  60, "fg"),
    ("--terminal-sel",    "QOL_SEL",  235, "bg"),
    ("--terminal-ok-bg",  "QOL_OKBG",  22, "bg"),
]

# 8-color tier uses the BRIGHT set: the dim six are unreadable on a near-black
# panel. Violet and steel both collapse onto bright blue, wine onto bright red.
TERMINAL_8 = {
    "QOL_STEP": "94", "QOL_PASS": "92", "QOL_INFO": "94", "QOL_WARN": "93",
    "QOL_STOP": "91", "QOL_FG": "97",  "QOL_META": "90", "QOL_RULE": "90",
    "QOL_SEL": "7",   "QOL_OKBG": "7",
}

# Files in the qol repo that carry a copy of the shell block. Read-only:
# the vault may reference a repo by absolute path but must never write there.
QOL_FILES = [
    Path.home() / "projects" / "qol" / "linux" / "base_functions.sh",
    Path.home() / "projects" / "qol" / "install_zsh_starship.sh",
]


def hex_to_triplet(value: str) -> str:
    """'#BCB0E8' -> '188;176;232'."""
    h = value.lstrip("#")
    return f"{int(h[0:2], 16)};{int(h[2:4], 16)};{int(h[4:6], 16)}"


def terminal_hexes(light: list[str]) -> dict[str, str]:
    """Map every --terminal-* ink token to its literal hex from tokens/."""
    truth = {
        m[1]: m[2].upper()
        for m in (re.match(r"\s*(--[a-z0-9-]+)\s*:\s*(#[0-9A-Fa-f]{6})\s*;", line) for line in light)
        if m
    }
    missing = [name for name, _, _, _ in TERMINAL_INK if name not in truth]
    if missing:
        sys.exit(f"terminal ink tokens absent from tokens/: {', '.join(missing)}")
    return {name: truth[name] for name, _, _, _ in TERMINAL_INK}
```

- [x] **Step 2: Add the bash emitter**

Insert after `terminal_hexes`:

```python
def emit_bash(light: list[str]) -> str:
    """Render the shell ink block. Paste into qol; the vault never writes there."""
    hexes = terminal_hexes(light)
    out = [
        "# ‒‒ generated by dojobrain scripts/build-design-tokens.py --emit-bash",
        "# ‒‒ do not hand-edit; edit tokens/colors.css and re-emit.",
        '    case "$QOL_DEPTH" in',
        "        truecolor)",
    ]
    for token, var, _idx, kind in TERMINAL_INK:
        sgr = "38" if kind == "fg" else "48"
        out.append(f"            {var}=$'\\033[{sgr};2;{hex_to_triplet(hexes[token])}m'")
    out += ["            ;;", "        256)"]
    for token, var, idx, kind in TERMINAL_INK:
        sgr = "38" if kind == "fg" else "48"
        out.append(f"            {var}=$'\\033[{sgr};5;{idx}m'")
    out += ["            ;;", "        8)"]
    for _token, var, _idx, _kind in TERMINAL_INK:
        out.append(f"            {var}=$'\\033[{TERMINAL_8[var]}m'")
    out += ["            ;;", "        *)"]
    out.append("            " + " ".join(f'{var}=""' for _t, var, _i, _k in TERMINAL_INK))
    out += ["            ;;", "    esac"]
    return "\n".join(out)


def qol_drift(light: list[str]) -> list[str]:
    """Report truecolor triplets in qol that no longer match tokens/. Never writes."""
    truth = {hex_to_triplet(v) for v in terminal_hexes(light).values()}
    problems: list[str] = []
    for path in QOL_FILES:
        if not path.exists():
            continue
        found = set(re.findall(r"[34]8;2;(\d{1,3};\d{1,3};\d{1,3})", path.read_text(encoding="utf-8")))
        stale = sorted(found - truth)
        if stale:
            shown = ", ".join(stale[:4]) + ("…" if len(stale) > 4 else "")
            problems.append(f"  {path}: {len(stale)} triplet(s) not in tokens/: {shown}")
    return problems
```

- [x] **Step 3: Point the note-drift check at both notes**

Replace the body of `note_drift` — specifically the loop line that reads `NOTE` — so it scans both notes. Change this:

```python
    for name, hex_value in re.findall(r"`(--[a-z0-9-]+):\s*(#[0-9A-Fa-f]{6})`", NOTE.read_text(encoding="utf-8")):
```

to this:

```python
    prose = NOTE.read_text(encoding="utf-8")
    if TERMINAL_NOTE.exists():
        prose += TERMINAL_NOTE.read_text(encoding="utf-8")
    for name, hex_value in re.findall(r"`(--[a-z0-9-]+):\s*(#[0-9A-Fa-f]{6})`", prose):
```

- [x] **Step 4: Wire the new flag and check into `main`**

In `main()`, after the `args = parser.parse_args()` line, add the `--emit-bash` argument to the parser and an early return. The parser block becomes:

```python
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="exit 1 if out of date, write nothing")
    parser.add_argument("--emit-bash", action="store_true", help="print the qol shell ink block to stdout")
    args = parser.parse_args()

    if args.emit_bash:
        light, _dark = collect()
        print(emit_bash(light))
        return 0
```

Then, immediately after the existing `strays` block, add:

```python
    drifted = qol_drift(light)
    if drifted:
        print("DRIFT in ~/projects/qol (read-only check; fix by re-emitting):")
        print("\n".join(drifted))
        print("  Regenerate with: uv run scripts/build-design-tokens.py --emit-bash")
        problems += drifted
```

- [x] **Step 5: Verify the emitter produces the expected truecolor escape**

```bash
cd ~/vaults/dojobrain && uv run scripts/build-design-tokens.py --emit-bash | grep QOL_STEP
```

Expected, twice (truecolor then 256), plus once for the 8 tier:

```
            QOL_STEP=$'\033[38;2;188;176;232m'
            QOL_STEP=$'\033[38;5;140m'
            QOL_STEP=$'\033[94m'
```

- [x] **Step 6: Verify `--check` still exits 0**

```bash
cd ~/vaults/dojobrain && uv run scripts/build-design-tokens.py --check; echo "exit=$?"
```

Expected: `up to date` and `exit=0`. The qol files have no truecolor triplets yet, so `qol_drift` returns empty.

- [x] **Step 7: Verify the drift check actually fires**

```bash
cd ~/vaults/dojobrain
printf "QOL_FAKE=\$'\\\\033[38;2;1;2;3m'\n" >> ~/projects/qol/linux/base_functions.sh
uv run scripts/build-design-tokens.py --check; echo "exit=$?"
```

Expected: a `DRIFT in ~/projects/qol` line naming `1;2;3`, and `exit=1`.

Now undo the probe:

```bash
cd ~/projects/qol && git checkout linux/base_functions.sh
cd ~/vaults/dojobrain && uv run scripts/build-design-tokens.py --check; echo "exit=$?"
```

Expected: `exit=0`.

- [x] **Step 8: Commit**

```bash
cd ~/vaults/dojobrain
git add scripts/build-design-tokens.py
git commit -m "feat: emit the qol shell ink block from tokens, detect drift read-only

--emit-bash renders the bash case block from tokens/colors.css. --check
gains a read-only pass over the two qol files that carry a copy, so the
fourth downstream consumer cannot drift silently. The vault never writes
outside itself."
```

---

### Task 3: Rewrite the theme block in base_functions.sh

**Files:**
- Modify: `~/projects/qol/linux/base_functions.sh:25-108`
- Create: `~/projects/qol/tests/test-theme.sh`

**Interfaces:**
- Consumes: the block printed by `uv run scripts/build-design-tokens.py --emit-bash`.
- Produces: `qol_init_color()`, `_term_cols()`, `_repeat(char, n)`, `_log_line(ink, badge, text)`, `log_phase(title)`, `banner(title, [subtitle])`, `log_complete(title)`, `log_ask(text)`, `log_next(text)`; variables `QOL_COLOR`, `QOL_DEPTH`, `QOL_BOLD`, `QOL_RESET`, and the ten ink variables. `printline`, `style_text`, `format_font`, `log_title`, `fstring`, `log_info`, `log_step`, `log_ok`, `log_warn`, `log_err` keep their signatures.

Depth selection moves into a function so tests can force it. `QOL_FORCE_COLOR=1` turns color on when stdout is not a TTY — required for testing, and genuinely useful when piping to `less -R`. This is an addition to the spec; Step 8 records it in the note.

- [x] **Step 1: Write the failing test**

Create `tests/test-theme.sh`:

```bash
#!/usr/bin/env bash
# Test harness for the IT Dojo terminal theme in linux/base_functions.sh.
#
# No test framework by design — same rationale as test-install-nano.sh.
#
# Run: ./tests/test-theme.sh
set -uo pipefail

TESTS_RUN=0
TESTS_FAILED=0
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/linux/base_functions.sh"

# shellcheck source=/dev/null
source "$LIB"

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$expected" == "$actual" ]]; then
        printf '  ok   %s\n' "$label"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' \
            "$label" "$expected" "$actual"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '  ok   %s\n' "$label"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s\n       missing substring: %s\n' "$label" "$needle"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        printf '  ok   %s\n' "$label"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s\n       unexpected substring: %s\n' "$label" "$needle"
    fi
}

# ‒‒ prefix arithmetic ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
printf '\nprefix is 9 columns for every badge\n'
QOL_COLOR_DEPTH=none qol_init_color
for pair in "log_step:STEP" "log_ok:PASS" "log_info:INFO" "log_warn:WARN" \
            "log_ask:ASK" "log_next:NEXT"; do
    fn="${pair%%:*}"; badge="${pair##*:}"
    line="$("$fn" "X")"
    assert_eq "▌ $(printf '%-4s' "$badge")   X" "$line" "$fn emits a 9-column prefix"
done
line="$(log_err "X" 2>&1)"
assert_eq "▌ STOP   X" "$line" "log_err emits a 9-column prefix"

printf '\nmessage text starts at column 10\n'
line="$(log_step "MSG")"
assert_eq "MSG" "${line:9}" "column 10 onward is the message"

# ‒‒ stderr routing ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
printf '\nlog_err goes to stderr, nothing else does\n'
assert_eq "" "$(log_err "X" 2>/dev/null)" "log_err writes nothing to stdout"
assert_eq "" "$(log_warn "X" 2>&1 1>/dev/null)" "log_warn writes nothing to stderr"

# ‒‒ depth tiers ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
printf '\ndepth tiers emit the right escapes\n'
QOL_FORCE_COLOR=1 QOL_COLOR_DEPTH=truecolor qol_init_color
assert_contains "$(log_step X)" $'\033[38;2;188;176;232m' "truecolor STEP is 188;176;232"
assert_contains "$(log_ok X)"   $'\033[38;2;78;206;106m'  "truecolor PASS is 78;206;106"

QOL_FORCE_COLOR=1 QOL_COLOR_DEPTH=256 qol_init_color
assert_contains "$(log_step X)" $'\033[38;5;140m' "256 STEP is index 140"
assert_contains "$(log_ok X)"   $'\033[38;5;77m'  "256 PASS is index 77"

QOL_FORCE_COLOR=1 QOL_COLOR_DEPTH=8 qol_init_color
assert_contains "$(log_step X)" $'\033[94m' "8-color STEP is bright blue"
assert_contains "$(log_err X 2>&1)" $'\033[91m' "8-color STOP is bright red"

QOL_COLOR_DEPTH=none qol_init_color
assert_not_contains "$(log_step X)" $'\033[' "none emits no escapes at all"

printf '\nNO_COLOR wins over a forced depth\n'
NO_COLOR=1 QOL_COLOR_DEPTH=truecolor qol_init_color
assert_not_contains "$(log_step X)" $'\033[' "NO_COLOR suppresses color"
unset NO_COLOR

# ‒‒ gutter survives every tier ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
printf '\nthe gutter bar prints at every depth\n'
for d in truecolor 256 8 none; do
    QOL_FORCE_COLOR=1 QOL_COLOR_DEPTH="$d" qol_init_color
    assert_contains "$(log_step X)" "▌" "gutter present at depth=$d"
done

# ‒‒ back-compat ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
printf '\nthe old style_text color names still resolve\n'
QOL_FORCE_COLOR=1 QOL_COLOR_DEPTH=256 qol_init_color
assert_contains "$(style_text hi normal green)"  $'\033[38;5;77m'  "green aliases jade"
assert_contains "$(style_text hi normal red)"    $'\033[38;5;168m' "red aliases wine"
assert_contains "$(style_text hi normal yellow)" $'\033[38;5;179m' "yellow aliases saffron"
assert_contains "$(style_text hi normal blue)"   $'\033[38;5;110m' "blue aliases steel"
assert_contains "$(style_text hi normal violet)" $'\033[38;5;140m' "violet is addressable by name"

printf '\nstyle_text still honors weight independently of ink\n'
assert_not_contains "$(style_text hi normal green)" $'\033[1m' "normal weight is not bold"
assert_contains     "$(style_text hi bold green)"   $'\033[1m' "bold weight is bold"

printf '\nfstring still dispatches\n'
QOL_COLOR_DEPTH=none qol_init_color
assert_eq "▌ PASS   done" "$(fstring done success)" "fstring success maps to PASS"
assert_eq "▌ WARN   careful" "$(fstring careful warning)" "fstring warning maps to WARN"

printf '\ncheck_status still reports through the new helpers\n'
assert_eq "▌ PASS   Thing: SUCCESS" "$(check_status "Thing" 0)" "check_status 0 is PASS"
assert_contains "$(check_status "Thing" 3 2>&1)" "▌ STOP   Thing: FAILED (exit 3)" "check_status nonzero is STOP"

# ‒‒ helpers ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
printf '\n_repeat builds fills\n'
assert_eq "─────" "$(_repeat '─' 5)" "_repeat emits n copies"
assert_eq "" "$(_repeat '─' 0)" "_repeat 0 is empty"
assert_eq "" "$(_repeat '─' -3)" "_repeat negative is empty"

printf '\nno function shadows a bash builtin\n'
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$(type -t complete)" == "builtin" ]]; then
    printf '  ok   complete is still the bash builtin\n'
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL complete was shadowed by a function\n'
fi

printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ "$TESTS_FAILED" -eq 0 ]]
```

- [x] **Step 2: Run it to make sure it fails**

```bash
cd ~/projects/qol && chmod +x tests/test-theme.sh && ./tests/test-theme.sh
```

Expected: FAIL — `qol_init_color: command not found`, and every badge assertion failing because the current helpers emit `📦  X` rather than `▌ STEP   X`.

- [x] **Step 3: Replace the theme block**

In `linux/base_functions.sh`, replace everything from the `# Pretty output — repo-standard theme` fence header (line 25) through the closing `}` of `log_title` (line 108) with the following. Keep the surrounding `# shellcheck shell=bash` header and everything from the `Back-compat: the old fstring API` fence onward.

```bash
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Pretty output — IT Dojo terminal design system
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Palette and rules:
#   ~/vaults/dojobrain/30-references/design-system/itdojo-terminal-design-system.md
# The ink case block below is GENERATED. Re-emit it rather than hand-editing:
#   cd ~/vaults/dojobrain && uv run scripts/build-design-tokens.py --emit-bash
# Keep this whole section byte-identical to the copy in install_zsh_starship.sh.

# Decide color and depth once. Re-callable so tests can force a tier.
#   NO_COLOR         — set to disable color entirely (wins over everything)
#   QOL_FORCE_COLOR  — set to keep color when stdout is not a TTY (e.g. less -R)
#   QOL_COLOR_DEPTH  — truecolor (default) | 256 | 8 | none
qol_init_color() {
    if [[ -n "${NO_COLOR:-}" ]]; then
        QOL_COLOR=""
    elif [[ -n "${QOL_FORCE_COLOR:-}" || -t 1 ]]; then
        QOL_COLOR=1
    else
        QOL_COLOR=""
    fi

    case "${QOL_COLOR_DEPTH:-truecolor}" in
        256)  QOL_DEPTH=256 ;;
        8)    QOL_DEPTH=8 ;;
        none) QOL_DEPTH=none ;;
        *)    QOL_DEPTH=truecolor ;;
    esac
    [[ -z "$QOL_COLOR" ]] && QOL_DEPTH=none

# ‒‒ generated by dojobrain scripts/build-design-tokens.py --emit-bash
# ‒‒ do not hand-edit; edit tokens/colors.css and re-emit.
    case "$QOL_DEPTH" in
        truecolor)
            QOL_STEP=$'\033[38;2;188;176;232m'
            QOL_PASS=$'\033[38;2;78;206;106m'
            QOL_INFO=$'\033[38;2;122;160;216m'
            QOL_WARN=$'\033[38;2;224;180;90m'
            QOL_STOP=$'\033[38;2;224;107;130m'
            QOL_FG=$'\033[38;2;228;222;245m'
            QOL_META=$'\033[38;2;154;147;181m'
            QOL_RULE=$'\033[38;2;74;65;112m'
            QOL_SEL=$'\033[48;2;36;29;61m'
            QOL_OKBG=$'\033[48;2;21;50;31m'
            ;;
        256)
            QOL_STEP=$'\033[38;5;140m'
            QOL_PASS=$'\033[38;5;77m'
            QOL_INFO=$'\033[38;5;110m'
            QOL_WARN=$'\033[38;5;179m'
            QOL_STOP=$'\033[38;5;168m'
            QOL_FG=$'\033[38;5;189m'
            QOL_META=$'\033[38;5;103m'
            QOL_RULE=$'\033[38;5;60m'
            QOL_SEL=$'\033[48;5;235m'
            QOL_OKBG=$'\033[48;5;22m'
            ;;
        8)
            QOL_STEP=$'\033[94m'
            QOL_PASS=$'\033[92m'
            QOL_INFO=$'\033[94m'
            QOL_WARN=$'\033[93m'
            QOL_STOP=$'\033[91m'
            QOL_FG=$'\033[97m'
            QOL_META=$'\033[90m'
            QOL_RULE=$'\033[90m'
            QOL_SEL=$'\033[7m'
            QOL_OKBG=$'\033[7m'
            ;;
        *)
            QOL_STEP="" QOL_PASS="" QOL_INFO="" QOL_WARN="" QOL_STOP="" QOL_FG="" QOL_META="" QOL_RULE="" QOL_SEL="" QOL_OKBG=""
            ;;
    esac
# ‒‒ end generated block

    if [[ "$QOL_DEPTH" == "none" ]]; then
        QOL_BOLD="" QOL_DIM="" QOL_RESET=""
    else
        QOL_BOLD=$'\033[1m'; QOL_DIM=$'\033[2m'; QOL_RESET=$'\033[0m'
    fi
}
qol_init_color

# Terminal width, falling back to 80 with no TTY (cron, CI, pipes).
_term_cols() {
    local cols
    cols="$(tput cols 2>/dev/null)" || cols=80
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
    printf '%s' "$cols"
}

# Repeat a character n times. Emits nothing for n <= 0.
_repeat() {
    local ch="$1" n="$2" line
    [[ "$n" =~ ^-?[0-9]+$ ]] || return 0
    (( n <= 0 )) && return 0
    printf -v line '%*s' "$n" ''
    printf '%s' "${line// /$ch}"
}

# One milestone line. The prefix is exactly 9 columns: gutter, space,
# 4-char badge, 3 spaces. Message text therefore starts at column 10.
_log_line() {
    local ink="$1" badge="$2" text="$3"
    printf '%s%s▌ %-4s   %s%s\n' "$QOL_BOLD" "$ink" "$badge" "$text" "$QOL_RESET"
}

log_step() { _log_line "$QOL_STEP" STEP "$1"; }
log_ok()   { _log_line "$QOL_PASS" PASS "$1"; }
log_info() { _log_line "$QOL_INFO" INFO "$1"; }
log_warn() { _log_line "$QOL_WARN" WARN "$1"; }
log_err()  { _log_line "$QOL_STOP" STOP "$1" >&2; }
log_ask()  { _log_line "$QOL_STEP" ASK  "$1"; }
log_next() { _log_line "$QOL_INFO" NEXT "$1"; }

# Phase boundary: a gray rule carrying the phase name in violet. A rule now
# means "new phase", which is information; a rule per line meant nothing.
log_phase() {
    local title="$1" cols fill
    cols="$(_term_cols)"
    fill=$(( cols - ${#title} - 4 ))
    printf '\n%s──%s %s%s%s%s %s%s\n\n' \
        "$QOL_RULE" "$QOL_RESET" \
        "$QOL_BOLD$QOL_STEP" "$title" "$QOL_RESET" \
        "$QOL_RULE" "$(_repeat '─' "$fill")" "$QOL_RESET"
}

# Run bookends. Jade rules, so a run's edges are findable when scrolling
# back through screens of package-manager output; phase rules are gray.
banner() {
    local title="$1" sub="${2:-}" cols
    cols="$(_term_cols)"
    printf '%s%s%s\n' "$QOL_PASS" "$(_repeat '━' "$cols")" "$QOL_RESET"
    printf '  %s%s⛩ %s ⛩%s' "$QOL_BOLD" "$QOL_PASS" "$title" "$QOL_RESET"
    [[ -n "$sub" ]] && printf '   %s%s%s' "$QOL_META" "$sub" "$QOL_RESET"
    printf '\n%s%s%s\n' "$QOL_PASS" "$(_repeat '━' "$cols")" "$QOL_RESET"
}

# NOTE: not named `complete` — that is a bash builtin.
log_complete() {
    local title="$1" cols
    cols="$(_term_cols)"
    printf '\n%s%s%s\n' "$QOL_PASS" "$(_repeat '━' "$cols")" "$QOL_RESET"
    printf '  %s%s%s ⛩ %s ⛩ %s\n' "$QOL_OKBG" "$QOL_BOLD" "$QOL_PASS" "$title" "$QOL_RESET"
    printf '%s%s%s\n\n' "$QOL_PASS" "$(_repeat '━' "$cols")" "$QOL_RESET"
}

# ‒‒ Back-compat ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Eight other scripts call these. Kept working, not kept identical: printline
# no longer appears in any log_* line, because the design uses phase rules.

# Print a separator line the width of the terminal.
# Usage: printline [solid|bullet|ibeam|star|plus|diamond|dentistry]
printline() {
    local sep
    case "${1:-solid}" in
        bullet)    sep="•" ;;
        ibeam)     sep="⌶" ;;
        star)      sep="★" ;;
        plus)      sep="✛" ;;
        diamond)   sep="◆" ;;
        dentistry) sep="⏥" ;;
        *)         sep="─" ;;
    esac
    printf '%s%s%s\n' "$QOL_RULE" "$(_repeat "$sep" "$(_term_cols)")" "$QOL_RESET"
}

# Print styled text with no separator. Also usable inline via command
# substitution: echo "I am a $(style_text "Raspberry Pi" bold wine)."
# Usage: style_text "text" [normal|bold|light] [brand or legacy color name]
# Brand names:  violet jade steel saffron wine prose meta rule
# Legacy names: blue   green  —     yellow  red   —     —    —
style_text() {
    local text="$1" weight="${2:-normal}" color="${3:-}"
    local wt="" ink=""
    case "$weight" in
        bold)  wt="$QOL_BOLD" ;;
        light) wt="$QOL_DIM" ;;
    esac
    case "$color" in
        violet)        ink="$QOL_STEP" ;;
        jade|green)    ink="$QOL_PASS" ;;
        steel|blue)    ink="$QOL_INFO" ;;
        saffron|yellow) ink="$QOL_WARN" ;;
        wine|red)      ink="$QOL_STOP" ;;
        prose)         ink="$QOL_FG" ;;
        meta)          ink="$QOL_META" ;;
        rule)          ink="$QOL_RULE" ;;
    esac
    if [[ -z "$QOL_COLOR" ]] || [[ -z "$ink" && -z "$wt" ]]; then
        printf '%s\n' "$text"
        return 0
    fi
    printf '%s%s%s%s\n' "$wt" "$ink" "$text" "$QOL_RESET"
}

# Separator + styled text. Retained for callers that predate log_phase;
# new code should use log_phase or a log_* helper instead.
format_font() {
    printline
    style_text "$1" "${2:-bold}" "${3:-saffron}"
}

# Banner for script titles. Prefer banner/log_complete in new code.
log_title() {
    local cols
    cols="$(_term_cols)"
    printf '%s%s%s\n' "$QOL_PASS" "$(_repeat '━' "$cols")" "$QOL_RESET"
    style_text "$1" bold jade
    printf '%s%s%s\n' "$QOL_PASS" "$(_repeat '━' "$cols")" "$QOL_RESET"
}
```

- [x] **Step 4: Run the tests**

```bash
cd ~/projects/qol && ./tests/test-theme.sh
```

Expected: every line `ok`, final line `N run, 0 failed`, exit 0.

- [x] **Step 5: Lint the file**

```bash
cd ~/projects/qol && shellcheck -x linux/base_functions.sh
```

Expected: no output. If `shellcheck` is not installed, skip this step and say so — it is not a gate.

- [x] **Step 6: Confirm the vault drift check now sees matching values**

```bash
cd ~/vaults/dojobrain && uv run scripts/build-design-tokens.py --check; echo "exit=$?"
```

Expected: no `DRIFT in ~/projects/qol` section, `exit=0`. The triplets in `base_functions.sh` now match `tokens/`.

- [x] **Step 7: Confirm the generated block is byte-identical to the emitter's output**

```bash
cd ~/vaults/dojobrain && uv run scripts/build-design-tokens.py --emit-bash > /tmp/emitted.txt
cd ~/projects/qol && sed -n '/^# ‒‒ generated by dojobrain/,/^# ‒‒ end generated block/p' linux/base_functions.sh \
  | sed '$d' | sed 's/^    //' > /tmp/inrepo.txt
diff <(sed 's/^ *//' /tmp/emitted.txt) <(sed 's/^ *//' /tmp/inrepo.txt) && echo "IDENTICAL"
```

Expected: `IDENTICAL`. If they differ, replace the in-repo block with the emitter's output rather than editing by hand.

- [x] **Step 8: Record the two spec additions in the vault note**

`QOL_FORCE_COLOR` and the `qol_init_color` re-callability are not in the note. In `~/vaults/dojobrain/30-references/design-system/itdojo-terminal-design-system.md`, find the paragraph beginning "Emit truecolor whenever color is on at all." and append this sentence to it:

```
`NO_COLOR` wins over everything; `QOL_FORCE_COLOR` keeps color on when stdout is not a TTY, which is what makes the tier testable and what makes `| less -R` usable.
```

- [x] **Step 9: Commit**

```bash
cd ~/projects/qol
git add linux/base_functions.sh tests/test-theme.sh
git commit -m "feat: rebrand the output theme to the IT Dojo terminal palette

Gutter bar plus a 4-char badge, 9 columns of prefix, replacing the emoji
markers whose widths needed a padding table and whose red X the brand
forbids. Depth is truecolor by default with QOL_COLOR_DEPTH to force down;
detection is not attempted because SSH strips COLORTERM.

log_* names and style_text's old color words keep working — eight other
scripts call them."
```

```bash
cd ~/vaults/dojobrain
git add 30-references/design-system/itdojo-terminal-design-system.md
git commit -m "docs: record QOL_FORCE_COLOR in the terminal design system"
```

---

### Task 4: Sync the theme block into install_zsh_starship.sh

**Files:**
- Modify: `~/projects/qol/install_zsh_starship.sh:55-127`
- Create: `~/projects/qol/tests/test-theme-sync.sh`

**Interfaces:**
- Consumes: the theme section written in Task 3.
- Produces: an identical theme section in `install_zsh_starship.sh`, and a test that fails whenever the two drift apart.

This script must run on macOS, where `linux/base_functions.sh` is unavailable, so it embeds a copy. The copy is the failure mode this task guards.

- [x] **Step 1: Write the failing test**

Create `tests/test-theme-sync.sh`:

```bash
#!/usr/bin/env bash
# Proves the two copies of the theme block have not drifted.
#
# install_zsh_starship.sh must run on macOS, where linux/base_functions.sh is
# unavailable, so it embeds a copy. This test is the only thing keeping that
# copy honest.
#
# Run: ./tests/test-theme-sync.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/linux/base_functions.sh"
EMBED="$ROOT/install_zsh_starship.sh"

# The theme section runs from the qol_init_color definition through the
# closing brace of log_title.
extract() {
    sed -n '/^qol_init_color() {/,/^# ‒‒ end theme block/p' "$1"
}

a="$(extract "$LIB")"
b="$(extract "$EMBED")"

if [[ -z "$a" ]]; then
    printf 'FAIL no theme block found in %s\n' "$LIB"
    exit 1
fi
if [[ -z "$b" ]]; then
    printf 'FAIL no theme block found in %s\n' "$EMBED"
    exit 1
fi
if [[ "$a" == "$b" ]]; then
    printf '  ok   theme block is identical in both files (%d lines)\n' "$(printf '%s\n' "$a" | wc -l | tr -d ' ')"
    printf '\n1 run, 0 failed\n'
    exit 0
fi

printf '  FAIL theme block has drifted\n'
diff <(printf '%s\n' "$a") <(printf '%s\n' "$b")
printf '\n1 run, 1 failed\n'
exit 1
```

- [x] **Step 2: Add the end marker to base_functions.sh**

The test needs a terminator. In `linux/base_functions.sh`, immediately after the closing `}` of `log_title`, add:

```bash
# ‒‒ end theme block
```

- [x] **Step 3: Run the test to verify it fails**

```bash
cd ~/projects/qol && chmod +x tests/test-theme-sync.sh && ./tests/test-theme-sync.sh
```

Expected: `FAIL no theme block found in .../install_zsh_starship.sh`, exit 1.

- [x] **Step 4: Replace the embedded block**

In `install_zsh_starship.sh`, delete lines 55 through 127 — the fence header `PRETTY OUTPUT — (KEEP IN SYNC WITH LINUX/BASE_FUNCTIONS.SH)` through the `log_err` definition. In its place, paste the fence header below followed by the exact text from `linux/base_functions.sh` running from `qol_init_color() {` through `# ‒‒ end theme block` inclusive:

```bash
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
#                   PRETTY OUTPUT — (KEEP IN SYNC WITH LINUX/BASE_FUNCTIONS.SH)
# ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Verified identical to linux/base_functions.sh by tests/test-theme-sync.sh.
```

Do the copy mechanically rather than retyping:

```bash
cd ~/projects/qol && sed -n '/^qol_init_color() {/,/^# ‒‒ end theme block/p' linux/base_functions.sh > /tmp/theme-block.sh
wc -l /tmp/theme-block.sh
```

Then paste `/tmp/theme-block.sh` verbatim below the fence header.

- [x] **Step 5: Run the sync test**

```bash
cd ~/projects/qol && ./tests/test-theme-sync.sh
```

Expected: `ok   theme block is identical in both files (N lines)`, `1 run, 0 failed`, exit 0.

- [x] **Step 6: Verify the script still parses and its helpers work**

```bash
cd ~/projects/qol && bash -n install_zsh_starship.sh && echo "PARSE OK"
QOL_COLOR_DEPTH=none bash -c 'source <(sed -n "/^qol_init_color() {/,/^# ‒‒ end theme block/p" install_zsh_starship.sh); log_step "probe"'
```

Expected: `PARSE OK`, then `▌ STEP   probe`.

- [x] **Step 7: Verify the vault drift check still passes**

```bash
cd ~/vaults/dojobrain && uv run scripts/build-design-tokens.py --check; echo "exit=$?"
```

Expected: `exit=0`. Both qol files now carry matching triplets.

- [x] **Step 8: Commit**

```bash
cd ~/projects/qol
git add install_zsh_starship.sh linux/base_functions.sh tests/test-theme-sync.sh
git commit -m "feat: sync the branded theme block into install_zsh_starship.sh

The macOS-capable script cannot source the Linux-only library, so it
embeds a copy. test-theme-sync.sh is what keeps that copy honest."
```

---

### Task 5: Give docker_install.sh phases and bookends

**Files:**
- Modify: `~/projects/qol/linux/docker_install.sh`

**Interfaces:**
- Consumes: `banner`, `log_phase`, `log_complete`, `log_next` from Task 3, reached by sourcing `base_functions.sh`.
- Produces: nothing other tasks depend on.

The 45 existing `log_*` and `check_status` calls already render in brand — they inherit from the library. This task adds the structure the new design expects and removes the hash-wall that predates it.

- [x] **Step 1: Find the current bookends**

```bash
cd ~/projects/qol && grep -n '#####\|log_title\|^main()' linux/docker_install.sh
```

Record the line numbers. The closing hash-wall and `DOCKER INSTALLER COMPLETE` text are what Step 3 replaces.

- [x] **Step 2: Add the opening banner**

Find the first executable line inside `main()`. Insert immediately after it:

```bash
    banner "DOCKER INSTALLER" "engine · compose · buildx"
```

- [x] **Step 3: Replace the closing hash-wall**

Delete the `printf`/`echo` lines that draw the `#####` wall and the `DOCKER INSTALLER COMPLETE` line. In their place:

```bash
    log_complete "DOCKER INSTALLER COMPLETE"
    log_next "Log out and back in to use Docker without sudo."
    log_next "Or apply the group to this shell now:  newgrp docker"
```

- [x] **Step 4: Add phase rules**

Insert a `log_phase` call before each group of related work in `main()`. Use exactly these five, in this order, each on its own line immediately before the first call of its group:

```bash
    log_phase "PREFLIGHT"
    log_phase "REPOSITORY"
    log_phase "DOCKER ENGINE"
    log_phase "SERVICE"
    log_phase "VERIFY"
```

`PREFLIGHT` goes before the root and package-manager checks; `REPOSITORY` before the GPG key and apt-source work; `DOCKER ENGINE` before `install_packages`; `SERVICE` before the kernel-module and systemd work; `VERIFY` before `docker_smoke_test`.

- [x] **Step 5: Verify it parses**

```bash
cd ~/projects/qol && bash -n linux/docker_install.sh && echo "PARSE OK"
```

Expected: `PARSE OK`.

- [x] **Step 6: Verify the structure renders**

```bash
cd ~/projects/qol && QOL_FORCE_COLOR=1 bash -c '
source linux/base_functions.sh
banner "DOCKER INSTALLER" "engine · compose · buildx"
log_phase "DOCKER ENGINE"
log_step "Installing docker-ce docker-ce-cli containerd.io..."
log_ok "docker-ce docker-ce-cli containerd.io are installed."
log_complete "DOCKER INSTALLER COMPLETE"
log_next "Log out and back in to use Docker without sudo."'
```

Expected: jade rules around a `⛩ DOCKER INSTALLER ⛩` banner, a gray `── DOCKER ENGINE ──` rule, two 9-column milestone lines, and a jade-ruled completion block. Compare against the rendered reference at `~/vaults/dojobrain/30-references/design-system/itdojo-terminal-design-system.html`.

- [x] **Step 7: Confirm no emoji survive**

```bash
cd ~/projects/qol && grep -n '✅\|📦\|ℹ️\|⚠️\|❌' linux/docker_install.sh
```

Expected: no output.

- [x] **Step 8: Commit**

```bash
cd ~/projects/qol
git add linux/docker_install.sh
git commit -m "feat: give docker_install.sh phase rules and branded bookends

Five phases replace the per-line separators; the hash-wall becomes a
jade-ruled completion block. The 45 log_* calls needed no change — they
inherit the palette from base_functions.sh."
```

---

### Task 6: Give install_zsh_starship.sh phases and bookends

**Files:**
- Modify: `~/projects/qol/install_zsh_starship.sh`

**Interfaces:**
- Consumes: `banner`, `log_phase`, `log_complete`, `log_next` from the block embedded in Task 4.
- Produces: nothing other tasks depend on.

The script's current ending is the blue-block-then-green-line pattern from the old house style. That pattern is what `log_next` plus `log_complete` now express.

- [x] **Step 1: Add the opening banner**

Find the first executable line inside `main()`. Insert immediately after it:

```bash
    banner "ZSH + STARSHIP" "shell · prompt · fonts · plugins"
```

- [x] **Step 2: Add phase rules**

Insert these five, each immediately before the first call of its group in `main()`:

```bash
    log_phase "PREFLIGHT"
    log_phase "PACKAGES"
    log_phase "FONTS"
    log_phase "CONFIG"
    log_phase "DEFAULT SHELL"
```

`PREFLIGHT` before the root check and package-manager detection; `PACKAGES` before the zsh/starship/plugin installs; `FONTS` before the Nerd Font download; `CONFIG` before the `starship.toml` and `.zshrc` writes; `DEFAULT SHELL` before the `chsh` work.

- [x] **Step 3: Replace the closing block**

Find the ending in `main()` — the `format_font` pair that prints next-steps in blue then a green completion line. Replace both calls with:

```bash
    log_complete "ZSH + STARSHIP INSTALLED"
    log_next "Prompt config:  ~/.config/starship.toml   (docs: https://starship.rs/config/)"
    log_next "Git aliases:    ~/.config/zsh/git-aliases.zsh"
    log_next "Plugins:        ~/.zsh/plugins/"
    log_next "If glyphs render as boxes, set your terminal font to 'MesloLGS NF'."
    log_next "Restart your terminal to pick up the new shell."
    echo
```

- [x] **Step 4: Verify it parses**

```bash
cd ~/projects/qol && bash -n install_zsh_starship.sh && echo "PARSE OK"
```

Expected: `PARSE OK`.

- [x] **Step 5: Confirm no emoji survive**

```bash
cd ~/projects/qol && grep -n '✅\|📦\|ℹ️\|⚠️\|❌' install_zsh_starship.sh
```

Expected: no output.

- [x] **Step 6: Confirm the sync test still passes**

Steps 1–3 touched only `main()`, never the theme block, so this must still hold:

```bash
cd ~/projects/qol && ./tests/test-theme-sync.sh && ./tests/test-theme.sh
```

Expected: both `0 failed`.

- [x] **Step 7: Commit**

```bash
cd ~/projects/qol
git add install_zsh_starship.sh
git commit -m "feat: give install_zsh_starship.sh phase rules and branded bookends

The blue-next-steps-then-green-line ending becomes log_complete plus
log_next lines, which is what that pattern was always describing."
```

---

### Task 7: Rebrand gotime

**Files:**
- Modify: `~/projects/qol/gotime:53-70` (palette), `:110-156` (chrome), and the two emoji in `attach_session`/`launch`

**Interfaces:**
- Consumes: the ink values from Task 1, by hand-copy — `gotime` is standalone and sources nothing.
- Produces: nothing other tasks depend on.

`gotime` keeps its own palette block because it sources no library. Variable names stay `C_*` so the ~30 existing `printf` call sites need no edits; only the values and the chrome change.

- [x] **Step 1: Replace the palette**

Replace lines 53–70 — the `# --- colors ---` block — with:

```bash
# --- colors -----------------------------------------------------------------
# IT Dojo terminal design system. Palette and rules:
#   ~/vaults/dojobrain/30-references/design-system/itdojo-terminal-design-system.md
# Truecolor by default; QOL_COLOR_DEPTH=256|8|none forces down. Detection is
# not attempted — SSH strips COLORTERM, so it would always guess low.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    case "${QOL_COLOR_DEPTH:-truecolor}" in
        256)
            C_JADE=$'\033[38;5;77m'
            C_VIOLET=$'\033[38;5;140m'
            C_STEEL=$'\033[38;5;110m'
            C_SAFFRON=$'\033[38;5;179m'
            C_FG=$'\033[38;5;189m'
            C_META=$'\033[38;5;103m'
            C_RULE=$'\033[38;5;60m'
            SEL_BG=$'\033[48;5;235m'
            ;;
        8)
            C_JADE=$'\033[92m'
            C_VIOLET=$'\033[94m'
            C_STEEL=$'\033[94m'
            C_SAFFRON=$'\033[93m'
            C_FG=$'\033[97m'
            C_META=$'\033[90m'
            C_RULE=$'\033[90m'
            SEL_BG=$'\033[7m'
            ;;
        none)
            C_JADE="" C_VIOLET="" C_STEEL="" C_SAFFRON=""
            C_FG="" C_META="" C_RULE="" SEL_BG=""
            ;;
        *)
            C_JADE=$'\033[38;2;78;206;106m'
            C_VIOLET=$'\033[38;2;188;176;232m'
            C_STEEL=$'\033[38;2;122;160;216m'
            C_SAFFRON=$'\033[38;2;224;180;90m'
            C_FG=$'\033[38;2;228;222;245m'
            C_META=$'\033[38;2;154;147;181m'
            C_RULE=$'\033[38;2;74;65;112m'
            SEL_BG=$'\033[48;2;36;29;61m'
            ;;
    esac
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    CLR_EOL=$'\033[K'
else
    C_RESET="" C_BOLD="" C_DIM="" C_FG="" C_JADE="" C_VIOLET="" C_STEEL=""
    C_SAFFRON="" C_META="" C_RULE="" SEL_BG="" CLR_EOL=""
fi
```

- [x] **Step 2: Retarget the old color names**

The old names `C_CYAN`, `C_BLUE`, `C_PURPLE`, `C_YELLOW` are gone. Rename every remaining use:

```bash
cd ~/projects/qol
sed -i.bak 's/\$C_CYAN/$C_JADE/g; s/\$C_BLUE/$C_RULE/g; s/\$C_PURPLE/$C_VIOLET/g; s/\$C_YELLOW/$C_SAFFRON/g' gotime
sed -i.bak2 's/"\$C_CYAN"/"$C_JADE"/g; s/"\$C_BLUE"/"$C_RULE"/g; s/"\$C_PURPLE"/"$C_VIOLET"/g; s/"\$C_YELLOW"/"$C_SAFFRON"/g' gotime
rm -f gotime.bak gotime.bak2
grep -n 'C_CYAN\|C_BLUE\|C_PURPLE\|C_YELLOW' gotime
```

Expected from the final `grep`: no output.

- [x] **Step 3: Swap the crest in the banner**

In `banner()`, replace the `⚡ GO TIME ⚡` printf with:

```bash
    printf '   %s⛩ GO TIME ⛩%s   %spick a workspace — launch the session%s\n' \
        "$C_JADE$C_BOLD" "$C_RESET" "$C_META" "$C_RESET"
```

The `$C_DIM` on the subtitle becomes `$C_META` — dim on a dim color compounds into unreadability.

- [x] **Step 4: Recolor the unselected row**

In `render_row()`, the unselected branch currently dims the number and prints the name in `$C_FG`. Replace that branch with:

```bash
        printf '   %s%s%s  %s %s%s%s\n' \
            "$C_META" "$num" "$C_RESET" "$icon" "$C_FG" "$name" "$C_RESET"
```

- [x] **Step 5: Recolor the footer**

In `footer()`, replace the two `printf` calls with:

```bash
    printf ' %s↑/↓%s or %sj/k%s move   %s1-9%s jump   %s⏎%s start   %sq%s quit\n' \
        "$C_JADE" "$C_RESET" "$C_JADE" "$C_RESET" "$C_JADE" "$C_RESET" \
        "$C_JADE" "$C_RESET" "$C_JADE" "$C_RESET"
    printf ' %swindows:%s dojobrain · %s%s%s · local     %s%s%s' \
        "$C_META" "$C_RESET" "$C_BOLD$C_JADE" "${NAMES[$sel]}" "$C_RESET" \
        "$C_META" "$tgt" "$C_RESET"
    [[ -n "$numbuf" ]] && printf '   %s[%s]%s' "$C_VIOLET" "$numbuf" "$C_RESET"
```

- [x] **Step 6: Replace the two stray emoji**

In `attach_session()`:

```bash
        printf '%s▌ PASS   session "%s" ready%s (not attaching).\n' "$C_JADE" "$s" "$C_RESET"
```

In `launch()`, the `⚠` line becomes:

```bash
    [[ -d "$dj" ]] || { printf '%s▌ WARN   %s not found; window 1 will open in ~ instead.%s\n' \
```

Keep the rest of that statement as it is.

- [x] **Step 7: Verify it parses and renders**

```bash
cd ~/projects/qol && bash -n gotime && echo "PARSE OK"
```

Expected: `PARSE OK`.

- [x] **Step 8: Run it and compare against the reference**  <!-- verified 2026-08-08 from a screen recording; surfaced the redraw flicker (c7dc1e6) and the 80-column ceiling (b1f0499); re-confirmed after both -->

```bash
cd ~/projects/qol && ./gotime
```

Expected: jade rules, a `⛩ GO TIME ⛩` banner, violet `COURSES` / `PROJECTS` headings, a jade-on-`#241D3D` selection bar, and jade keycaps in the footer. Press `q` to quit. Compare against the Interactive section of the rendered reference.

- [x] **Step 9: Verify the 256 tier renders**  <!-- verified 2026-08-08; sampled colors match the xterm-256 palette, fg and sel-bg exactly -->

```bash
cd ~/projects/qol && QOL_COLOR_DEPTH=256 ./gotime
```

Expected: the same layout with slightly flatter colors. Press `q`.

- [x] **Step 10: Commit**  <!-- 56733bb; steps 8-9 (visual, needs a human at a terminal) still open -->

```bash
cd ~/projects/qol
git add gotime
git commit -m "feat: rebrand gotime to the IT Dojo terminal palette

The fzf-derived cyan and blue are replaced by jade and violet; ⚡ becomes
the ⛩ crest. Variable names stay C_* so the ~30 printf call sites are
untouched — only values and chrome changed."
```

---

### Task 8: Build the three question shapes

**Files:**
- Modify: `~/projects/qol/linux/base_functions.sh` (append to the theme block, before `# ‒‒ end theme block`)
- Modify: `~/projects/qol/install_zsh_starship.sh` (re-sync the copy)
- Modify: `~/projects/qol/tests/test-theme.sh` (append cases)

**Interfaces:**
- Consumes: `_log_line`, `QOL_STEP`, `QOL_PASS`, `QOL_META`, `QOL_FG`, `QOL_SEL`, `QOL_BOLD`, `QOL_RESET` from Task 3.
- Produces: `ask_confirm(question, [Y|N]) -> exit 0/1`; `ask_value(question, default, [hint]) -> echoes the answer`; `ask_choice(heading, default_index, "label|hint"...) -> echoes a 1-based index`; and the private `_read_key` setting `_KEY` and `_KEYCH`.

Prompts go to **stderr**, answers to **stdout**. `ask_value` and `ask_choice` are meant to be captured with `$(...)`, and a prompt written to stdout would land in the captured value.

`ask_choice` redraws in place with cursor-up rather than taking the alternate screen. `gotime` uses `tput smcup` because it is a launcher; an installer that blanks the scrollback mid-run has destroyed the record of what it just did.

- [x] **Step 1: Write the failing tests**

Append to `tests/test-theme.sh`, immediately before the final `printf '\n%d run, %d failed\n'` line:

```bash
# ‒‒ question shapes ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# stdin is not a TTY under the harness, so every helper takes its
# non-interactive path. That is the path cron and the test suite hit.
printf '\nnon-interactive questions return their defaults\n'
QOL_COLOR_DEPTH=none qol_init_color
unset ASSUME_YES

assert_eq "/var/lib/docker" "$(ask_value "Data root" "/var/lib/docker")" \
    "ask_value returns the default"
assert_eq "2" "$(ask_choice "DRIVER" 2 "overlay2|fast" "vfs|slow")" \
    "ask_choice returns the default index"
assert_fail 'ask_confirm "Proceed?" N' "ask_confirm default N is no"
assert_ok   'ask_confirm "Proceed?" Y' "ask_confirm default Y is yes"

printf '\nASSUME_YES forces the yes path\n'
assert_ok 'ASSUME_YES=1 ask_confirm "Proceed?" N' "ASSUME_YES overrides a No default"

printf '\nprompts go to stderr, answers to stdout\n'
assert_eq "" "$(ask_value "Q" "d" "hint" 2>/dev/null; true)" \
    "ask_value emits no prompt on stdout" || true
assert_eq "d" "$(ask_value "Q" "d" "hint" 2>/dev/null)" \
    "ask_value's stdout is the answer alone"
assert_not_contains "$(ask_choice "H" 1 "a|x" "b|y" 2>/dev/null)" "H" \
    "ask_choice's stdout carries no heading"

printf '\n_read_key decodes without a TTY\n'
_KEY=""; printf 'j' | { _read_key; }
assert_eq "DOWN" "$_KEY" "_read_key maps j to DOWN"
_KEY=""; printf 'k' | { _read_key; }
assert_eq "UP" "$_KEY" "_read_key maps k to UP"
_KEY=""; printf '3' | { _read_key; }
assert_eq "DIGIT" "$_KEY" "_read_key maps a digit to DIGIT"
assert_eq "3" "$_KEYCH" "_read_key records the digit character"
```

- [x] **Step 2: Run to verify it fails**

```bash
cd ~/projects/qol && ./tests/test-theme.sh
```

Expected: FAIL — `ask_value: command not found` and friends.

- [x] **Step 3: Implement the helpers**

In `linux/base_functions.sh`, insert this immediately before the `# ‒‒ end theme block` line:

```bash
# ‒‒ Interactive ‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒‒
# Three question shapes, sharing gotime's chrome. Prompts go to stderr so
# ask_value and ask_choice can be captured with $(...). All three skip the
# prompt and return the default when ASSUME_YES is set or stdin is not a
# TTY — the priority order install_nano.sh already follows.

# Decode one keypress into _KEY (and _KEYCH for digits). Bash 3.2 safe:
# no read -N, no fractional -t. Arrows arrive as ESC then "[A"/"OA".
_read_key() {
    local k s
    _KEY=""; _KEYCH=""
    IFS= read -rsn1 k || { _KEY="QUIT"; return; }
    if [[ -z "$k" ]]; then _KEY="ENTER"; return; fi
    case "$k" in
        $'\r'|$'\n') _KEY="ENTER" ;;
        $'\x1b')
            IFS= read -rsn2 -t 1 s
            case "$s" in
                '[A'|'OA') _KEY="UP" ;;
                '[B'|'OB') _KEY="DOWN" ;;
                '')        _KEY="QUIT" ;;
                *)         _KEY="OTHER" ;;
            esac ;;
        [0-9]) _KEY="DIGIT"; _KEYCH="$k" ;;
        k|K)   _KEY="UP" ;;
        j|J)   _KEY="DOWN" ;;
        q|Q)   _KEY="QUIT" ;;
        *)     _KEY="OTHER" ;;
    esac
}

# ask_confirm "question" [Y|N]  ->  exit 0 for yes, 1 for no
ask_confirm() {
    local q="$1" def="${2:-N}" hint reply
    if [[ -n "${ASSUME_YES:-}" ]]; then return 0; fi
    if [[ ! -t 0 ]]; then [[ "$def" == "Y" ]]; return $?; fi
    if [[ "$def" == "Y" ]]; then hint="Y/n"; else hint="y/N"; fi
    _log_line "$QOL_STEP" ASK "$q" >&2
    printf '    %s❯%s %s[%s]%s ' "$QOL_PASS" "$QOL_RESET" "$QOL_META" "$hint" "$QOL_RESET" >&2
    read -r reply
    reply="${reply:-$def}"
    case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# ask_value "question" "default" ["hint"]  ->  echoes the answer
ask_value() {
    local q="$1" def="$2" hint="${3:-}" reply
    if [[ -n "${ASSUME_YES:-}" || ! -t 0 ]]; then printf '%s' "$def"; return 0; fi
    _log_line "$QOL_STEP" ASK "$q" >&2
    [[ -n "$hint" ]] && printf '         %s%s%s\n' "$QOL_META" "$hint" "$QOL_RESET" >&2
    printf '    %s❯%s [%s%s%s] ' "$QOL_PASS" "$QOL_RESET" "$QOL_PASS" "$def" "$QOL_RESET" >&2
    read -r reply
    printf '%s' "${reply:-$def}"
}

# Draw the choice list. Emits exactly (count + 3) lines so the caller knows
# how far to move the cursor back up when redrawing.
_ask_choice_draw() {
    local heading="$1" sel="$2"; shift 2
    local i=0 item label hint
    printf '\n %s%s%s%s\n' "$QOL_BOLD" "$QOL_STEP" "$heading" "$QOL_RESET"
    for item in "$@"; do
        label="${item%%|*}"
        hint="${item#*|}"; [[ "$hint" == "$item" ]] && hint=""
        if (( i == sel )); then
            printf '%s%s%s ❯ %2d   %-18s %s%s\n' \
                "$QOL_SEL" "$QOL_BOLD" "$QOL_PASS" "$(( i + 1 ))" "$label" "$hint" "$QOL_RESET"
        else
            printf '   %s%2d%s   %s%-18s%s %s%s%s\n' \
                "$QOL_META" "$(( i + 1 ))" "$QOL_RESET" \
                "$QOL_FG" "$label" "$QOL_RESET" "$QOL_META" "$hint" "$QOL_RESET"
        fi
        i=$(( i + 1 ))
    done
    printf ' %s↑/↓%s or %sj/k%s move   %s1-9%s jump   %s⏎%s select\n' \
        "$QOL_PASS" "$QOL_RESET" "$QOL_PASS" "$QOL_RESET" \
        "$QOL_PASS" "$QOL_RESET" "$QOL_PASS" "$QOL_RESET"
}

# ask_choice "HEADING" default_index "label|hint" [...]  ->  echoes 1-based index
# Redraws in place rather than taking the alternate screen: an installer that
# blanks the scrollback has destroyed the record of what it just did.
ask_choice() {
    local heading="$1" def="$2"; shift 2
    local n=$# sel=$(( def - 1 ))
    if [[ -n "${ASSUME_YES:-}" || ! -t 0 ]]; then printf '%s' "$def"; return 0; fi
    _ask_choice_draw "$heading" "$sel" "$@" >&2
    while true; do
        _read_key
        case "$_KEY" in
            ENTER) break ;;
            QUIT)  sel=$(( def - 1 )); break ;;
            UP)    sel=$(( (sel - 1 + n) % n )) ;;
            DOWN)  sel=$(( (sel + 1) % n )) ;;
            DIGIT) (( 10#$_KEYCH >= 1 && 10#$_KEYCH <= n )) && sel=$(( 10#$_KEYCH - 1 )) ;;
        esac
        printf '\033[%dA' $(( n + 3 )) >&2
        _ask_choice_draw "$heading" "$sel" "$@" >&2
    done
    printf '%s' $(( sel + 1 ))
}
```

- [x] **Step 4: Run the tests**

```bash
cd ~/projects/qol && ./tests/test-theme.sh
```

Expected: `0 failed`.

- [x] **Step 5: Verify the arrow keys by hand**  <!-- verified 2026-08-08 after 13afa3a/b1f0499; bar measured spanning the full terminal, run returned driver=1 root=/var/lib/docker group=yes -->

Automated TTY testing is not worth building here, so drive it once manually:

```bash
cd ~/projects/qol && bash -c '
source linux/base_functions.sh
d=$(ask_choice "STORAGE DRIVER" 1 \
    "overlay2|recommended for ext4 / xfs" \
    "fuse-overlayfs|rootless installs" \
    "vfs|fallback — slow, no dedup")
r=$(ask_value "Data root directory" "/var/lib/docker" "where images and volumes live")
ask_confirm "Add itdojo to the docker group?" Y && g=yes || g=no
log_ok "Configured. driver=$d root=$r group=$g"'
```

Expected: arrows and `j`/`k` move the jade highlight bar without the list scrolling away or duplicating; digits jump; `⏎` selects; the final `PASS` line reports the three values. Compare against the Interactive section of the rendered reference.

- [x] **Step 6: Re-sync the embedded copy**

The theme block grew, so `install_zsh_starship.sh` is now stale:

```bash
cd ~/projects/qol && ./tests/test-theme-sync.sh
```

Expected: FAIL with a diff. Re-copy:

```bash
cd ~/projects/qol && sed -n '/^qol_init_color() {/,/^# ‒‒ end theme block/p' linux/base_functions.sh > /tmp/theme-block.sh
```

Replace the corresponding region of `install_zsh_starship.sh` with the contents of `/tmp/theme-block.sh`, then:

```bash
cd ~/projects/qol && ./tests/test-theme-sync.sh && bash -n install_zsh_starship.sh && echo "PARSE OK"
```

Expected: `0 failed` and `PARSE OK`.

- [x] **Step 7: Commit**  <!-- c109d31; step 5 (arrow keys by hand) still open -->

```bash
cd ~/projects/qol
git add linux/base_functions.sh install_zsh_starship.sh tests/test-theme.sh
git commit -m "feat: add the three question shapes

ask_confirm, ask_value, ask_choice, sharing gotime's chrome. Prompts go
to stderr so the captured value is the answer alone. ask_choice redraws
in place instead of taking the alternate screen — an installer that
blanks the scrollback has destroyed the record of what it just did."
```

---

### Task 9: Turn script-design.md's theme section into a pointer

**Files:**
- Modify: `~/projects/qol/script-design.md:59-107`

**Interfaces:**
- Consumes: everything above.
- Produces: the repo's authoritative bash contract, deferring to the vault for the palette.

The house style keeps the bash contract — function names, section layout, behavioral conventions. It stops describing colors, because a second description is a second thing to drift.

- [x] **Step 1: Replace the Output theme section**

Replace the `## Output theme` section and the `## STDOUT vocabulary and voice` section, through the end of `### Ending`, with the following. Note the outer fence is four backticks because the replacement text contains fenced blocks of its own — paste the inner content, not the outer fence.

````markdown
## Output theme

**The palette has one source of truth, and it is not this repo:** `~/vaults/dojobrain/30-references/design-system/itdojo-terminal-design-system.md`. The rendered reference beside it shows every surface at real hex values. Read it before changing anything about how a script looks.

**The theme text has one source of truth in this repo:** the `Pretty output` block in `linux/base_functions.sh`, running from `qol_init_color() {` to `# ‒‒ end theme block`. Copy it verbatim; never retype it, never restyle it per-script.

- Scripts that can run on **macOS** embed the block (self-contained — `linux/base_functions.sh` is Linux-only). `tests/test-theme-sync.sh` proves the copy has not drifted; run it after touching either file.
- Scripts under **`linux/`** source `base_functions.sh` instead (with the auto-download-from-GitHub fallback — see `linux/kernel_update.sh`).

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
| `printline` · `style_text` · `format_font` · `log_title` · `fstring` | Retained for the eight scripts that predate this design. New code should not call them. |

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

## Asking questions

Three shapes, all in `base_functions.sh`. Prompts go to **stderr**, answers to **stdout**, so `$(...)` capture returns the answer alone.

| Helper | Returns | Notes |
|---|---|---|
| `ask_confirm "q" [Y\|N]` | exit 0 = yes, 1 = no | Replaces the old `confirm()` pattern. |
| `ask_value "q" "default" ["hint"]` | echoes the answer | `⏎` accepts the default. |
| `ask_choice "HEADING" n "label\|hint" ...` | echoes a 1-based index | Arrow keys, `j`/`k`, digit jump, `⏎` selects. |

All three skip the prompt and return the default when `ASSUME_YES` is set or stdin is not a TTY, in that priority order. `ask_choice` redraws in place rather than taking the alternate screen — an installer that blanks the scrollback has destroyed the record of what it just did. Close a question sequence with a `log_ok` restating every collected value, so nothing installs before the user has seen what they agreed to.
````

- [x] **Step 2: Update the deprecated-emoji line in the New script checklist**

In the `## New script checklist` section, replace the line reading:

```markdown
- [ ] Step/ok pairs read `"...ing X..."` → `"X is installed."`; reruns narrate skips
```

with:

```markdown
- [ ] Step/ok pairs read `"...ing X..."` → `"X is installed."`; reruns narrate skips
- [ ] `main()` opens with `banner` and closes with `log_complete` + `log_next`; phases marked with `log_phase`
- [ ] No emoji anywhere in user-facing output — the badge carries the meaning
```

- [x] **Step 3: Verify no stale references remain**

```bash
cd ~/projects/qol && grep -n '✅\|📦\|ℹ️\|⚠️\|❌\|uneven emoji padding' script-design.md
```

Expected: no output.

- [x] **Step 4: Run the full test suite**

```bash
cd ~/projects/qol && ./tests/test-theme.sh && ./tests/test-theme-sync.sh && ./tests/test-install-nano.sh
```

Expected: all three end `0 failed`. `test-install-nano.sh` is the regression check — it sources `install_nano.sh`, which calls the retained back-compat helpers.

- [x] **Step 5: Verify the vault check is clean**

```bash
cd ~/vaults/dojobrain && uv run scripts/build-design-tokens.py --check; echo "exit=$?"
```

Expected: `exit=0`.

- [x] **Step 6: Commit**  <!-- d61454f -->

```bash
cd ~/projects/qol
git add script-design.md
git commit -m "docs: point the house style at the vault for the palette

The bash contract stays here; the colors move to the design system note.
A second description of the palette is a second thing to drift."
```

---

## Verification

After Task 9, the whole system holds when all of these pass:

```bash
cd ~/projects/qol && ./tests/test-theme.sh && ./tests/test-theme-sync.sh && ./tests/test-install-nano.sh
cd ~/projects/qol && bash -n gotime && bash -n install_zsh_starship.sh && bash -n linux/docker_install.sh && bash -n linux/base_functions.sh
cd ~/projects/qol && ! grep -rn '✅\|📦\|ℹ️\|⚠️\|❌' --include='*.sh' --include='gotime' --include='*.md' .
cd ~/vaults/dojobrain && uv run scripts/build-design-tokens.py --check
```

The last two are the ones worth watching: the emoji grep proves the old vocabulary is fully gone, and the vault check proves no hex in the qol repo has drifted from `tokens/colors.css`.

## Out of scope

These call the retained back-compat helpers and will render in the new palette without edits. Giving them phases and bookends is separate work:

`install_zsh.sh` (deprecated), `netstatus.sh`, `uninstall_omz_p10k.sh`, `shell-login-settings.sh`, `tool_checks.sh`, `linux/docker_uninstall.sh`, `linux/kernel_update.sh`, `linux/nm-connection-maker.sh`, `linux/wireshark_install.sh`.

Rewiring `install_nano.sh`'s existing `confirm()` to call `ask_confirm` is also separate work. Task 8 builds the helper and Task 9 documents it; `install_nano.sh` has an 80k test suite of its own, and changing its prompt path deserves its own review rather than riding along here. `confirm()` keeps working meanwhile — it is unaffected by anything in this plan.
