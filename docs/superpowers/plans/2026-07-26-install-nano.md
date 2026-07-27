# install_nano.sh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A cross-platform installer that gives a student the best GNU nano their machine can run — syntax highlighting, sane editing defaults, a `^S` save binding, and a printable cheat sheet.

**Architecture:** One bash script at the repo root, written as a library of small pure functions plus a `main` that wires them together. A `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard at the bottom means the file can be sourced by a test harness without executing anything, which is what makes the logic testable. Config is emitted into a managed block in `~/.nanorc` that is rewritten whole on every run. Feature detection is done by grepping `nano --help` rather than by comparing version numbers.

**Tech Stack:** bash 3.2+ (macOS ships 3.2 — no associative arrays, no `${x^^}`), coreutils, git, curl. No test framework: a plain bash test script with assert helpers, matching the repo's zero-dependency habit.

## Global Constraints

- **bash 3.2 compatible.** macOS ships bash 3.2.57. No associative arrays, no `mapfile`, no `${var^^}`, no `&>>`.
- **Minimum GNU nano: 4.0.** Below that, refuse to write a config.
- **Probing nano must use `TERM=dumb "$bin" --version </dev/null 2>&1`.** Verified: macOS `/usr/bin/nano` is `UW PICO 5.09`, which ignores `--version` and opens an editor. With `TERM=dumb` and stdin closed it exits 1 with `Incomplete terminfo entry` instead of corrupting the terminal. GNU nano is unaffected — `src/nano.c:1981` calls `version(); exit(0);` long before `initscr()` at line 2164.
- **GNU nano version string is exactly `" GNU nano, version 9.1"`** — leading space, comma. From `src/nano.c:657`: `printf(_(" GNU nano, version %s\n"), VERSION);`
- **Syntax include order is last-wins.** `begin_new_syntax()` in `src/rcfile.c` prepends to the `syntaxes` list; `find_and_prime_applicable_syntax()` in `src/color.c` walks from the head and breaks on first match. Community pack is included first, shipped pack last.
- **Managed block markers:** `# >>> qol nano block >>>` and `# <<< qol nano block <<<`, matching the `BLOCK_START`/`BLOCK_END` convention in `install_zsh_starship.sh:51-52`.
- **Reuse the repo output theme.** `log_info`, `log_ok`, `log_warn`, `log_err`, `log_step`, `printline`, `style_text`, `format_font` — copy the definitions from `install_zsh_starship.sh:67-141`, as that script does rather than sourcing `linux/base_functions.sh` (which is Linux-only).
- **Filenames:** lowercase letters, digits, hyphens.
- **No `set mouse`, no `set minibar`, no `set zero`, no `set backup`, no interface colour directives.** Rationale is in the spec; do not add them.

---

## File Structure

| Path | Responsibility |
|:--|:--|
| `install_nano.sh` | Everything executable. Detection, capability probe, config rendering, managed-block write, syntax pack sync, `main`. |
| `tests/test-install-nano.sh` | Sources `install_nano.sh` and exercises its pure functions against stub `nano` binaries. |
| `docs/nano-cheatsheet.md` | Plain-text keybinding reference. |
| `docs/nano-cheatsheet.html` | Standalone printable reference in the IT Dojo design system. |
| `README.md` | Two new rows in the tool table. |

The nanorc body lives inside `install_nano.sh` as a heredoc in `render_nanorc`, not in a separate `nanorc.template` file as the spec suggested. The spec was written before the gating design settled: because roughly a third of the lines are conditional, a template file would need its own mini templating language. A heredoc in the function that owns the conditionals is simpler and keeps the two in sync. This is the only deviation from the spec.

---

### Task 1: Script skeleton, flags, and test harness

> **Amended after review, 2026-07-26.** Two things in this task's code below are
> wrong; the implemented version in `install_nano.sh` is correct and governs.
>
> 1. `set -euo pipefail` must **not** sit at file scope. `source` runs in the
>    caller's shell, so it turns on `-e` in the test harness — which declares
>    only `set -uo pipefail` — and any later test calling a function that
>    returns non-zero outside a conditional would kill the suite with no output.
>    It belongs inside the `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard.
> 2. The output-theme helpers below are a lossy paraphrase of
>    `install_zsh_starship.sh`'s, not the copy the comment claims. They dropped
>    the `QOL_COLOR` TTY/`NO_COLOR` gate (so log lines emitted raw ANSI into
>    pipes and log files), the numeric `tput cols` guard, and `format_font`'s
>    leading `printline`. Copy `install_zsh_starship.sh:58-113` verbatim
>    instead, and make sure `log_step` does not then emit a double separator.

**Files:**
- Create: `install_nano.sh`
- Create: `tests/test-install-nano.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `SCRIPT_DIR`, `BLOCK_START`, `BLOCK_END`, `NANORC`, `SYNTAX_DIR`, `DRY_RUN`, `ASSUME_YES`, `NO_SYNTAX`, `SET_EDITOR` globals; `usage()`, `parse_args()`, and the `log_*` helpers. Every later task's tests source this file.

- [ ] **Step 1: Write the failing test**

Create `tests/test-install-nano.sh`:

```bash
#!/usr/bin/env bash
# Test harness for install_nano.sh.
#
# No test framework by design — the repo has no build step and no dependency
# manifest, and a student cloning it should be able to run these immediately.
#
# Run: ./tests/test-install-nano.sh
set -uo pipefail

TESTS_RUN=0
TESTS_FAILED=0
SCRIPT_UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install_nano.sh"

# Sourcing must not execute main; install_nano.sh guards on BASH_SOURCE == $0.
# shellcheck source=/dev/null
source "$SCRIPT_UNDER_TEST"

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

assert_ok() {
    local label="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if eval "$1"; then
        printf '  ok   %s\n' "$label"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s (expected success from: %s)\n' "$label" "$1"
    fi
}

assert_fail() {
    local label="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if eval "$1"; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s (expected failure from: %s)\n' "$label" "$1"
    else
        printf '  ok   %s\n' "$label"
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

echo "== flags =="

test_parse_args_defaults() {
    DRY_RUN=""; ASSUME_YES=""; NO_SYNTAX=""; SET_EDITOR=""
    parse_args
    assert_eq "" "$DRY_RUN"    "no flags leaves DRY_RUN unset"
    assert_eq "" "$NO_SYNTAX"  "no flags leaves NO_SYNTAX unset"
}

test_parse_args_all() {
    DRY_RUN=""; ASSUME_YES=""; NO_SYNTAX=""; SET_EDITOR=""
    parse_args --dry-run --yes --no-syntax --set-editor
    assert_eq "1" "$DRY_RUN"    "--dry-run sets DRY_RUN"
    assert_eq "1" "$ASSUME_YES" "--yes sets ASSUME_YES"
    assert_eq "1" "$NO_SYNTAX"  "--no-syntax sets NO_SYNTAX"
    assert_eq "1" "$SET_EDITOR" "--set-editor sets SET_EDITOR"
}

test_parse_args_short() {
    DRY_RUN=""; ASSUME_YES=""; NO_SYNTAX=""; SET_EDITOR=""
    parse_args -n -y
    assert_eq "1" "$DRY_RUN"    "-n sets DRY_RUN"
    assert_eq "1" "$ASSUME_YES" "-y sets ASSUME_YES"
}

test_parse_args_defaults
test_parse_args_all
test_parse_args_short

printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ "$TESTS_FAILED" -eq 0 ]]
```

- [ ] **Step 2: Run test to verify it fails**

```bash
chmod +x tests/test-install-nano.sh && ./tests/test-install-nano.sh
```

Expected: FAIL — `install_nano.sh` does not exist, source fails.

- [ ] **Step 3: Write minimal implementation**

Create `install_nano.sh`:

```bash
#!/usr/bin/env bash
#
# install_nano.sh — set up GNU nano for people who actually edit in it.
#
# Installs GNU nano (Homebrew on macOS, the distro package manager on Linux),
# probes the resulting binary for which rc directives it supports, and writes a
# managed block into ~/.nanorc with syntax highlighting, line numbers, sane
# indentation and a ^S save binding.
#
# Usage:
#   ./install_nano.sh                 # install and configure
#   ./install_nano.sh --dry-run       # print the plan, change nothing
#   ./install_nano.sh --no-syntax     # skip the community syntax pack clone
#
# macOS note: /usr/bin/nano is not nano. It is UW PICO 5.09, which has no
# syntax highlighting and none of the modern rc directives. This script
# installs the real GNU nano via Homebrew and refuses to write a config if
# PATH still resolves `nano` to /usr/bin/nano.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BLOCK_START="# >>> qol nano block >>>"
BLOCK_END="# <<< qol nano block <<<"

NANORC="$HOME/.nanorc"
SYNTAX_DIR="$HOME/.nano"
SYNTAX_REPO="https://github.com/scopatz/nanorc"
MIN_NANO_VERSION="4.0"

DRY_RUN=""
ASSUME_YES=""
NO_SYNTAX=""
SET_EDITOR=""

# ---------------------------------------------------------------------------
# Output theme
# ---------------------------------------------------------------------------
# Copied from install_zsh_starship.sh rather than sourced, so this script stays
# a single self-contained file and works on macOS (linux/base_functions.sh is
# Linux-only).
printline() {
    local char="─" width
    width="$(tput cols 2>/dev/null || echo 80)"
    case "${1:-solid}" in
        solid)     char="─" ;;
        bullet)    char="•" ;;
        ibeam)     char="⌶" ;;
        star)      char="★" ;;
        plus)      char="+" ;;
        diamond)   char="◆" ;;
        dentistry) char="⚑" ;;
    esac
    printf '%*s\n' "$width" '' | tr ' ' "$char"
}

style_text() {
    local text="$1" weight="${2:-normal}" colour="${3:-}" seq=""
    case "$weight" in
        bold)   seq="1" ;;
        light)  seq="2" ;;
        normal) seq="0" ;;
    esac
    case "$colour" in
        red)    seq="$seq;31" ;;
        green)  seq="$seq;32" ;;
        yellow) seq="$seq;33" ;;
        blue)   seq="$seq;34" ;;
    esac
    printf '\033[%sm%s\033[0m\n' "$seq" "$text"
}

format_font() { style_text "$1" "${2:-normal}" "${3:-}"; }

log_step() { echo; printline; style_text "$1" "${2:-bold}" "${3:-yellow}"; }
log_info() { format_font "ℹ️   $1" bold blue; }
log_ok()   { format_font "✅  $1" bold green; }
log_warn() { format_font "⚠️   $1" bold yellow; }
log_err()  { format_font "❌  $1" bold red >&2; }

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
usage() {
    cat <<'USAGE'
install_nano.sh — set up GNU nano with syntax highlighting and sane defaults.

Usage: ./install_nano.sh [options]

  -n, --dry-run      Print every action; write nothing.
  -y, --yes          Skip confirmation prompts.
      --no-syntax    Skip cloning the community syntax pack (offline machines).
                     The syntax definitions shipped with nano are still used.
      --set-editor   Also export EDITOR=nano and VISUAL=nano into your shell rc.
  -h, --help         Show this message.
USAGE
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|-n)  DRY_RUN=1 ;;
            --yes|-y)      ASSUME_YES=1 ;;
            --no-syntax)   NO_SYNTAX=1 ;;
            --set-editor)  SET_EDITOR=1 ;;
            --help|-h)     usage; exit 0 ;;
            *)             log_err "Unknown option: $1"; usage >&2; exit 2 ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    log_ok "skeleton only"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

- [ ] **Step 4: Run test to verify it passes**

```bash
chmod +x install_nano.sh && ./tests/test-install-nano.sh
```

Expected: the suite reports `0 failed`.

- [ ] **Step 5: Verify sourcing has no side effects**

```bash
bash -c 'source ./install_nano.sh && echo "sourced clean"'
```

Expected: `sourced clean` with no "skeleton only" line above it.

- [ ] **Step 6: Commit**

```bash
git add install_nano.sh tests/test-install-nano.sh
git commit -m "feat: add install_nano.sh skeleton and test harness"
```

---

### Task 2: nano detection and version comparison

**Files:**
- Modify: `install_nano.sh`
- Modify: `tests/test-install-nano.sh`

**Interfaces:**
- Consumes: `log_err` from Task 1.
- Produces:
  - `version_at_least HAVE WANT` → exit 0 if `HAVE >= WANT`.
  - `nano_version BIN` → prints the bare version (`9.1`) on stdout, exit 0; exit 1 if `BIN` is not GNU nano.
  - `make_stub_nano DIR VERSION` (test-only helper, defined in the test file).

- [ ] **Step 1: Write the failing test**

Append to `tests/test-install-nano.sh`, before the final `printf` summary:

```bash
echo
echo "== version comparison =="

assert_ok   'version_at_least 9.1 4.0'   "9.1 >= 4.0"
assert_ok   'version_at_least 4.0 4.0'   "4.0 >= 4.0 (equal)"
assert_ok   'version_at_least 10.0 9.1'  "10.0 >= 9.1 (numeric, not lexical)"
assert_ok   'version_at_least 5.10 5.9'  "5.10 >= 5.9 (numeric minor)"
assert_fail 'version_at_least 2.9 4.0'   "2.9 < 4.0"
assert_fail 'version_at_least 3.2 4.0'   "3.2 < 4.0"
assert_ok   'version_at_least 4.0.1 4.0' "4.0.1 >= 4.0 (patch level)"

echo
echo "== nano detection =="

# Build a fake nano on disk. GNU nano's real first line is exactly
# " GNU nano, version 9.1" — leading space, comma — per src/nano.c:657.
make_stub_nano() {
    local dir="$1" version="$2"
    mkdir -p "$dir"
    cat > "$dir/nano" <<STUB
#!/usr/bin/env bash
case "\$1" in
    --version) printf ' GNU nano, version %s\n' "$version"; exit 0 ;;
    --help)    printf ' -l, --linenumbers\n -q, --indicator\n -%%, --stateflags\n'; exit 0 ;;
esac
exit 1
STUB
    chmod +x "$dir/nano"
}

# Build a fake pico: ignores --version, exits nonzero under TERM=dumb.
make_stub_pico() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/nano" <<'STUB'
#!/usr/bin/env bash
printf 'Incomplete terminfo entry\n' >&2
exit 1
STUB
    chmod +x "$dir/nano"
}

test_nano_version() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/gnu" "9.1"
    make_stub_nano "$tmp/old" "4.8"
    make_stub_pico "$tmp/pico"

    assert_eq "9.1" "$(nano_version "$tmp/gnu/nano")"  "parses 9.1 from GNU nano"
    assert_eq "4.8" "$(nano_version "$tmp/old/nano")"  "parses 4.8 from GNU nano"
    assert_fail 'nano_version '"$tmp"'/pico/nano'      "pico is rejected"
    assert_fail 'nano_version /nonexistent/nano'       "missing binary is rejected"

    rm -rf "$tmp"
}

test_nano_version
```

- [ ] **Step 2: Run test to verify it fails**

```bash
./tests/test-install-nano.sh
```

Expected: FAIL — `version_at_least: command not found`.

- [ ] **Step 3: Write minimal implementation**

Insert into `install_nano.sh` after the `parse_args` function:

```bash
# ---------------------------------------------------------------------------
# nano detection
# ---------------------------------------------------------------------------
# True when HAVE is the same version as WANT or newer. Sorting both numerically
# and taking the first line means WANT sorts first in exactly the cases we want
# to accept, including the equal case. A plain string compare would put "10.0"
# below "9.1"; `sort -V` would handle that but is not on macOS's BSD sort.
version_at_least() {
    local have="$1" want="$2" first
    first="$(printf '%s\n%s\n' "$want" "$have" \
        | sort -t. -k1,1n -k2,2n -k3,3n | head -1)"
    [[ "$first" == "$want" ]]
}

# Print the bare version of a GNU nano binary, or fail.
#
# TERM=dumb and </dev/null are load-bearing, not defensive. macOS's
# /usr/bin/nano is UW PICO, which does not understand --version and will open
# a full-screen editor. Under TERM=dumb with stdin closed it bails out with
# "Incomplete terminfo entry" instead. GNU nano prints its version and exits
# before it ever calls initscr(), so it is unaffected.
nano_version() {
    local bin="$1" line
    [[ -x "$bin" ]] || return 1
    line="$(TERM=dumb "$bin" --version </dev/null 2>&1 | head -1)" || return 1
    case "$line" in
        *"GNU nano"*) ;;
        *) return 1 ;;
    esac
    printf '%s\n' "$line" \
        | sed -E 's/.*GNU nano,? version ([0-9][0-9.]*).*/\1/'
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
./tests/test-install-nano.sh
```

Expected: the suite reports `0 failed`.

- [ ] **Step 5: Verify against the real pico on this machine**

```bash
source ./install_nano.sh && nano_version /usr/bin/nano; echo "exit=$?"
```

Expected: no version printed, `exit=1`. The terminal must still be usable — no escape-code garbage, no editor UI.

- [ ] **Step 6: Commit**

```bash
git add install_nano.sh tests/test-install-nano.sh
git commit -m "feat: detect GNU nano and compare versions safely past pico"
```

---

### Task 3: Capability probe

**Files:**
- Modify: `install_nano.sh`
- Modify: `tests/test-install-nano.sh`

**Interfaces:**
- Consumes: nothing from Task 2 at runtime; shares the `TERM=dumb` probe convention.
- Produces:
  - `nano_help_cache` — global string, populated by `load_nano_help BIN`.
  - `load_nano_help BIN` → captures `nano --help` once into `nano_help_cache`.
  - `nano_supports LONGOPT` → exit 0 if that long option appears in the cache. `LONGOPT` is given without dashes, e.g. `nano_supports indicator`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-install-nano.sh` before the summary:

```bash
echo
echo "== capability probe =="

test_capability_probe() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/full" "9.1"

    # A --enable-tiny build: modern version number, but the gated options are
    # compiled out. This is why we probe --help instead of comparing versions.
    mkdir -p "$tmp/tiny"
    cat > "$tmp/tiny/nano" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    --version) printf ' GNU nano, version 8.0\n'; exit 0 ;;
    --help)    printf ' -l, --linenumbers\n'; exit 0 ;;
esac
exit 1
STUB
    chmod +x "$tmp/tiny/nano"

    load_nano_help "$tmp/full/nano"
    assert_ok 'nano_supports linenumbers' "full build supports linenumbers"
    assert_ok 'nano_supports indicator'   "full build supports indicator"
    assert_ok 'nano_supports stateflags'  "full build supports stateflags"
    assert_fail 'nano_supports zero'      "stub does not advertise zero"

    load_nano_help "$tmp/tiny/nano"
    assert_ok   'nano_supports linenumbers' "tiny build supports linenumbers"
    assert_fail 'nano_supports indicator'   "tiny build lacks indicator despite 8.0"
    assert_fail 'nano_supports stateflags'  "tiny build lacks stateflags despite 8.0"

    # A substring must not produce a false positive: --line must not match
    # --linenumbers.
    assert_fail 'nano_supports line' "partial option name does not match"

    rm -rf "$tmp"
}

test_capability_probe
```

- [ ] **Step 2: Run test to verify it fails**

```bash
./tests/test-install-nano.sh
```

Expected: FAIL — `load_nano_help: command not found`.

- [ ] **Step 3: Write minimal implementation**

Append to the `nano detection` section of `install_nano.sh`:

```bash
# `nano --help` lists the long-option form of every rc directive that this
# particular binary was compiled with. Several are wrapped in #ifdef in
# src/nano.c, so a distro build configured with --enable-tiny omits them
# regardless of its version number. Probing --help is therefore exact where a
# version table would be wrong.
nano_help_cache=""

load_nano_help() {
    local bin="$1"
    nano_help_cache="$(TERM=dumb "$bin" --help </dev/null 2>&1 || true)"
}

# Match on the whole option token so that `line` cannot match `--linenumbers`.
# The option is always followed by a comma, an equals sign, or whitespace.
nano_supports() {
    printf '%s\n' "$nano_help_cache" | grep -qE -- "--$1([,= ]|\$)"
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
./tests/test-install-nano.sh
```

Expected: the suite reports `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add install_nano.sh tests/test-install-nano.sh
git commit -m "feat: probe nano --help for supported rc directives"
```

---

### Task 4: Syntax include path discovery

**Files:**
- Modify: `install_nano.sh`
- Modify: `tests/test-install-nano.sh`

**Interfaces:**
- Consumes: `SYNTAX_DIR` from Task 1.
- Produces: `syntax_include_globs` → prints one glob per line, in nano include order (community first, shipped last). Reads the `QOL_NANO_PREFIXES` global if set, so tests can point it at a fixture tree; defaults to the real system paths.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-install-nano.sh` before the summary:

```bash
echo
echo "== syntax include paths =="

test_syntax_include_globs() {
    local tmp; tmp="$(mktemp -d)"
    mkdir -p "$tmp/share/nano/extra" "$tmp/home/.nano" "$tmp/deb/nano-syntax-highlighting"
    touch "$tmp/share/nano/sh.nanorc" "$tmp/share/nano/extra/ada.nanorc"
    touch "$tmp/home/.nano/yaml.nanorc"
    touch "$tmp/deb/nano-syntax-highlighting/toml.nanorc"

    local saved_dir="$SYNTAX_DIR" saved_prefixes="${QOL_NANO_PREFIXES:-}"
    SYNTAX_DIR="$tmp/home/.nano"
    QOL_NANO_PREFIXES="$tmp/share/nano $tmp/deb/nano-syntax-highlighting $tmp/nonexistent"

    local out; out="$(syntax_include_globs)"

    assert_eq "$tmp/home/.nano/*.nanorc
$tmp/share/nano/*.nanorc
$tmp/share/nano/extra/*.nanorc
$tmp/deb/nano-syntax-highlighting/*.nanorc" "$out" \
        "community pack first, shipped last, extra included"

    assert_not_contains "$out" "nonexistent" "missing directories are skipped"

    # With no community clone, the ~/.nano line must not be emitted at all —
    # nano warns on an include glob that matches nothing.
    SYNTAX_DIR="$tmp/absent"
    out="$(syntax_include_globs)"
    assert_not_contains "$out" "absent" "absent community dir is skipped"
    assert_contains "$out" "$tmp/share/nano/*.nanorc" "shipped path still present"

    SYNTAX_DIR="$saved_dir"
    QOL_NANO_PREFIXES="$saved_prefixes"
    rm -rf "$tmp"
}

test_syntax_include_globs
```

- [ ] **Step 2: Run test to verify it fails**

```bash
./tests/test-install-nano.sh
```

Expected: FAIL — `syntax_include_globs: command not found`.

- [ ] **Step 3: Write minimal implementation**

Append to `install_nano.sh` after the capability probe section:

```bash
# ---------------------------------------------------------------------------
# Syntax highlighting
# ---------------------------------------------------------------------------
# Emit include globs in nano's parse order. Order is load-bearing:
# begin_new_syntax() in src/rcfile.c prepends each syntax to a list, and
# find_and_prime_applicable_syntax() in src/color.c walks that list from the
# head and stops at the first extension match. The last file included therefore
# wins. The definitions shipped with the nano binary are versioned alongside it
# and are the better ones where both packs define a language, so they go last;
# the community pack fills in the ~140 languages nano does not ship.
#
# Only directories that exist are emitted. nano prints a warning for an include
# glob that matches nothing, and a warning on every launch is exactly the kind
# of thing that makes a student distrust their editor.
syntax_include_globs() {
    local prefixes dir

    if [[ -n "${QOL_NANO_PREFIXES:-}" ]]; then
        prefixes="$QOL_NANO_PREFIXES"
    else
        prefixes="/usr/share/nano
/usr/local/share/nano
/opt/homebrew/share/nano
/usr/share/nano-syntax-highlighting"
    fi

    # Community pack first — lowest precedence.
    if [[ -d "$SYNTAX_DIR" ]]; then
        printf '%s/*.nanorc\n' "$SYNTAX_DIR"
    fi

    # Shipped packs last — they win ties.
    for dir in $prefixes; do
        [[ -d "$dir" ]] || continue
        printf '%s/*.nanorc\n' "$dir"
        [[ -d "$dir/extra" ]] && printf '%s/extra/*.nanorc\n' "$dir"
    done
}
```

Note the unquoted `$prefixes` in the `for` loop is deliberate word-splitting, which is how both the default newline-separated string and the test's space-separated string iterate correctly under bash 3.2 without arrays.

- [ ] **Step 4: Run test to verify it passes**

```bash
./tests/test-install-nano.sh
```

Expected: the suite reports `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add install_nano.sh tests/test-install-nano.sh
git commit -m "feat: discover syntax include paths in last-wins order"
```

---

### Task 5: Render the nanorc body

**Files:**
- Modify: `install_nano.sh`
- Modify: `tests/test-install-nano.sh`

**Interfaces:**
- Consumes: `nano_supports` (Task 3), `syntax_include_globs` (Task 4), `BLOCK_START`/`BLOCK_END` (Task 1).
- Produces: `render_nanorc` → prints the complete managed block, markers included, to stdout. Reads `nano_help_cache`; writes no files.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-install-nano.sh` before the summary:

```bash
echo
echo "== nanorc rendering =="

test_render_nanorc() {
    local tmp; tmp="$(mktemp -d)"
    mkdir -p "$tmp/share/nano" "$tmp/home/.nano"
    touch "$tmp/share/nano/sh.nanorc" "$tmp/home/.nano/yaml.nanorc"

    local saved_dir="$SYNTAX_DIR" saved_prefixes="${QOL_NANO_PREFIXES:-}"
    SYNTAX_DIR="$tmp/home/.nano"
    QOL_NANO_PREFIXES="$tmp/share/nano"

    # --- full-capability build ---
    nano_help_cache=' -l, --linenumbers
 -q, --indicator
 -%, --stateflags'
    local out; out="$(render_nanorc)"

    assert_contains "$out" "$BLOCK_START" "block start marker present"
    assert_contains "$out" "$BLOCK_END"   "block end marker present"
    assert_contains "$out" "set linenumbers"   "core: linenumbers"
    assert_contains "$out" "set softwrap"      "core: softwrap"
    assert_contains "$out" "set atblanks"      "core: atblanks"
    assert_contains "$out" "set tabsize 4"     "core: tabsize 4"
    assert_contains "$out" "set tabstospaces"  "core: tabstospaces"
    assert_contains "$out" "set autoindent"    "core: autoindent"
    assert_contains "$out" "set constantshow"  "core: constantshow"
    assert_contains "$out" "set positionlog"   "core: positionlog"
    assert_contains "$out" "set historylog"    "core: historylog"
    assert_contains "$out" "set multibuffer"   "core: multibuffer"
    assert_contains "$out" "set smarthome"     "core: smarthome"
    assert_contains "$out" "set trimblanks"    "core: trimblanks"
    assert_contains "$out" "set guidestripe 80" "core: guidestripe"
    assert_contains "$out" 'set matchbrackets "(<[{)>]}"' "core: matchbrackets"
    assert_contains "$out" "bind ^S savefile main" "binding: ^S saves"

    assert_contains "$out" "set indicator"  "gated: indicator written"
    assert_contains "$out" "set stateflags" "gated: stateflags written"

    # Excluded by design — these must never appear.
    assert_not_contains "$out" "set mouse"   "excluded: mouse"
    assert_not_contains "$out" "set minibar" "excluded: minibar"
    assert_not_contains "$out" "set zero"    "excluded: zero"
    assert_not_contains "$out" "set backup"  "excluded: backup"
    assert_not_contains "$out" "titlecolor"  "excluded: interface colours"
    assert_not_contains "$out" "bind ^Q"     "excluded: ^Q collides with XOFF"

    # Include order: community pack must appear before the shipped pack.
    local community_line shipped_line
    community_line="$(printf '%s\n' "$out" | grep -n 'home/.nano/\*.nanorc' | cut -d: -f1)"
    shipped_line="$(printf '%s\n' "$out" | grep -n 'share/nano/\*.nanorc' | cut -d: -f1)"
    assert_ok "[ $community_line -lt $shipped_line ]" \
        "community include precedes shipped include"

    # --- tiny build ---
    nano_help_cache=' -l, --linenumbers'
    out="$(render_nanorc)"
    assert_contains "$out" "set linenumbers" "tiny: core still written"
    assert_not_contains "$out" "
set indicator" "tiny: indicator not written as a directive"
    assert_contains "$out" "# set indicator" "tiny: indicator left as a comment"
    assert_contains "$out" "nano 5.0" "tiny: comment names the enabling version"
    assert_contains "$out" "# set stateflags" "tiny: stateflags left as a comment"
    assert_contains "$out" "nano 5.3" "tiny: stateflags comment names 5.3"

    SYNTAX_DIR="$saved_dir"
    QOL_NANO_PREFIXES="$saved_prefixes"
    rm -rf "$tmp"
}

test_render_nanorc
```

- [ ] **Step 2: Run test to verify it fails**

```bash
./tests/test-install-nano.sh
```

Expected: FAIL — `render_nanorc: command not found`.

- [ ] **Step 3: Write minimal implementation**

Append to `install_nano.sh`:

```bash
# ---------------------------------------------------------------------------
# nanorc rendering
# ---------------------------------------------------------------------------
# Emit one gated directive. When the running nano supports it, write it live;
# when it does not, write it as a comment naming the version that would enable
# it, so someone who later upgrades can see what they gained.
#
#   gated_directive <long-option> <rc-line> <version-that-added-it>
gated_directive() {
    local opt="$1" line="$2" since="$3"
    if nano_supports "$opt"; then
        printf '%s\n' "$line"
    else
        printf '# %s   # unavailable — needs nano %s (or a non-tiny build)\n' \
            "$line" "$since"
    fi
}

render_nanorc() {
    local glob

    printf '%s\n' "$BLOCK_START"
    cat <<'BODY'
# Managed by install_nano.sh — this whole block is rewritten on every rerun.
# Put your own settings OUTSIDE the markers; anything inside is disposable.
# Full directive reference: `man nanorc`

# --- editing ---------------------------------------------------------------
set autoindent          # keep the current indent on Enter
set tabsize 4           # a tab is four columns wide
set tabstospaces        # ...and typing Tab inserts spaces, not a tab character
set trimblanks          # strip trailing whitespace from wrapped lines
set smarthome           # Home goes to the first non-blank first, then column 1
set matchbrackets "(<[{)>]}"   # M-] jumps to the matching bracket

# --- display ---------------------------------------------------------------
set linenumbers         # line numbers down the left margin
set softwrap            # wrap long lines on screen without inserting newlines
set atblanks            # ...and wrap at spaces rather than mid-word
set constantshow        # always show the cursor position on the status bar
set guidestripe 80      # faint vertical rule at column 80
BODY

    gated_directive indicator "set indicator" "5.0"
    gated_directive stateflags "set stateflags" "5.3"

    cat <<'BODY'

# --- state -----------------------------------------------------------------
set positionlog         # reopen a file where you left off
set historylog          # remember search and replace history between sessions
set multibuffer         # ^R reads a file into a new buffer instead of inline

# --- keys ------------------------------------------------------------------
# ^S to save, because everyone's fingers already do this. nano's own ^O
# ("WriteOut") stays bound as well.
#
# ^Q is deliberately NOT bound to exit: it is XOFF on many terminals, and a
# student who hits it on a serial console gets what looks like a frozen
# machine. ^X remains the way out, and it is on the help bar at all times.
bind ^S savefile main
BODY

    printf '\n# --- syntax highlighting ---------------------------------------------------\n'
    printf '# Later includes win: nano matches the most recently parsed syntax first,\n'
    printf '# so the definitions shipped with nano override the community pack.\n'
    while IFS= read -r glob; do
        [[ -n "$glob" ]] && printf 'include "%s"\n' "$glob"
    done <<EOF
$(syntax_include_globs)
EOF

    printf '%s\n' "$BLOCK_END"
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
./tests/test-install-nano.sh
```

Expected: the suite reports `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add install_nano.sh tests/test-install-nano.sh
git commit -m "feat: render the nanorc managed block with gated directives"
```

---

### Task 6: Managed-block write and idempotence

**Files:**
- Modify: `install_nano.sh`
- Modify: `tests/test-install-nano.sh`

**Interfaces:**
- Consumes: `BLOCK_START`, `BLOCK_END`, `render_nanorc`.
- Produces:
  - `backup_file FILE` → copies to `FILE.pre-nano.<timestamp>.bak` when a backup is warranted.
  - `replace_file_contents SRC DST` → overwrites DST's bytes, preserving its inode and mode.
  - `remove_managed_block FILE` → strips an existing block.
  - `write_nanorc` → backs up if needed, removes any old block, appends a freshly rendered one.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-install-nano.sh` before the summary:

```bash
echo
echo "== managed block =="

test_managed_block() {
    local tmp; tmp="$(mktemp -d)"
    mkdir -p "$tmp/share/nano"
    touch "$tmp/share/nano/sh.nanorc"

    local saved_rc="$NANORC" saved_dir="$SYNTAX_DIR" saved_prefixes="${QOL_NANO_PREFIXES:-}"
    NANORC="$tmp/nanorc"
    SYNTAX_DIR="$tmp/absent"
    QOL_NANO_PREFIXES="$tmp/share/nano"
    nano_help_cache=' -l, --linenumbers
 -q, --indicator
 -%, --stateflags'

    # A pre-existing user config with a setting of their own.
    printf 'set nowrap\n' > "$NANORC"

    write_nanorc
    local first; first="$(cat "$NANORC")"
    assert_contains "$first" "set nowrap"     "pre-existing user line survives"
    assert_contains "$first" "set linenumbers" "block was written"
    assert_eq "1" "$(grep -cF "$BLOCK_START" "$NANORC")" "exactly one start marker"

    # A backup must exist, since the file had content and no block.
    assert_eq "1" "$(find "$tmp" -name 'nanorc.pre-nano.*.bak' | wc -l | tr -d ' ')" \
        "original was backed up"

    # Rerun: byte-identical, still one block.
    write_nanorc
    local second; second="$(cat "$NANORC")"
    assert_eq "$first" "$second" "rerun is byte-identical"
    assert_eq "1" "$(grep -cF "$BLOCK_START" "$NANORC")" "still exactly one start marker"
    assert_eq "1" "$(grep -cF "$BLOCK_END" "$NANORC")"   "still exactly one end marker"

    # A third run after the user edits inside the block must discard the edit.
    printf 'set mouse\n' >> "$NANORC"
    write_nanorc
    assert_not_contains "$(cat "$NANORC")" "set mouse" "stale line outside block is dropped"

    # File mode must survive: replace_file_contents keeps the inode.
    chmod 644 "$NANORC"
    local mode_before; mode_before="$(ls -l "$NANORC" | cut -c1-10)"
    write_nanorc
    assert_eq "$mode_before" "$(ls -l "$NANORC" | cut -c1-10)" "file mode preserved"

    NANORC="$saved_rc"
    SYNTAX_DIR="$saved_dir"
    QOL_NANO_PREFIXES="$saved_prefixes"
    rm -rf "$tmp"
}

test_managed_block
```

Note the "stale line outside block is dropped" case: `set mouse` is appended *after* the end marker, and the rewrite drops it because the block is re-appended at the end of the file after removal. Confirm this matches the intent before implementing — if the desired behaviour is to preserve trailing user content, the block must be reinserted in place rather than appended.

**Decision for this implementation: append.** `install_zsh_starship.sh` appends, and matching the sibling script matters more than preserving a line a user added after a marker that says the region is managed.

- [ ] **Step 2: Run test to verify it fails**

```bash
./tests/test-install-nano.sh
```

Expected: FAIL — `write_nanorc: command not found`.

- [ ] **Step 3: Write minimal implementation**

Append to `install_nano.sh`:

```bash
# ---------------------------------------------------------------------------
# Writing ~/.nanorc
# ---------------------------------------------------------------------------
backup_file() {
    local f="$1" backup
    [[ -f "$f" ]] || return 0
    backup="$f.pre-nano.$(date +%Y%m%d-%H%M%S).bak"
    cp "$f" "$backup"
    log_info "Backed up $f → $backup"
}

# Overwrite dst with the contents of src, keeping dst's mode, owner and inode.
# `mv tmp dst` would be simpler but carries the temp file's permissions across —
# mktemp creates 0600, which would silently tighten a normal 0644 .nanorc.
replace_file_contents() {
    local src="$1" dst="$2"
    cat "$src" > "$dst"
    rm -f "$src"
}

remove_managed_block() {
    local file="$1" tmp
    grep -qF "$BLOCK_START" "$file" || return 0
    tmp="$(mktemp)"
    awk -v s="$BLOCK_START" -v e="$BLOCK_END" '
        index($0, s) { skip = 1 }
        !skip { print }
        index($0, e) { skip = 0 }
    ' "$file" > "$tmp"
    replace_file_contents "$tmp" "$file"
}

write_nanorc() {
    log_step "Writing $NANORC..."
    [[ -f "$NANORC" ]] || touch "$NANORC"

    # Only back up a file we have not managed before. Backing up on every rerun
    # would litter the home directory with near-identical copies.
    if ! grep -qF "$BLOCK_START" "$NANORC" && [[ -s "$NANORC" ]]; then
        backup_file "$NANORC"
    fi

    remove_managed_block "$NANORC"

    # Strip trailing blank lines left behind by block removal. Without this,
    # every rerun would add one more blank line above the block and the
    # "byte-identical rerun" guarantee would fail on the second run.
    # Only *trailing* blanks go — blank lines inside the user's own config are
    # their spacing and must survive.
    local tmp; tmp="$(mktemp)"
    awk '{ lines[NR] = $0 }
         END {
             last = 0
             for (i = 1; i <= NR; i++) if (lines[i] ~ /[^[:space:]]/) last = i
             for (i = 1; i <= last; i++) print lines[i]
         }' "$NANORC" > "$tmp"
    replace_file_contents "$tmp" "$NANORC"

    render_nanorc >> "$NANORC"
    log_ok "Wrote the qol block to $NANORC"
}
```

One change to Task 5 is required by this: because the block is now appended
directly after the last non-blank line, `render_nanorc` must supply its own
separating blank line. Change its first statement from
`printf '%s\n' "$BLOCK_START"` to `printf '\n%s\n' "$BLOCK_START"`.

- [ ] **Step 4: Run test to verify it passes**

```bash
./tests/test-install-nano.sh
```

Expected: the suite reports `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add install_nano.sh tests/test-install-nano.sh
git commit -m "feat: write an idempotent managed block into ~/.nanorc"
```

---

### Task 7: Package installation and the macOS pico guard

**Files:**
- Modify: `install_nano.sh`
- Modify: `tests/test-install-nano.sh`

**Interfaces:**
- Consumes: `nano_version` (Task 2), `version_at_least` (Task 2), `MIN_NANO_VERSION` (Task 1).
- Produces:
  - `detect_pkg_manager` → prints one of `brew apt dnf pacman apk zypper`, or fails.
  - `install_nano_package` → installs GNU nano via the detected manager.
  - `resolve_nano` → prints the path to a usable GNU nano, or fails with a diagnostic. This is where the pico-on-PATH check lives.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-install-nano.sh` before the summary:

```bash
echo
echo "== nano resolution =="

test_resolve_nano() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/good" "9.1"
    make_stub_nano "$tmp/ancient" "2.9.7"
    make_stub_pico "$tmp/pico"

    local saved_path="$PATH"

    PATH="$tmp/good:$saved_path"
    assert_eq "$tmp/good/nano" "$(resolve_nano 2>/dev/null)" "modern nano is accepted"

    PATH="$tmp/ancient:$saved_path"
    assert_fail 'resolve_nano >/dev/null 2>&1' "nano 2.9.7 is rejected (below 4.0)"

    PATH="$tmp/pico:$saved_path"
    assert_fail 'resolve_nano >/dev/null 2>&1' "pico is rejected"

    # The pico rejection must explain itself — this is the single most likely
    # failure a macOS student hits.
    local msg; msg="$(PATH="$tmp/pico:$saved_path" resolve_nano 2>&1 || true)"
    assert_contains "$msg" "pico" "pico rejection names pico"

    PATH="$saved_path"
    rm -rf "$tmp"
}

test_resolve_nano
```

- [ ] **Step 2: Run test to verify it fails**

```bash
./tests/test-install-nano.sh
```

Expected: FAIL — `resolve_nano: command not found`.

- [ ] **Step 3: Write minimal implementation**

Append to `install_nano.sh`:

```bash
# ---------------------------------------------------------------------------
# Installing nano
# ---------------------------------------------------------------------------
detect_pkg_manager() {
    local mgr
    for mgr in brew apt-get dnf pacman apk zypper; do
        if command -v "$mgr" >/dev/null 2>&1; then
            printf '%s\n' "${mgr%-get}"
            return 0
        fi
    done
    return 1
}

install_nano_package() {
    local mgr
    mgr="$(detect_pkg_manager)" || {
        log_err "No supported package manager found (brew, apt-get, dnf, pacman, apk, zypper)."
        return 1
    }

    log_step "Installing GNU nano via $mgr..."
    if [[ -n "$DRY_RUN" ]]; then
        log_info "[dry-run] would install nano with $mgr"
        return 0
    fi

    local sudo_cmd=""
    [[ "$mgr" != "brew" && "$(id -u)" -ne 0 ]] && sudo_cmd="sudo"

    case "$mgr" in
        brew)   brew install nano ;;
        apt)    $sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y nano ;;
        dnf)    $sudo_cmd dnf install -y nano ;;
        pacman) $sudo_cmd pacman -S --noconfirm nano ;;
        apk)    $sudo_cmd apk add nano ;;
        zypper) $sudo_cmd zypper install -y nano ;;
    esac
}

# Find a usable GNU nano on PATH, or explain precisely why there isn't one.
resolve_nano() {
    local bin version
    bin="$(command -v nano 2>/dev/null)" || {
        log_err "nano is not on PATH."
        return 1
    }

    if ! version="$(nano_version "$bin")"; then
        log_err "'$bin' is not GNU nano."
        if [[ "$(uname -s)" == "Darwin" && "$bin" == "/usr/bin/nano" ]]; then
            log_err "On macOS, /usr/bin/nano is UW pico — a different editor that
has no syntax highlighting and none of the settings this script writes.
GNU nano is installed, but your PATH still finds /usr/bin first.
Put your Homebrew prefix ahead of /usr/bin in your shell config, open a
new terminal, and run this script again."
        fi
        return 1
    fi

    if ! version_at_least "$version" "$MIN_NANO_VERSION"; then
        log_err "Found GNU nano $version, but this config needs $MIN_NANO_VERSION or newer.
Upgrade nano and run this script again."
        return 1
    fi

    printf '%s\n' "$bin"
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
./tests/test-install-nano.sh
```

Expected: the suite reports `0 failed`.

- [ ] **Step 5: Verify the real macOS path end to end**

```bash
brew install nano && source ./install_nano.sh && resolve_nano
```

Expected: prints the Homebrew nano path (`/opt/homebrew/bin/nano` on Apple silicon), not `/usr/bin/nano`.

- [ ] **Step 6: Commit**

```bash
git add install_nano.sh tests/test-install-nano.sh
git commit -m "feat: install GNU nano and reject pico on the macOS PATH"
```

---

### Task 8: Community syntax pack sync

**Files:**
- Modify: `install_nano.sh`
- Modify: `tests/test-install-nano.sh`

**Interfaces:**
- Consumes: `SYNTAX_DIR`, `SYNTAX_REPO`, `NO_SYNTAX`, `DRY_RUN` (Task 1).
- Produces: `sync_syntax_pack` → clones on first run, fast-forward pulls on rerun, skips and warns on a dirty clone, no-ops under `--no-syntax` or `--dry-run`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-install-nano.sh` before the summary:

```bash
echo
echo "== syntax pack sync =="

test_sync_syntax_pack() {
    local tmp; tmp="$(mktemp -d)"
    local saved_dir="$SYNTAX_DIR" saved_repo="$SYNTAX_REPO"
    local saved_nosyn="$NO_SYNTAX" saved_dry="$DRY_RUN"

    # Build a local git repo to clone, so the test never touches the network.
    mkdir -p "$tmp/origin"
    git -C "$tmp/origin" init -q
    printf 'syntax "fake" "\\.fake$"\n' > "$tmp/origin/fake.nanorc"
    git -C "$tmp/origin" add -A
    git -C "$tmp/origin" -c user.email=t@t -c user.name=t commit -qm init

    SYNTAX_DIR="$tmp/clone"
    SYNTAX_REPO="$tmp/origin"
    NO_SYNTAX=""; DRY_RUN=""

    sync_syntax_pack >/dev/null 2>&1
    assert_ok "[ -f '$tmp/clone/fake.nanorc' ]" "first run clones the pack"

    # Rerun on a clean clone must succeed and leave the file in place.
    sync_syntax_pack >/dev/null 2>&1
    assert_ok "[ -f '$tmp/clone/fake.nanorc' ]" "rerun on clean clone succeeds"

    # A dirty clone must be left alone, not clobbered.
    printf 'local edit\n' >> "$tmp/clone/fake.nanorc"
    sync_syntax_pack >/dev/null 2>&1
    assert_contains "$(cat "$tmp/clone/fake.nanorc")" "local edit" \
        "dirty clone is not overwritten"

    # --no-syntax must not create anything.
    SYNTAX_DIR="$tmp/skipped"; NO_SYNTAX=1
    sync_syntax_pack >/dev/null 2>&1
    assert_fail "[ -d '$tmp/skipped' ]" "--no-syntax creates nothing"

    # --dry-run must not create anything either.
    SYNTAX_DIR="$tmp/dry"; NO_SYNTAX=""; DRY_RUN=1
    sync_syntax_pack >/dev/null 2>&1
    assert_fail "[ -d '$tmp/dry' ]" "--dry-run creates nothing"

    SYNTAX_DIR="$saved_dir"; SYNTAX_REPO="$saved_repo"
    NO_SYNTAX="$saved_nosyn"; DRY_RUN="$saved_dry"
    rm -rf "$tmp"
}

test_sync_syntax_pack
```

- [ ] **Step 2: Run test to verify it fails**

```bash
./tests/test-install-nano.sh
```

Expected: FAIL — `sync_syntax_pack: command not found`.

- [ ] **Step 3: Write minimal implementation**

Append to `install_nano.sh`:

```bash
# nano ships 39 syntax definitions (44 counting syntax/extra). The community
# pack at scopatz/nanorc carries roughly 180, covering yaml variants, toml,
# dockerfile, terraform, nginx, systemd units and the rest of what a student in
# a networking course actually opens.
sync_syntax_pack() {
    if [[ -n "$NO_SYNTAX" ]]; then
        log_info "Skipping the community syntax pack (--no-syntax)."
        return 0
    fi

    if [[ -n "$DRY_RUN" ]]; then
        log_info "[dry-run] would sync $SYNTAX_REPO → $SYNTAX_DIR"
        return 0
    fi

    if ! command -v git >/dev/null 2>&1; then
        log_warn "git is not installed; skipping the community syntax pack.
The definitions shipped with nano will still be used."
        return 0
    fi

    log_step "Syncing extra syntax definitions..."

    if [[ ! -d "$SYNTAX_DIR/.git" ]]; then
        if [[ -d "$SYNTAX_DIR" ]]; then
            log_warn "$SYNTAX_DIR exists but is not a git clone; leaving it alone."
            return 0
        fi
        git clone --depth 1 --quiet "$SYNTAX_REPO" "$SYNTAX_DIR" || {
            log_warn "Could not clone the syntax pack. The definitions shipped
with nano will still be used."
            return 0
        }
        log_ok "Cloned the community syntax pack to $SYNTAX_DIR"
        return 0
    fi

    # Never discard someone's local edits to a syntax file.
    if [[ -n "$(git -C "$SYNTAX_DIR" status --porcelain)" ]]; then
        log_warn "$SYNTAX_DIR has local changes; not pulling."
        return 0
    fi

    git -C "$SYNTAX_DIR" pull --ff-only --quiet \
        || log_warn "Could not update the syntax pack; using what is already there."
    log_ok "Syntax pack is up to date."
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
./tests/test-install-nano.sh
```

Expected: the suite reports `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add install_nano.sh tests/test-install-nano.sh
git commit -m "feat: sync the scopatz community syntax pack"
```

---

### Task 9: Wire up main, dry-run, and --set-editor

**Files:**
- Modify: `install_nano.sh`
- Modify: `tests/test-install-nano.sh`

**Interfaces:**
- Consumes: everything from Tasks 2–8.
- Produces: `set_default_editor` → appends `EDITOR`/`VISUAL` exports to the shell rc inside their own managed block; a complete `main`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-install-nano.sh` before the summary:

```bash
echo
echo "== end to end =="

test_dry_run_writes_nothing() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/bin" "9.1"
    mkdir -p "$tmp/home"

    local saved_path="$PATH"
    PATH="$tmp/bin:$saved_path"

    HOME="$tmp/home" ./install_nano.sh --dry-run --yes >/dev/null 2>&1

    assert_fail "[ -f '$tmp/home/.nanorc' ]" "--dry-run writes no .nanorc"
    assert_fail "[ -d '$tmp/home/.nano' ]"   "--dry-run clones nothing"

    PATH="$saved_path"
    rm -rf "$tmp"
}

test_real_run_writes_config() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/bin" "9.1"
    mkdir -p "$tmp/home"

    local saved_path="$PATH"
    PATH="$tmp/bin:$saved_path"

    HOME="$tmp/home" ./install_nano.sh --yes --no-syntax >/dev/null 2>&1

    assert_ok "[ -f '$tmp/home/.nanorc' ]" "real run writes .nanorc"
    assert_contains "$(cat "$tmp/home/.nanorc")" "set linenumbers" \
        "written .nanorc carries the core settings"
    assert_contains "$(cat "$tmp/home/.nanorc")" "bind ^S savefile main" \
        "written .nanorc carries the ^S binding"

    PATH="$saved_path"
    rm -rf "$tmp"
}

test_set_editor_is_opt_in() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/bin" "9.1"
    mkdir -p "$tmp/home"
    touch "$tmp/home/.zshrc"

    local saved_path="$PATH"
    PATH="$tmp/bin:$saved_path"

    HOME="$tmp/home" ./install_nano.sh --yes --no-syntax >/dev/null 2>&1
    assert_not_contains "$(cat "$tmp/home/.zshrc")" "EDITOR" \
        "EDITOR is not exported by default"

    HOME="$tmp/home" ./install_nano.sh --yes --no-syntax --set-editor >/dev/null 2>&1
    assert_contains "$(cat "$tmp/home/.zshrc")" "export EDITOR=nano" \
        "--set-editor exports EDITOR"
    assert_contains "$(cat "$tmp/home/.zshrc")" "export VISUAL=nano" \
        "--set-editor exports VISUAL"

    # Idempotent: a second --set-editor run must not duplicate.
    HOME="$tmp/home" ./install_nano.sh --yes --no-syntax --set-editor >/dev/null 2>&1
    assert_eq "1" "$(grep -c 'export EDITOR=nano' "$tmp/home/.zshrc")" \
        "--set-editor does not duplicate on rerun"

    PATH="$saved_path"
    rm -rf "$tmp"
}

test_dry_run_writes_nothing
test_real_run_writes_config
test_set_editor_is_opt_in
```

These tests invoke the script with a synthetic `HOME`, so the paths must be derived at call time rather than frozen when the file is sourced. In Task 1, change the two declarations to empty strings:

```bash
NANORC=""
SYNTAX_DIR=""
```

and add this function, called from `main` immediately after `parse_args`:

```bash
# Resolve paths at run time, not at source time. Tests run the script under a
# synthetic $HOME, and anything captured when the file was sourced would still
# point at the real home directory.
init_paths() {
    [[ -n "$NANORC" ]]     || NANORC="$HOME/.nanorc"
    [[ -n "$SYNTAX_DIR" ]] || SYNTAX_DIR="$HOME/.nano"
}
```

Tests from Tasks 4–8 that assign `NANORC` and `SYNTAX_DIR` directly keep working, because they call the inner functions rather than `main`.

- [ ] **Step 2: Run test to verify it fails**

```bash
./tests/test-install-nano.sh
```

Expected: FAIL — the dry-run test passes trivially but `test_real_run_writes_config` fails, because `main` still only logs "skeleton only".

- [ ] **Step 3: Write minimal implementation**

Replace `main` in `install_nano.sh` and add `set_default_editor` above it:

```bash
# ---------------------------------------------------------------------------
# Optional: make nano the default editor
# ---------------------------------------------------------------------------
# Off unless asked for. Setting EDITOR touches a second file and changes what
# happens when `git commit` or `crontab -e` opens — a surprise nobody asked for
# when all they wanted was syntax highlighting.
EDITOR_BLOCK_START="# >>> qol nano editor >>>"
EDITOR_BLOCK_END="# <<< qol nano editor <<<"

set_default_editor() {
    local rc
    case "$(basename "${SHELL:-/bin/bash}")" in
        zsh)  rc="$HOME/.zshrc" ;;
        bash) rc="$HOME/.bashrc" ;;
        *)    log_warn "Unrecognised shell ${SHELL:-unset}; not setting EDITOR."
              return 0 ;;
    esac

    if [[ -n "$DRY_RUN" ]]; then
        log_info "[dry-run] would export EDITOR=nano and VISUAL=nano in $rc"
        return 0
    fi

    [[ -f "$rc" ]] || touch "$rc"

    # Reuse the block-removal logic against this block's own markers.
    local saved_start="$BLOCK_START" saved_end="$BLOCK_END"
    BLOCK_START="$EDITOR_BLOCK_START"
    BLOCK_END="$EDITOR_BLOCK_END"
    remove_managed_block "$rc"
    BLOCK_START="$saved_start"
    BLOCK_END="$saved_end"

    cat >> "$rc" <<EOF
$EDITOR_BLOCK_START
# Managed by install_nano.sh — rewritten on every rerun.
export EDITOR=nano
export VISUAL=nano
$EDITOR_BLOCK_END
EOF
    log_ok "Set nano as the default editor in $rc"
}

# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    init_paths

    log_step "nano setup"
    [[ -n "$DRY_RUN" ]] && log_info "Dry run — nothing will be written."

    local bin
    if ! bin="$(resolve_nano 2>/dev/null)"; then
        install_nano_package || exit 1
        if [[ -n "$DRY_RUN" ]]; then
            log_info "[dry-run] stopping here; nano is not actually installed."
            exit 0
        fi
        bin="$(resolve_nano)" || exit 1
    fi

    log_ok "Using $bin ($(nano_version "$bin"))"

    load_nano_help "$bin"
    sync_syntax_pack

    if [[ -n "$DRY_RUN" ]]; then
        log_info "[dry-run] would write this block to $NANORC:"
        render_nanorc
        exit 0
    fi

    write_nanorc
    [[ -n "$SET_EDITOR" ]] && set_default_editor

    echo
    format_font "Config:      $NANORC
Syntax:      $SYNTAX_DIR (community) + the definitions shipped with nano
Cheat sheet: $SCRIPT_DIR/docs/nano-cheatsheet.html
^S saves. ^X exits. M-U undoes, M-E redoes." normal blue
    format_font "nano is ready. Open a new file to see it." bold green
    echo
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
./tests/test-install-nano.sh
```

Expected: the suite reports `0 failed`.

- [ ] **Step 5: Run shellcheck**

```bash
shellcheck install_nano.sh tests/test-install-nano.sh
```

Expected: no errors. Warnings about intentional word-splitting on `$prefixes` (SC2086) and `$sudo_cmd` may be suppressed with a targeted `# shellcheck disable` and a comment saying why.

- [ ] **Step 6: Commit**

```bash
git add install_nano.sh tests/test-install-nano.sh
git commit -m "feat: wire up main with dry-run and opt-in EDITOR export"
```

---

### Task 10: Markdown cheat sheet

**Files:**
- Create: `docs/nano-cheatsheet.md`

**Interfaces:**
- Consumes: the keybinding decisions from Task 5 (`^S` bound, `^Q` not bound, `^Z` left as suspend).
- Produces: the canonical content that Task 11 renders as HTML. If the two ever disagree, this file is right.

- [ ] **Step 1: Write the cheat sheet**

Create `docs/nano-cheatsheet.md`:

```markdown
# nano cheat sheet

`^` means Ctrl. `M-` means Alt on Linux, or Esc-then-key on macOS — press and
release Esc, then the key. Key names are not case sensitive: `^X` is Ctrl and x.

Lines marked **(qol)** exist because of `install_nano.sh`. On a stock nano they
will not work.

## Get out

| Key | Does |
|:--|:--|
| `^X` | Exit. Prompts to save if the file changed. |
| `^S` | Save, no prompt. **(qol)** |
| `^O` | Save As — prompts for the filename. Stock nano's save key. |
| `^C` | Show the cursor's line, column, and character count. Does **not** quit. |

If you are stuck at a prompt, `^C` cancels it.

## Move

| Key | Does |
|:--|:--|
| `^A` / `^E` | Start / end of line. |
| `^Y` / `^V` | Page up / page down. |
| `^_` then a number | Go to that line. |
| `M-\` / `M-/` | Start / end of the file. |
| `M-]` | Jump to the matching bracket. |
| `M-↑` / `M-↓` | Previous / next block of text. |

## Edit

| Key | Does |
|:--|:--|
| `^K` | Cut the current line. Press repeatedly to cut several. |
| `^U` | Paste what was cut. |
| `M-6` | Copy the current line without cutting it. |
| `M-U` | Undo. |
| `M-E` | Redo. |
| `M-3` | Comment or uncomment the line, using the right character for the file type. |
| `Tab` / `Shift-Tab` | Indent / unindent. Works on a selection too. |
| `^T` | Run a command and read its output. |

`^Z` suspends nano and drops you back to the shell. Type `fg` to return. It is
not undo — undo is `M-U`.

## Select and copy

| Key | Does |
|:--|:--|
| `^6` or `M-A` | Start selecting. Move the cursor to extend. |
| `^K` | Cut the selection. |
| `M-6` | Copy the selection. |
| `^6` again | Cancel the selection. |

Copying *out of* nano into another application is your terminal's job, not
nano's — use the terminal's own select-and-copy.

## Search and replace

| Key | Does |
|:--|:--|
| `^W` | Search forwards. |
| `M-W` | Repeat the last search. |
| `^\` | Search and replace. `A` at the prompt replaces all. |
| `M-R` | Toggle regular expressions in the search prompt. |
| `M-C` | Toggle case sensitivity. |

Search history is kept between sessions **(qol)** — press ↑ at the search prompt.

## Files and buffers

| Key | Does |
|:--|:--|
| `^R` | Read another file into a new buffer. **(qol** — stock nano inserts it into the current one.**)** |
| `M-<` / `M->` | Previous / next buffer. |
| `^R` then `^T` | Open the file browser. |

## Help

| Key | Does |
|:--|:--|
| `^G` | Full help, inside nano. |
| `M-X` | Show or hide the two-line help bar at the bottom. |

## What the qol config changes

- Line numbers down the left margin, and a faint rule at column 80.
- Syntax highlighting for roughly 180 file types.
- Tab inserts four spaces rather than a tab character.
- Long lines wrap on screen at word boundaries without newlines being inserted.
- Reopening a file returns you to where you left off.
- `^S` saves.
- `^Q` is deliberately **not** bound to quit. On many terminals `^Q` is flow
  control and can make the terminal look frozen. Use `^X`.
```

- [ ] **Step 2: Verify every binding against the installed nano**

```bash
source ./install_nano.sh && load_nano_help "$(resolve_nano)" && nano --help | grep -E 'linenumbers|indicator|stateflags'
```

Then open a scratch file and confirm by hand: `^S` saves, `M-U` undoes, `M-3` comments a line in a `.sh` file, `^R` opens a new buffer rather than inserting inline.

Expected: all four behave as documented. Fix the table, not the config, if any disagree.

- [ ] **Step 3: Commit**

```bash
git add docs/nano-cheatsheet.md
git commit -m "docs: add nano keybinding cheat sheet"
```

---

### Task 11: HTML cheat sheet and README

**Files:**
- Create: `docs/nano-cheatsheet.html`
- Modify: `README.md`
- Reference: `~/vaults/dojobrain/30-references/design-system/itdojo-design-system.html`

**Interfaces:**
- Consumes: `docs/nano-cheatsheet.md` (Task 10) as the content source of truth.
- Produces: nothing consumed by later tasks. This is the last task.

- [ ] **Step 1: Copy the design tokens**

Open `~/vaults/dojobrain/30-references/design-system/itdojo-design-system.html` and copy its `:root` block (lines 34–103) and its `[data-theme="dark"]` block (lines 110–140) verbatim into the new file's inline `<style>`. Copy the early theme-setting `<script>` (lines 9–19) as well, changing the localStorage key from `itdojo-theme` to `nano-cheatsheet-theme`.

Do **not** copy the `<link>` tags to Google Fonts. Replace the two font tokens with fallback-only stacks:

```css
--font-text: 'Roboto', system-ui, -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif;
--font-mono: 'Fira Code', ui-monospace, 'SF Mono', Menlo, 'Cascadia Code', Consolas, monospace;
```

The named families are kept first so the page uses them when a machine happens to have them installed, and falls back cleanly when it does not. The page must render correctly with no network access.

- [ ] **Step 2: Build the page**

Structure:

- `<h1>` "nano cheat sheet", with the `⛩` glyph in a mono uppercase letter-spaced eyebrow above it, per the design system's caption rule (mono, uppercase, `letter-spacing: 0.15em`, `--gray-500`).
- A lede paragraph in `--gray-900` explaining `^` and `M-`.
- A prominent panel at the top holding only `^X` and `^S` — the two keys a stuck student needs. Use card variant D (3px jade left border, `--gray-100` other borders).
- One section per heading in the markdown file, each a card variant B (outlined, `--gray-300` border on white), containing a two-column table.
- Every key rendered as `<kbd>`, styled from the inline-code rule: `--lavender` background, `--violet` text, `--r-xs` radius, mono at `0.92em`, `2px 6px` padding.
- Rows sourced from `install_nano.sh` get a badge reading `QOL` — pill, mono, uppercase, `letter-spacing: 0.08em`, weight 700, `--mint` background, `#1E7A37` text, with the 6px `::before` dot.
- A `WARN` callout for the `^Q` note: 3px `--warning` left border, `rgba(216, 156, 44, 0.18)` background, `--violet` body text, radius `0 var(--r-sm) var(--r-sm) 0`, with the icon prefix `WARN` in mono uppercase weight 700.
- A theme toggle button in the top right, styled as the Ghost button variant (transparent, `--violet` text, no border, `--lavender` on hover).
- Sections laid out in a CSS grid, `repeat(auto-fit, minmax(320px, 1fr))`, `gap: var(--sp-5)`, collapsing to one column below 700px.

- [ ] **Step 3: Add the print stylesheet**

```css
@media print {
  :root { color-scheme: light; }
  html, body { background: #FFFFFF !important; color: #14102B !important; }
  .theme-toggle { display: none; }
  main { max-width: none; padding: 0; }
  .grid { grid-template-columns: repeat(2, 1fr); gap: 8px; }
  .card { break-inside: avoid; box-shadow: none; border: 1px solid #BEB9CC; }
  kbd { background: #F1ECFA !important; color: #3E3566 !important; border: 1px solid #BEB9CC; }
  @page { margin: 12mm; }
}
```

The dark-theme token overrides must not leak into print — force the light values explicitly, because a student printing from a dark-themed browser would otherwise get a page of solid ink.

- [ ] **Step 4: Verify it is self-contained**

```bash
grep -nE 'https?://|src=|@import|<link' docs/nano-cheatsheet.html
```

Expected: no matches other than URLs inside HTML comments or visible text. Any `<link>`, `<script src>`, `@import`, or remote `url()` is a defect — the page has to work on a lab machine with no internet.

- [ ] **Step 5: Verify it renders in both themes and prints to one page**

```bash
open docs/nano-cheatsheet.html
```

Check by hand:
- Light and dark both legible; the toggle switches and the choice survives a reload.
- No horizontal scrolling at 375px width.
- Print preview (Cmd-P) fits on one page in light colours with the toggle hidden.
- Every key and every row matches `docs/nano-cheatsheet.md` exactly.

- [ ] **Step 6: Add the README rows**

Add to the tool table in `README.md`, keeping the existing column order and the alphabetical-by-path placement used by its neighbours:

```markdown
| [install_nano.sh](install_nano.sh) | macOS, Linux | Sets up GNU nano for people who actually edit in it: syntax highlighting for ~180 file types, line numbers, four-space indentation, soft wrapping at word boundaries, cursor-position memory, and a `^S` save binding. Writes one managed block into `~/.nanorc` that is rewritten whole on rerun, so reruns cannot duplicate config. Idempotent; supports `--dry-run`, `--yes`, `--no-syntax` and `--set-editor`.<br><br>Rather than mapping nano versions to features, it greps `nano --help` for each directive it wants to write. Distro builds configured with `--enable-tiny` omit options regardless of their version number, so a version table would be wrong on exactly the machines most likely to have one.<br><br>**macOS note:** `/usr/bin/nano` is not nano — it is UW PICO 5.09, with no syntax highlighting and none of the modern settings. The script installs real GNU nano via Homebrew and refuses to write a config if PATH still resolves `nano` to `/usr/bin/nano`, rather than writing a file that would error on every launch. |
| [docs/nano-cheatsheet.html](docs/nano-cheatsheet.html) | — | Printable one-page nano keybinding reference in the IT Dojo design system. Light and dark, self-contained, no network needed. Plain-text version at [docs/nano-cheatsheet.md](docs/nano-cheatsheet.md). |
```

- [ ] **Step 7: Run the full suite one last time**

```bash
./tests/test-install-nano.sh && shellcheck install_nano.sh tests/test-install-nano.sh
```

Expected: `0 failed`, and no shellcheck errors.

- [ ] **Step 8: Commit**

```bash
git add docs/nano-cheatsheet.html README.md
git commit -m "docs: add printable nano cheat sheet and README entries"
```

---

## Self-Review Notes

Spec coverage check, section by section:

| Spec section | Task |
|:--|:--|
| Verified environment facts | Encoded as Global Constraints and in Task 2/3 comments |
| 1. Detection and install | Task 7 |
| 2. Capability probe | Task 3 |
| 3. Config rendering | Tasks 5 and 6 |
| 4. Syntax highlighting | Tasks 4 and 8 |
| 5. Keybindings | Task 5 |
| 6. Flags | Tasks 1 and 9 |
| 7. Cheat sheet | Tasks 10 and 11 |
| Testing | Distributed across every task; Task 9 step 4 and Task 11 step 7 are the full-suite gates |

One deviation from the spec, flagged in File Structure above: the nanorc body lives in a heredoc inside `render_nanorc` rather than in a separate `nanorc.template`, because a third of its lines are conditional and a template file would need its own templating layer.
