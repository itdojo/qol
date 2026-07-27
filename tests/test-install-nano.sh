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
    assert_eq "" "$ASSUME_YES" "no flags leaves ASSUME_YES unset"
    assert_eq "" "$NO_SYNTAX"  "no flags leaves NO_SYNTAX unset"
    assert_eq "" "$SET_EDITOR" "no flags leaves SET_EDITOR unset"
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

echo
echo "== version comparison =="

assert_ok   'version_at_least 9.1 4.0'   "9.1 >= 4.0"
assert_ok   'version_at_least 4.0 4.0'   "4.0 >= 4.0 (equal)"
assert_ok   'version_at_least 10.0 9.1'  "10.0 >= 9.1 (numeric, not lexical)"
assert_ok   'version_at_least 5.10 5.9'  "5.10 >= 5.9 (numeric minor)"
assert_fail 'version_at_least 2.9 4.0'   "2.9 < 4.0"
assert_fail 'version_at_least 3.2 4.0'   "3.2 < 4.0"
assert_ok   'version_at_least 4.0.1 4.0' "4.0.1 >= 4.0 (patch level)"
assert_ok   'version_at_least 4.0 4.0.0'   "4.0 >= 4.0.0 (equal, unequal depth)"
assert_ok   'version_at_least 4.0.0 4.0'   "4.0.0 >= 4.0 (equal, unequal depth reversed)"
assert_ok   'version_at_least 9.1 9.1.0'   "9.1 >= 9.1.0 (equal, unequal depth)"
assert_fail 'version_at_least 4.0 4.0.1'   "4.0 < 4.0.1"
assert_ok   'version_at_least 4.1 4.0.9'   "4.1 >= 4.0.9 (minor beats patch)"
assert_ok   'version_at_least 9.1.2.3 9.1'     "four-field version compares cleanly"
assert_ok   'version_at_least 9.1.2.3 9.1.2'   "four-field version, third field ties"
assert_fail 'version_at_least 9.1.2.3 9.2'     "four-field version, minor is older"
assert_ok   'version_at_least 5.0-rc1 5.0'     "suffixed field truncates to its digits"
assert_fail 'version_at_least 4.0-rc1 4.1'     "suffixed field still compares as older"

echo
echo "== nano detection =="

# Build a fake nano on disk. GNU nano's real first line is exactly
# " GNU nano, version 9.1" — leading space, comma — per src/nano.c:657.
#
# The --help body is the real layout, copied from `nano --help` on GNU nano
# 9.1: space-padded columns, no comma after the short option, and a
# `--longopt=<value>` form for the options that take an argument. An earlier
# version of this helper emitted ` -l, --linenumbers` with the option at end
# of line, which meant every fixture in this suite exercised only the `$`
# branch of nano_supports' `--$1([,= ]|$)` character class. Proven toothless:
# narrowing that class to `[,=]` left the suite at 238 run / 0 failed while
# both gated directives were silently written as comments against real nano.
NANO_HELP_FIXTURE=' Option         Long option             Meaning
 -J <number>    --guidestripe=<number>  Show a guiding bar at this column
 -l             --linenumbers           Show line numbers in front of the text
 -q             --indicator             Show a position+portion indicator
 -%             --stateflags            Show some states on the title bar'

# The same, minus everything a --enable-tiny build compiles out.
NANO_HELP_FIXTURE_TINY=' Option         Long option             Meaning
 -l             --linenumbers           Show line numbers in front of the text'

make_stub_nano() {
    local dir="$1" version="$2"
    mkdir -p "$dir"
    cat > "$dir/nano" <<STUB
#!/usr/bin/env bash
case "\$1" in
    --version) printf ' GNU nano, version %s\n' "$version"; exit 0 ;;
    --help)    printf '%s\n' "$NANO_HELP_FIXTURE"; exit 0 ;;
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

    # A stub that claims "GNU nano" but prints no version number. The sed
    # pattern in nano_version won't match, so without the post-match regex
    # guard it would echo the raw line back and return 0. One-off, unlike
    # make_stub_nano/make_stub_pico, so it's defined inline rather than
    # promoted to a top-level helper.
    mkdir -p "$tmp/noversion"
    cat > "$tmp/noversion/nano" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    --version) printf ' GNU nano\n'; exit 0 ;;
esac
exit 1
STUB
    chmod +x "$tmp/noversion/nano"
    assert_fail 'nano_version '"$tmp"'/noversion/nano' "GNU nano with no version number is rejected"

    rm -rf "$tmp"
}

test_nano_version

echo
echo "== capability probe =="

test_capability_probe() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/full" "9.1"

    # A --enable-tiny build: modern version number, but the gated options are
    # compiled out. This is why we probe --help instead of comparing versions.
    mkdir -p "$tmp/tiny"
    cat > "$tmp/tiny/nano" <<STUB
#!/usr/bin/env bash
case "\$1" in
    --version) printf ' GNU nano, version 8.0\n'; exit 0 ;;
    --help)    printf '%s\n' "$NANO_HELP_FIXTURE_TINY"; exit 0 ;;
esac
exit 1
STUB
    chmod +x "$tmp/tiny/nano"

    load_nano_help "$tmp/full/nano"
    assert_ok 'nano_supports linenumbers' "full build supports linenumbers"
    assert_ok 'nano_supports indicator'   "full build supports indicator"
    assert_ok 'nano_supports stateflags'  "full build supports stateflags"
    assert_fail 'nano_supports zero'      "stub does not advertise zero"

    # nano_supports' character class has three branches — `,`, `=`, and a
    # space — plus an end-of-line anchor, and every one of them needs a
    # fixture that actually reaches it. The three assertions above cover the
    # space branch (real nano pads its columns with spaces). This covers the
    # `=` branch: options that take an argument are printed as
    # `--guidestripe=<number>`, so a class without `=` would fail to see
    # them entirely.
    assert_ok 'nano_supports guidestripe' \
        "an option printed in --longopt=<value> form is still detected"

    load_nano_help "$tmp/tiny/nano"
    assert_ok   'nano_supports linenumbers' "tiny build supports linenumbers"
    assert_fail 'nano_supports indicator'   "tiny build lacks indicator despite 8.0"
    assert_fail 'nano_supports stateflags'  "tiny build lacks stateflags despite 8.0"
    assert_fail 'nano_supports guidestripe' "tiny build lacks guidestripe too"

    # A substring must not produce a false positive: --line must not match
    # --linenumbers.
    assert_fail 'nano_supports line' "partial option name does not match"

    # The remaining branch: the `$` anchor. Real nano never prints an option
    # at end of line, so no faithful fixture reaches it — but a truncated or
    # differently-formatted --help could, and dropping `$` from the class
    # would then silently report a supported option as missing. One
    # deliberately unfaithful fixture, kept small and labelled as such.
    nano_help_cache=' -q             --indicator'
    assert_ok 'nano_supports indicator' \
        "an option at end of line is still detected (the \$ branch)"

    rm -rf "$tmp"
}

test_capability_probe

test_capability_probe_errors() {
    local tmp; tmp="$(mktemp -d)"

    assert_fail 'load_nano_help /nonexistent/nano' \
        "load_nano_help fails on a nonexistent path"
    assert_fail 'nano_supports linenumbers' \
        "no probe matches after a failed load (nonexistent path)"

    mkdir -p "$tmp/notexec"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/notexec/nano"
    chmod -x "$tmp/notexec/nano"
    assert_fail 'load_nano_help '"$tmp"'/notexec/nano' \
        "load_nano_help fails on a non-executable file"
    assert_fail 'nano_supports linenumbers' \
        "no probe matches after a failed load (not executable)"

    # Real pico, when present (macOS ships it at /usr/bin/nano). The guard is
    # a capability probe, not a platform claim: on Linux /usr/bin/nano is
    # normally real GNU nano, so the block simply does not run there.
    #
    # TERM=dumb and </dev/null are load-bearing here, exactly as in
    # nano_version above: an unguarded `/usr/bin/nano --version` blocks for
    # tens of seconds on terminfo/terminal detection, and on a real tty it
    # can leave pico's full-screen editor sitting there. Do not copy this
    # invocation without both.
    if [[ -x /usr/bin/nano ]] && ! TERM=dumb /usr/bin/nano --version </dev/null 2>/dev/null | grep -q 'GNU nano'; then
        assert_fail 'load_nano_help /usr/bin/nano' \
            "load_nano_help fails against real pico"
        assert_fail 'nano_supports linenumbers' \
            "no probe matches after a failed load (real pico)"
    fi

    # Staleness: a failed load after a successful one must not leave the
    # previous binary's capabilities readable.
    make_stub_nano "$tmp/full" "9.1"
    load_nano_help "$tmp/full/nano"
    assert_ok 'nano_supports linenumbers' \
        "sanity: successful load reports capabilities"
    assert_fail 'load_nano_help /nonexistent/nano' \
        "subsequent load against a bad path fails"
    assert_fail 'nano_supports linenumbers' \
        "stale capabilities from the prior successful load are not reported"

    rm -rf "$tmp"
}

test_capability_probe_errors

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
    QOL_NANO_PREFIXES="$tmp/share/nano
$tmp/deb/nano-syntax-highlighting
$tmp/nonexistent"

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

    # Regression: a prefix path containing a space must survive intact.
    # Splitting on IFS's default (space/tab/newline) would break "share nano"
    # into "share" and "nano", neither of which exists, and the directory
    # would silently vanish from the output.
    mkdir -p "$tmp/share nano"
    touch "$tmp/share nano/perl.nanorc"
    SYNTAX_DIR="$tmp/absent"
    QOL_NANO_PREFIXES="$tmp/share nano"
    out="$(syntax_include_globs)"
    assert_contains "$out" "$tmp/share nano/*.nanorc" \
        "prefix path containing a space is kept intact"

    # syntax_include_globs must not leak a modified IFS to its caller.
    local ifs_before ifs_after
    ifs_before="$IFS"
    syntax_include_globs >/dev/null
    ifs_after="$IFS"
    assert_eq "$ifs_before" "$ifs_after" "IFS is restored after the call"

    SYNTAX_DIR="$saved_dir"
    QOL_NANO_PREFIXES="$saved_prefixes"
    rm -rf "$tmp"
}

test_syntax_include_globs

# This suite otherwise runs under bash only, which is exactly how the
# word-splitting bug survived: `for dir in $prefixes` relies on bash's
# unquoted-expansion word-splitting, but zsh leaves an unquoted expansion
# unsplit even with IFS set, so the whole newline-separated prefix list
# arrived as one unmatched path and the function silently emitted nothing
# when this script was sourced into a zsh shell — exactly what the plan's
# own verification steps (and this machine's zsh login shell) do. Shell out
# to a real zsh and prove both prefixes still come back split.
test_syntax_include_globs_zsh() {
    if ! command -v zsh >/dev/null 2>&1; then
        printf '  skip syntax_include_globs splits correctly under zsh (no zsh on PATH)\n'
        return 0
    fi

    local tmp; tmp="$(mktemp -d)"
    mkdir -p "$tmp/a" "$tmp/b"
    touch "$tmp/a/one.nanorc" "$tmp/b/two.nanorc"

    local out
    out="$(SYNTAX_DIR="$tmp/absent" QOL_NANO_PREFIXES="$tmp/a
$tmp/b" zsh -c "source '$SCRIPT_UNDER_TEST'; syntax_include_globs" 2>&1)"

    assert_contains "$out" "$tmp/a/*.nanorc" \
        "zsh: first prefix glob present"
    assert_contains "$out" "$tmp/b/*.nanorc" \
        "zsh: second prefix glob present"

    rm -rf "$tmp"
}

test_syntax_include_globs_zsh

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
    nano_help_cache="$NANO_HELP_FIXTURE"
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

    # Anchored to a line start (leading newline), same reasoning as the
    # gated-directive checks below: assert_contains is a substring match,
    # and an unanchored "bind ^Z suspend main" needle would also match a
    # hypothetical commented-out form of the same text.
    assert_contains "$out" "
bind ^Z suspend main" "binding: ^Z suspends (stock nano leaves it doing nothing)"

    # Anchored to a line start (leading newline) so these cannot pass against
    # the commented-out form gated_directive emits on an unsupported build —
    # "# set indicator   # unavailable ..." also contains the bare substring
    # "set indicator", so an unanchored assert_contains would pass either way.
    assert_contains "$out" "
set indicator" "gated: indicator written"
    assert_contains "$out" "
set stateflags" "gated: stateflags written"

    # Every other line in this student-facing file explains itself. These two
    # were the only directives with no trailing comment; the explanation is
    # aligned into the same column the hand-written ones use.
    assert_eq "1" "$(printf '%s\n' "$out" | grep -cE '^set indicator +# .')" \
        "gated: indicator carries a trailing explanatory comment"
    assert_eq "1" "$(printf '%s\n' "$out" | grep -cE '^set stateflags +# .')" \
        "gated: stateflags carries a trailing explanatory comment"

    # Excluded by design — these must never appear.
    assert_not_contains "$out" "set mouse"   "excluded: mouse"
    assert_not_contains "$out" "set minibar" "excluded: minibar"
    assert_not_contains "$out" "set zero"    "excluded: zero"
    assert_not_contains "$out" "set backup"  "excluded: backup"
    assert_not_contains "$out" "titlecolor"  "excluded: interface colours"
    # ^Q is left alone, not rebound: since nano 2.9.0 it starts a backward
    # search, and this config's floor is 4.0. (The earlier rationale here —
    # that ^Q is XOFF — was wrong: nano disables flow control unless
    # `set preserve` is used, which is why that directive exists at all.)
    assert_not_contains "$out" "bind ^Q" \
        "excluded: ^Q is left as nano's own backward search, not rebound"

    # Include order: community pack must appear before the shipped pack.
    local community_line shipped_line
    community_line="$(printf '%s\n' "$out" | grep -n 'home/.nano/\*.nanorc' | cut -d: -f1)"
    shipped_line="$(printf '%s\n' "$out" | grep -n 'share/nano/\*.nanorc' | cut -d: -f1)"
    assert_ok "[ $community_line -lt $shipped_line ]" \
        "community include precedes shipped include"

    # --- tiny build ---
    # shellcheck disable=SC2034  # read by nano_supports (via render_nanorc), not directly in this file
    nano_help_cache="$NANO_HELP_FIXTURE_TINY"
    out="$(render_nanorc)"
    assert_contains "$out" "set linenumbers" "tiny: core still written"
    assert_not_contains "$out" "
set indicator" "tiny: indicator not written as a directive"
    assert_contains "$out" "# set indicator" "tiny: indicator left as a comment"
    assert_contains "$out" "nano 5.0" "tiny: comment names the enabling version"
    assert_contains "$out" "# set stateflags" "tiny: stateflags left as a comment"
    assert_contains "$out" "nano 5.3" "tiny: stateflags comment names 5.3"

    # --- no syntax directories at all ---
    # Neither the community dir nor any shipped prefix exists. render_nanorc
    # must still succeed and emit a well-formed block with no include line at
    # all — never an "include ""` for a glob that resolved to nothing.
    SYNTAX_DIR="$tmp/nonexistent-community"
    QOL_NANO_PREFIXES="$tmp/nonexistent-shipped"
    local rc
    out="$(render_nanorc)"; rc=$?
    assert_eq "0" "$rc" "no syntax dirs: render_nanorc exits 0"
    assert_contains "$out" "$BLOCK_START" "no syntax dirs: block start marker present"
    assert_contains "$out" "$BLOCK_END"   "no syntax dirs: block end marker present"
    assert_not_contains "$out" 'include ""' "no syntax dirs: no empty include line"

    SYNTAX_DIR="$saved_dir"
    QOL_NANO_PREFIXES="$saved_prefixes"
    rm -rf "$tmp"
}

test_render_nanorc

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
    # shellcheck disable=SC2034  # read by nano_supports (via write_nanorc -> render_nanorc), not directly in this file
    nano_help_cache="$NANO_HELP_FIXTURE"

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

    # A third run: append a line AFTER the end marker, the way a user would if
    # they mistook the trailing edge of the file for free space.
    #
    # remove_managed_block only excises BLOCK_START..BLOCK_END inclusive (see
    # its awk: skip goes 0->1 on the start marker and back 1->0 on the end
    # marker, on the very same line as the end marker) — it does not touch
    # anything after BLOCK_END. Because write_nanorc always re-appends the
    # fresh block at the end of the file, a line that used to sit after the
    # old block does NOT get dropped; it survives and is relocated to just
    # before the new block. This matches install_zsh_starship.sh's
    # remove_managed_block, which has the identical excise-only behaviour.
    printf 'set mouse\n' >> "$NANORC"
    write_nanorc
    local third; third="$(cat "$NANORC")"
    assert_contains "$third" "
set mouse" "line appended after the end marker survives (relocated, not lost)"

    # And it must end up BEFORE the new block, not inside/after it — otherwise
    # this would silently reintroduce a second copy of "set mouse" forever.
    local mouse_line block_line
    mouse_line="$(printf '%s\n' "$third" | grep -nF 'set mouse' | cut -d: -f1)"
    block_line="$(printf '%s\n' "$third" | grep -nF "$BLOCK_START" | cut -d: -f1)"
    assert_ok "[ $mouse_line -lt $block_line ]" \
        "relocated line sits before the re-appended block"
    assert_eq "1" "$(grep -cF "$BLOCK_START" "$NANORC")" \
        "still exactly one start marker after the stale-line rerun"

    # File mode must survive: replace_file_contents carries the mode across
    # the atomic rename (it no longer preserves the inode — see its comment).
    chmod 644 "$NANORC"
    local mode_before
    # shellcheck disable=SC2012  # permission string only; filename is a fixed fixture path with no odd characters
    mode_before="$(ls -l "$NANORC" | cut -c1-10)"
    write_nanorc
    # shellcheck disable=SC2012  # permission string only; filename is a fixed fixture path with no odd characters
    assert_eq "$mode_before" "$(ls -l "$NANORC" | cut -c1-10)" "file mode preserved"

    NANORC="$saved_rc"
    SYNTAX_DIR="$saved_dir"
    QOL_NANO_PREFIXES="$saved_prefixes"
    rm -rf "$tmp"
}

test_managed_block

echo
echo "== replace_file_contents: mode, symlinks, truncation safety =="

# Portable octal mode, GNU stat (Linux) first, then BSD stat (macOS).
#
# The two calls are separate statements for the same reason
# replace_file_contents' copy of this idiom is: GNU `stat -f` means
# `--file-system`, so on Linux the BSD-first form printed a filesystem dump
# to stdout before failing, and anything capturing this function got that
# dump concatenated with the real answer.
file_mode() {
    stat -c '%a' "$1" 2>/dev/null && return 0
    stat -f '%Lp' "$1" 2>/dev/null
}

test_mode_preservation() {
    local tmp; tmp="$(mktemp -d)"
    mkdir -p "$tmp/share/nano"

    local saved_rc="$NANORC" saved_dir="$SYNTAX_DIR" saved_prefixes="${QOL_NANO_PREFIXES:-}"
    NANORC="$tmp/nanorc"
    SYNTAX_DIR="$tmp/absent"
    QOL_NANO_PREFIXES="$tmp/share/nano"
    # shellcheck disable=SC2034  # read by nano_supports (via write_nanorc -> render_nanorc), not directly in this file
    nano_help_cache="$NANO_HELP_FIXTURE_TINY"

    local mode
    for mode in 640 600; do
        printf 'set nowrap\n' > "$NANORC"
        chmod "$mode" "$NANORC"
        write_nanorc
        assert_eq "$mode" "$(file_mode "$NANORC")" "mode $mode survives one write_nanorc"
        write_nanorc
        assert_eq "$mode" "$(file_mode "$NANORC")" "mode $mode survives a rerun too"
        rm -f "$NANORC"
    done

    NANORC="$saved_rc"
    SYNTAX_DIR="$saved_dir"
    QOL_NANO_PREFIXES="$saved_prefixes"
    rm -rf "$tmp"
}

test_symlink_survival() {
    local tmp; tmp="$(mktemp -d)"
    mkdir -p "$tmp/share/nano"

    local saved_rc="$NANORC" saved_dir="$SYNTAX_DIR" saved_prefixes="${QOL_NANO_PREFIXES:-}"
    local real="$tmp/real-nanorc"
    NANORC="$tmp/nanorc"
    SYNTAX_DIR="$tmp/absent"
    QOL_NANO_PREFIXES="$tmp/share/nano"
    # shellcheck disable=SC2034  # read by nano_supports (via write_nanorc -> render_nanorc), not directly in this file
    nano_help_cache="$NANO_HELP_FIXTURE_TINY"

    printf 'set nowrap\n' > "$real"
    ln -s "$real" "$NANORC"

    write_nanorc
    assert_ok "[ -L \"$NANORC\" ]" "NANORC path is still a symlink after one write"
    assert_contains "$(cat "$real")" "set linenumbers" "block landed in the symlink TARGET, not a copy replacing the link"

    local first; first="$(cat "$NANORC")"
    write_nanorc
    assert_ok "[ -L \"$NANORC\" ]" "NANORC path is still a symlink after a rerun"
    local second; second="$(cat "$NANORC")"
    assert_eq "$first" "$second" "rerun through a symlink is byte-identical"

    NANORC="$saved_rc"
    SYNTAX_DIR="$saved_dir"
    QOL_NANO_PREFIXES="$saved_prefixes"
    rm -rf "$tmp"
}

test_truncation_safety() {
    local tmp; tmp="$(mktemp -d)"
    local dst="$tmp/dst"
    printf 'ORIGINAL CONTENT THAT MUST SURVIVE\n' > "$dst"

    # Detect whether this sandbox actually enforces ulimit -f before relying
    # on it for the test — some containers silently ignore the limit, in
    # which case a "filesize-limited" write would just succeed in full and
    # the test would prove nothing.
    local ulimit_enforced=""
    if ( ulimit -f 1 2>/dev/null && dd if=/dev/zero of="$tmp/probe" bs=1024 count=10 \
        ) >/dev/null 2>&1; then
        ulimit_enforced=""
    else
        ulimit_enforced=1
    fi
    rm -f "$tmp/probe"

    if [[ -n "$ulimit_enforced" ]]; then
        # Reproduce the reviewer's actual failure mode: a source bigger than
        # the limit, so cat is killed mid-write rather than never starting.
        local src="$tmp/src"
        for _ in $(seq 1 200); do
            printf '%s\n' \
                "0123456789012345678901234567890123456789012345678901234567890123456789" \
                >> "$src"
        done
        ( ulimit -f 1 2>/dev/null; replace_file_contents "$src" "$dst" ) 2>/dev/null || true
        assert_eq "ORIGINAL CONTENT THAT MUST SURVIVE" "$(cat "$dst")" \
            "a filesize-limited write leaves the original file intact (ulimit -f enforced)"
    else
        # Fall back to a source that does not exist — cat fails immediately,
        # exercising the same "write fails, dst must be untouched" path.
        replace_file_contents "$tmp/does-not-exist" "$dst" 2>/dev/null || true
        assert_eq "ORIGINAL CONTENT THAT MUST SURVIVE" "$(cat "$dst")" \
            "a failed write leaves the original file intact (ulimit -f not enforced here)"
    fi

    rm -rf "$tmp"
}

# Both awks that feed replace_file_contents used to run unchecked. `set -e`
# cannot catch them — every caller sits in a `||` context, which disarms it
# for the whole call tree — so a failing awk handed a truncated temp file
# straight to an atomic rename over the user's real config, while the script
# printed "nano is ready" and exited 0.
#
# The failure is injected with an awk on PATH that emits partial output and
# then exits 1, which is what a broken awk, a full disk, and a killed process
# all look like from inside these functions.
test_awk_failure_never_truncates() {
    local tmp; tmp="$(mktemp -d)"
    mkdir -p "$tmp/badbin" "$tmp/share/nano"

    # Absolute shebang, same reasoning as make_stub_mgr: nothing here should
    # depend on what else is reachable when PATH is being manipulated.
    cat > "$tmp/badbin/awk" <<'STUB'
#!/bin/bash
printf 'PARTIAL OUTPUT\n'
exit 1
STUB
    chmod +x "$tmp/badbin/awk"

    local saved_rc="$NANORC" saved_dir="$SYNTAX_DIR" saved_prefixes="${QOL_NANO_PREFIXES:-}"
    local saved_path="$PATH"
    NANORC="$tmp/nanorc"
    SYNTAX_DIR="$tmp/absent"
    QOL_NANO_PREFIXES="$tmp/share/nano"
    # shellcheck disable=SC2034  # read by nano_supports (via write_nanorc -> render_nanorc)
    nano_help_cache="$NANO_HELP_FIXTURE_TINY"

    # --- the trailing-blank trim awk ------------------------------------
    # No managed block in the file yet, so remove_managed_block's own grep
    # short-circuits and the trim is the first awk reached.
    printf 'set nowrap\nset tabsize 2\n' > "$NANORC"
    PATH="$tmp/badbin:$saved_path"
    local rc=0
    write_nanorc >/dev/null 2>&1 || rc=$?
    PATH="$saved_path"

    assert_eq "1" "$rc" "a failing trim awk makes write_nanorc fail"
    assert_eq "set nowrap
set tabsize 2" "$(cat "$NANORC")" \
        "a failing trim awk leaves the user's config byte-for-byte intact"
    assert_eq "0" "$(find "$tmp" -name 'nanorc.pre-nano.*.bak' | wc -l | tr -d ' ')" \
        "a failing trim awk cleans up the backup it took for a write that never landed"

    # --- remove_managed_block's excision awk ------------------------------
    # Plant a real block first, with a working awk, so the grep no longer
    # short-circuits and the excision awk runs before the trim.
    write_nanorc >/dev/null 2>&1
    local planted; planted="$(cat "$NANORC")"
    assert_contains "$planted" "$BLOCK_START" "sanity: a block was planted with a working awk"

    PATH="$tmp/badbin:$saved_path"
    rc=0
    write_nanorc >/dev/null 2>&1 || rc=$?
    PATH="$saved_path"

    assert_eq "1" "$rc" "a failing block-removal awk makes write_nanorc fail"
    assert_eq "$planted" "$(cat "$NANORC")" \
        "a failing block-removal awk leaves the previous config byte-for-byte intact"

    NANORC="$saved_rc"
    SYNTAX_DIR="$saved_dir"
    QOL_NANO_PREFIXES="$saved_prefixes"
    rm -rf "$tmp"
}

# backup_file's contract is that the backup is a usable copy, not just a
# plausible filename. Every existing assertion only counted `.bak` files, so
# replacing the `cp` with a `touch` would have gone unnoticed.
test_backup_file_copies_content() {
    local tmp; tmp="$(mktemp -d)"
    local f="$tmp/original"
    printf 'line one\nline two\n' > "$f"

    assert_ok "backup_file '$f' >/dev/null" "backup_file succeeds on a real file"
    assert_ok "[ -n \"\$LAST_BACKUP_PATH\" ]" "backup_file reports the path it wrote"
    assert_eq "line one
line two" "$(cat "$LAST_BACKUP_PATH")" \
        "the backup holds the original's actual content, not an empty placeholder"

    # A missing file is a no-op, not a failure, and must report no path.
    assert_ok "backup_file '$tmp/absent' >/dev/null" "backup_file is a no-op on a missing file"
    assert_eq "" "$LAST_BACKUP_PATH" "no backup path is reported when there was nothing to copy"

    rm -rf "$tmp"
}

test_mode_preservation
test_symlink_survival
test_truncation_safety
test_awk_failure_never_truncates
test_backup_file_copies_content

echo
echo "== package manager detection =="

# Build a stub package-manager executable that records whether it was ever
# actually run, so tests can prove install_nano_package's dry-run path never
# invokes it.
make_stub_mgr() {
    local dir="$1" name="$2" marker="$3"
    mkdir -p "$dir"
    # Absolute shebang, not #!/usr/bin/env bash: several tests using this
    # stub replace PATH wholesale (no fallback to the real PATH) so that a
    # bug can't fall through to a real package manager. `env` would then be
    # unable to find `bash` at all.
    cat > "$dir/$name" <<STUB
#!/bin/bash
printf 'ran\n' >> "$marker"
exit 0
STUB
    chmod +x "$dir/$name"
}

test_detect_pkg_manager() {
    local tmp; tmp="$(mktemp -d)"
    local saved_path="$PATH"

    # Build every fixture directory up front, while PATH still has mkdir/chmod
    # on it — narrowing PATH must happen only around the assertions below.
    mkdir -p "$tmp/empty"
    make_stub_mgr "$tmp/apt_only" "apt-get" "$tmp/apt.marker"
    make_stub_mgr "$tmp/both" "brew" "$tmp/both.marker"
    make_stub_mgr "$tmp/both" "apt-get" "$tmp/both.marker"

    # Nothing on PATH at all: detection must fail, not silently pick something.
    # Deliberately a full replacement, not "$tmp/empty:$saved_path" — this
    # dev machine has real brew/apt on PATH, and a fallback would defeat the
    # "no manager found" case entirely.
    # shellcheck disable=SC2123
    PATH="$tmp/empty"
    assert_fail 'detect_pkg_manager >/dev/null 2>&1' \
        "no package manager on PATH fails detection"

    # apt-get is reported as "apt" — the -get suffix is stripped. Full
    # replacement again, so only the stub is visible.
    # shellcheck disable=SC2123
    PATH="$tmp/apt_only"
    assert_eq "apt" "$(detect_pkg_manager)" "apt-get normalizes to apt"

    # brew is checked first, so it wins when several managers are present —
    # this matters on a Linuxbrew box that also has apt-get.
    # shellcheck disable=SC2123
    PATH="$tmp/both"
    assert_eq "brew" "$(detect_pkg_manager)" "brew takes priority over apt-get"

    PATH="$saved_path"
    rm -rf "$tmp"
}

test_detect_pkg_manager

echo
echo "== install_nano_package dry-run =="

test_install_nano_package_dry_run() {
    local tmp; tmp="$(mktemp -d)"
    local saved_path="$PATH" saved_dry_run="$DRY_RUN"
    local marker="$tmp/brew.ran"

    make_stub_mgr "$tmp/brew" "brew" "$marker"

    # Full replacement, not a prepend: only the stub brew must be reachable,
    # so a bug that skips the dry-run guard can never fall through to a real
    # package manager on this machine's PATH.
    # shellcheck disable=SC2123
    PATH="$tmp/brew"
    DRY_RUN=1
    local out status
    out="$(install_nano_package 2>&1)"
    status=$?

    assert_eq "0" "$status" "dry-run install_nano_package exits 0"
    assert_contains "$out" "[dry-run]" "dry-run output announces itself"
    assert_contains "$out" "brew" "dry-run output names the detected manager"
    assert_eq "absent" "$([[ -f "$marker" ]] && echo present || echo absent)" \
        "dry-run never actually executes the package manager"

    DRY_RUN="$saved_dry_run"
    PATH="$saved_path"
    rm -rf "$tmp"
}

test_install_nano_package_dry_run

echo
echo "== install_nano_package sudo decision =="

# Fake `id -u`, reporting a fixed uid regardless of who actually runs the
# suite.
make_stub_id() {
    local dir="$1" uid="$2"
    mkdir -p "$dir"
    # Absolute shebang — see make_stub_mgr's comment: these tests replace
    # PATH wholesale, so `env` has no PATH left to find `bash` on.
    cat > "$dir/id" <<STUB
#!/bin/bash
if [[ "\$1" == "-u" ]]; then
    printf '%s\n' "$uid"
    exit 0
fi
exit 1
STUB
    chmod +x "$dir/id"
}

# Fake sudo: records that it ran, then actually execs its arguments (which
# resolve to the stub package manager also on PATH), so the sudo-prefixed
# case in install_nano_package still "installs" via the harmless stub.
make_stub_sudo() {
    local dir="$1" marker="$2"
    mkdir -p "$dir"
    cat > "$dir/sudo" <<STUB
#!/bin/bash
printf 'ran\n' >> "$marker"
exec "\$@"
STUB
    chmod +x "$dir/sudo"
}

test_install_nano_package_sudo_decision() {
    local tmp; tmp="$(mktemp -d)"
    local saved_path="$PATH" saved_dry_run="$DRY_RUN"
    DRY_RUN=""   # the sudo decision is only reached past the dry-run guard

    # Build every fixture directory up front, while PATH still has
    # mkdir/chmod on it — narrowing PATH must happen only around the
    # assertions below, one scenario at a time.
    local root_dir="$tmp/root"
    local dnf_marker="$tmp/root-dnf.ran" sudo_marker="$tmp/root-sudo.ran"
    make_stub_id "$root_dir" 0
    make_stub_mgr "$root_dir" "dnf" "$dnf_marker"
    make_stub_sudo "$root_dir" "$sudo_marker"

    local sudo_dir="$tmp/sudo"
    local dnf_marker2="$tmp/sudo-dnf.ran" sudo_marker2="$tmp/sudo-sudo.ran"
    make_stub_id "$sudo_dir" 501
    make_stub_mgr "$sudo_dir" "dnf" "$dnf_marker2"
    make_stub_sudo "$sudo_dir" "$sudo_marker2"

    local nosudo_dir="$tmp/nosudo"
    local dnf_marker3="$tmp/nosudo-dnf.ran"
    make_stub_id "$nosudo_dir" 501
    make_stub_mgr "$nosudo_dir" "dnf" "$dnf_marker3"

    local brew_dir="$tmp/brewnosudo"
    local brew_marker="$tmp/brewnosudo-brew.ran"
    make_stub_id "$brew_dir" 501
    make_stub_mgr "$brew_dir" "brew" "$brew_marker"

    # --- root: never prefixed, sudo not even consulted -------------------
    # shellcheck disable=SC2123
    PATH="$root_dir"
    assert_ok 'install_nano_package >/dev/null 2>&1' "root install succeeds"
    assert_eq "present" "$([[ -f "$dnf_marker" ]] && echo present || echo absent)" \
        "root install actually runs dnf"
    assert_eq "absent" "$([[ -f "$sudo_marker" ]] && echo present || echo absent)" \
        "root install never touches sudo, even though it's on PATH"

    # --- non-root, sudo available: prefixed and it runs ------------------
    # shellcheck disable=SC2123
    PATH="$sudo_dir"
    assert_ok 'install_nano_package >/dev/null 2>&1' \
        "non-root install with sudo available succeeds"
    assert_eq "present" "$([[ -f "$sudo_marker2" ]] && echo present || echo absent)" \
        "non-root install runs through sudo"
    assert_eq "present" "$([[ -f "$dnf_marker2" ]] && echo present || echo absent)" \
        "sudo actually forwards to dnf"

    # --- non-root, no sudo binary: clear failure, nothing attempted ------
    # shellcheck disable=SC2123
    PATH="$nosudo_dir"
    local out3
    out3="$(install_nano_package 2>&1)"
    local status3=$?
    assert_eq "1" "$status3" "non-root install with no sudo fails cleanly"
    assert_contains "$out3" "dnf" "no-sudo failure names the package manager"
    assert_contains "$out3" "dnf install -y nano" \
        "no-sudo failure gives the literal command to run as root"
    assert_eq "absent" "$([[ -f "$dnf_marker3" ]] && echo present || echo absent)" \
        "no-sudo failure never attempts the install"

    # --- brew: never prefixed regardless of root/sudo status -------------
    # shellcheck disable=SC2123
    PATH="$brew_dir"
    assert_ok 'install_nano_package >/dev/null 2>&1' \
        "brew install succeeds with no sudo and no root, since brew needs neither"
    assert_eq "present" "$([[ -f "$brew_marker" ]] && echo present || echo absent)" \
        "brew install actually runs brew"

    DRY_RUN="$saved_dry_run"
    PATH="$saved_path"
    rm -rf "$tmp"
}

test_install_nano_package_sudo_decision

echo
echo "== nano resolution =="

test_resolve_nano() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/good" "9.1"
    make_stub_nano "$tmp/ancient" "2.9.7"
    # Named "legacy", not "pico": a directory literally named "pico" leaks
    # that word into any 2>&1-captured message regardless of what
    # resolve_nano actually printed, which is exactly how an earlier version
    # of this suite hid a false positive (see the seam-driven Darwin tests
    # below, where the branded message is proven for real).
    make_stub_pico "$tmp/legacy"

    local saved_path="$PATH"

    PATH="$tmp/good:$saved_path"
    assert_eq "$tmp/good/nano" "$(resolve_nano 2>/dev/null)" "modern nano is accepted"

    PATH="$tmp/ancient:$saved_path"
    assert_fail 'resolve_nano >/dev/null 2>&1' "nano 2.9.7 is rejected (below 4.0)"

    PATH="$tmp/legacy:$saved_path"
    assert_fail 'resolve_nano >/dev/null 2>&1' "a non-GNU nano binary is rejected"

    # With no Darwin seam active, a non-GNU binary gets only the generic
    # rejection. This is the control case for the seam-driven tests below:
    # it proves "pico" cannot leak into the message from the fixture path.
    local generic_msg
    generic_msg="$(PATH="$tmp/legacy:$saved_path" resolve_nano 2>&1 || true)"
    assert_not_contains "$generic_msg" "pico" \
        "generic rejection (no Darwin seam) does not mention pico"

    PATH="$saved_path"
    rm -rf "$tmp"
}

test_resolve_nano

# resolve_nano's callers use its stdout as its actual return value
# (`bin="$(resolve_nano)"`), so any diagnostic it prints on the "not found"
# branch MUST go to stderr, not stdout — a log_info call there without an
# explicit >&2 would silently vanish into that captured value instead of
# ever reaching the terminal, since log_info (unlike log_err) does not
# redirect itself. This is exactly the shape of bug the unit tests above
# cannot catch, since assert_eq/assert_fail only look at exit status or an
# already-merged 2>&1 stream — it only showed up running the real script
# end to end with a PATH that has genuinely no nano at all.
test_resolve_nano_not_found_goes_to_stderr() {
    local tmp; tmp="$(mktemp -d)"
    mkdir -p "$tmp/empty"
    local saved_path="$PATH"
    # Full replacement, not a prepend: this dev machine has a real nano on
    # it, and a prepend would defeat the entire point of "genuinely absent."
    # shellcheck disable=SC2123
    PATH="$tmp/empty"

    local stdout_only stderr_only rc
    stdout_only="$(resolve_nano 2>/dev/null)"; rc=$?
    stderr_only="$(resolve_nano 2>&1 >/dev/null)"

    assert_eq "1" "$rc" "not-found: resolve_nano returns 1, not 2"
    assert_eq "" "$stdout_only" "not-found: stdout (the return-value channel) is empty"
    assert_contains "$stderr_only" "No GNU nano found on PATH." \
        "not-found: the message actually lands on stderr"

    PATH="$saved_path"
    rm -rf "$tmp"
}

test_resolve_nano_not_found_goes_to_stderr

echo
echo "== macOS pico diagnostic (seam-driven) =="

# resolve_nano's Darwin branch only fires when the offending binary's path
# equals exactly /usr/bin/nano on a real Darwin host. QOL_NANO_PICO_PATH and
# QOL_NANO_UNAME (read by resolve_nano) and QOL_NANO_BREW_PREFIXES (read by
# find_homebrew_nano) let these tests force that branch, and choose whether a
# real GNU nano is "found", without touching /usr/bin/nano or pretending the
# test host is Darwin.
test_pico_diagnostic() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_pico "$tmp/legacy"
    make_stub_nano "$tmp/brewbin" "9.1"
    mkdir -p "$tmp/nobrewbin"

    local saved_path="$PATH"
    local pico_bin="$tmp/legacy/nano"

    PATH="$tmp/legacy:$saved_path"

    # --- brew nano present: branded message, concrete fix ---------------
    local msg
    msg="$(QOL_NANO_PICO_PATH="$pico_bin" QOL_NANO_UNAME="Darwin" \
           QOL_NANO_BREW_PREFIXES="$tmp/brewbin" resolve_nano 2>&1 || true)"

    assert_contains "$msg" "UW pico" \
        "Darwin + pico-path seam produces the branded diagnostic"
    assert_contains "$msg" "$tmp/brewbin/nano" \
        "diagnostic names the actual Homebrew nano path found"
    assert_contains "$msg" "export PATH=" \
        "diagnostic gives a literal PATH fix"
    assert_contains "$msg" "new terminal" \
        "diagnostic tells the student to open a new terminal"
    assert_not_contains "$msg" "not installed yet" \
        "diagnostic does not claim nano is missing when it was found"

    # --- no brew nano anywhere: honest "not installed" message ----------
    local msg_missing
    msg_missing="$(QOL_NANO_PICO_PATH="$pico_bin" QOL_NANO_UNAME="Darwin" \
           QOL_NANO_BREW_PREFIXES="$tmp/nobrewbin" resolve_nano 2>&1 || true)"

    assert_contains "$msg_missing" "UW pico" \
        "diagnostic still names pico when nano is not installed"
    assert_contains "$msg_missing" "not installed yet" \
        "diagnostic says plainly that GNU nano isn't installed"
    assert_not_contains "$msg_missing" "export PATH=" \
        "diagnostic does not suggest a PATH fix with nothing to point PATH at"

    # --- rc file selection follows $SHELL --------------------------------
    local msg_zsh msg_bash msg_other
    msg_zsh="$(SHELL=/bin/zsh QOL_NANO_PICO_PATH="$pico_bin" QOL_NANO_UNAME="Darwin" \
           QOL_NANO_BREW_PREFIXES="$tmp/brewbin" resolve_nano 2>&1 || true)"
    assert_contains "$msg_zsh" ".zshrc" "zsh users are told to edit .zshrc"

    msg_bash="$(SHELL=/bin/bash QOL_NANO_PICO_PATH="$pico_bin" QOL_NANO_UNAME="Darwin" \
           QOL_NANO_BREW_PREFIXES="$tmp/brewbin" resolve_nano 2>&1 || true)"
    assert_contains "$msg_bash" ".bashrc" "bash users are told to edit .bashrc"

    msg_other="$(SHELL=/bin/fish QOL_NANO_PICO_PATH="$pico_bin" QOL_NANO_UNAME="Darwin" \
           QOL_NANO_BREW_PREFIXES="$tmp/brewbin" resolve_nano 2>&1 || true)"
    assert_contains "$msg_other" "your shell's rc file" \
        "unrecognised shells get a generic rc pointer instead of a wrong filename"

    # --- off Darwin: the pico path alone is not enough to fire it -------
    local msg_linux
    msg_linux="$(QOL_NANO_PICO_PATH="$pico_bin" QOL_NANO_UNAME="Linux" \
           QOL_NANO_BREW_PREFIXES="$tmp/brewbin" resolve_nano 2>&1 || true)"
    assert_not_contains "$msg_linux" "UW pico" \
        "the pico branch never fires off Darwin, even at the same path"

    PATH="$saved_path"
    rm -rf "$tmp"
}

test_pico_diagnostic

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

    local rc
    sync_syntax_pack >/dev/null 2>&1; rc=$?
    assert_ok "[ -f '$tmp/clone/fake.nanorc' ]" "first run clones the pack"
    assert_eq "0" "$rc" "first-run clone returns success"

    # Rerun on a clean clone must succeed and leave the file in place.
    sync_syntax_pack >/dev/null 2>&1; rc=$?
    assert_ok "[ -f '$tmp/clone/fake.nanorc' ]" "rerun on clean clone succeeds"
    assert_eq "0" "$rc" "clean-clone rerun returns success"

    # Give origin a new commit so a real pull would actually change something.
    # Without this, "would a pull have happened" is untestable: an unmodified
    # origin makes `git pull --ff-only` a no-op whether or not the dirty guard
    # exists, so the assertion below would pass even with the guard deleted.
    printf 'syntax "fake" "\\.fake$"\nupstream update\n' > "$tmp/origin/fake.nanorc"
    git -C "$tmp/origin" add -A
    git -C "$tmp/origin" -c user.email=t@t -c user.name=t commit -qm upstream

    # A dirty clone must be left alone, not clobbered — and must not silently
    # fetch the upstream change either.
    printf 'local edit\n' >> "$tmp/clone/fake.nanorc"
    sync_syntax_pack >/dev/null 2>&1; rc=$?
    assert_contains "$(cat "$tmp/clone/fake.nanorc")" "local edit" \
        "dirty clone is not overwritten"
    assert_not_contains "$(cat "$tmp/clone/fake.nanorc")" "upstream update" \
        "dirty clone does not silently pull upstream changes"
    assert_eq "0" "$rc" "dirty-clone refusal returns success"

    # The two assertions above would also pass with our dirty-check deleted
    # entirely, because `git pull --ff-only` refuses on its own to check out a
    # fast-forward that would clobber a locally modified tracked file — that
    # was verified by hand before trusting this test. To prove our own check
    # (git status --porcelain, read before git is ever invoked to pull) is
    # what is actually firing, repeat with a kind of dirt git itself does NOT
    # object to: an untracked file that doesn't collide with anything the
    # upstream commit touches. Start from a clean clone caught up to origin.
    git -C "$tmp/clone" reset -q --hard
    git -C "$tmp/clone" pull --ff-only --quiet
    printf 'scratch\n' > "$tmp/clone/scratch.txt"
    local head_before; head_before="$(git -C "$tmp/clone" rev-parse HEAD)"

    printf 'syntax "fake" "\\.fake$"\nupstream update\nsecond update\n' \
        > "$tmp/origin/fake.nanorc"
    git -C "$tmp/origin" add -A
    git -C "$tmp/origin" -c user.email=t@t -c user.name=t commit -qm upstream2

    sync_syntax_pack >/dev/null 2>&1; rc=$?
    local head_after; head_after="$(git -C "$tmp/clone" rev-parse HEAD)"
    assert_eq "$head_before" "$head_after" \
        "an untracked scratch file blocks the pull too, though bare git would allow it"
    assert_not_contains "$(cat "$tmp/clone/fake.nanorc")" "second update" \
        "untracked-dirty clone does not silently pull upstream changes"
    assert_eq "0" "$rc" "untracked-dirty-clone refusal returns success"

    # A SYNTAX_DIR that exists but was never a git clone (e.g. hand-created,
    # or left over from before this script existed) must be left completely
    # alone rather than folded into a clone. Content-bearing case first: this
    # documents that existing files survive, though it does not by itself
    # prove our own check fired — `git clone` already refuses on its own to
    # clone into a non-empty directory, so this assertion would still pass
    # with our check deleted.
    NO_SYNTAX=""; DRY_RUN=""
    mkdir -p "$tmp/notgit"
    printf 'do not touch\n' > "$tmp/notgit/keep.txt"
    SYNTAX_DIR="$tmp/notgit"
    sync_syntax_pack >/dev/null 2>&1; rc=$?
    assert_ok "[ -f '$tmp/notgit/keep.txt' ]" \
        "existing non-git SYNTAX_DIR is left untouched"
    assert_eq "0" "$rc" "non-git SYNTAX_DIR refusal returns success"

    # The actual proof: an *empty* pre-existing directory. `git clone` has no
    # objection to cloning into an empty directory, so only our own
    # not-a-.git-dir check stands between this and silently becoming a clone.
    mkdir -p "$tmp/notgit-empty"
    SYNTAX_DIR="$tmp/notgit-empty"
    sync_syntax_pack >/dev/null 2>&1; rc=$?
    assert_fail "[ -d '$tmp/notgit-empty/.git' ]" \
        "an empty pre-existing SYNTAX_DIR is not turned into a clone either"
    assert_eq "0" "$rc" "empty non-git SYNTAX_DIR refusal returns success"

    # A missing git binary must degrade gracefully — not error out, not fall
    # through to try running git anyway. PATH is narrowed to a directory that
    # has every tool sync_syntax_pack's own logging needs (tput, for the
    # separator rule) but no git, so `command -v git` genuinely fails rather
    # than the test accidentally proving nothing because git was still found
    # elsewhere on PATH.
    local nogit_bin="$tmp/nogit-bin" saved_path="$PATH"
    mkdir -p "$nogit_bin"
    ln -s "$(command -v tput)" "$nogit_bin/tput"
    SYNTAX_DIR="$tmp/nogit"
    PATH="$nogit_bin"
    sync_syntax_pack >/dev/null 2>&1; rc=$?
    PATH="$saved_path"
    assert_fail "[ -e '$tmp/nogit' ]" "no git on PATH creates nothing"
    assert_eq "0" "$rc" "missing-git refusal returns success"

    # A clone that fails outright (bad remote) must warn and move on rather
    # than aborting the whole install.
    SYNTAX_DIR="$tmp/failedclone"
    SYNTAX_REPO="$tmp/does-not-exist"
    sync_syntax_pack >/dev/null 2>&1; rc=$?
    assert_eq "0" "$rc" "failed clone returns success"

    # --no-syntax must not create anything.
    SYNTAX_DIR="$tmp/skipped"; SYNTAX_REPO="$tmp/origin"; NO_SYNTAX=1
    sync_syntax_pack >/dev/null 2>&1; rc=$?
    assert_fail "[ -d '$tmp/skipped' ]" "--no-syntax creates nothing"
    assert_eq "0" "$rc" "--no-syntax returns success"

    # --dry-run must not create anything either.
    SYNTAX_DIR="$tmp/dry"; NO_SYNTAX=""; DRY_RUN=1
    sync_syntax_pack >/dev/null 2>&1; rc=$?
    assert_fail "[ -d '$tmp/dry' ]" "--dry-run creates nothing"
    assert_eq "0" "$rc" "--dry-run returns success"

    SYNTAX_DIR="$saved_dir"; SYNTAX_REPO="$saved_repo"
    NO_SYNTAX="$saved_nosyn"; DRY_RUN="$saved_dry"
    rm -rf "$tmp"
}

test_sync_syntax_pack

echo
echo "== end to end =="

# QOL_NANO_NO_INSTALL is set in every end-to-end invocation below, even the
# ones that expect nano to already be on PATH via make_stub_nano and so
# should never reach install_nano_package at all. Belt and suspenders: if a
# bug ever did let one of these fall through, this seam is what stops it
# from running a real package manager against this machine instead of just
# quietly (and wrongly) passing.

test_dry_run_writes_nothing() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/bin" "9.1"
    mkdir -p "$tmp/home"

    local saved_path="$PATH"
    PATH="$tmp/bin:$saved_path"

    local rc
    QOL_NANO_NO_INSTALL=1 HOME="$tmp/home" \
        ./install_nano.sh --dry-run --yes >/dev/null 2>&1
    rc=$?

    assert_eq "0" "$rc" "--dry-run exits 0"
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

    local rc
    QOL_NANO_NO_INSTALL=1 HOME="$tmp/home" \
        ./install_nano.sh --yes --no-syntax >/dev/null 2>&1
    rc=$?

    assert_eq "0" "$rc" "real run exits 0"
    assert_ok "[ -f '$tmp/home/.nanorc' ]" "real run writes .nanorc"
    assert_contains "$(cat "$tmp/home/.nanorc")" "set linenumbers" \
        "written .nanorc carries the core settings"
    assert_contains "$(cat "$tmp/home/.nanorc")" "bind ^S savefile main" \
        "written .nanorc carries the ^S binding"
    assert_contains "$(cat "$tmp/home/.nanorc")" "bind ^Z suspend main" \
        "written .nanorc carries the ^Z suspend binding"

    PATH="$saved_path"
    rm -rf "$tmp"
}

# $SHELL is pinned explicitly on every invocation here rather than left to
# whatever shell happens to be running the test suite. This test previously
# passed only because this development machine's own $SHELL is zsh — on a
# bash-login host every assertion below would have failed silently, since
# set_default_editor would have written to a completely different file.
test_set_editor_is_opt_in() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/bin" "9.1"
    mkdir -p "$tmp/home"
    touch "$tmp/home/.zshrc"

    local saved_path="$PATH"
    PATH="$tmp/bin:$saved_path"

    local rc
    SHELL=/bin/zsh QOL_NANO_NO_INSTALL=1 HOME="$tmp/home" \
        ./install_nano.sh --yes --no-syntax >/dev/null 2>&1
    rc=$?
    assert_eq "0" "$rc" "run without --set-editor exits 0"
    assert_not_contains "$(cat "$tmp/home/.zshrc")" "EDITOR" \
        "EDITOR is not exported by default"

    SHELL=/bin/zsh QOL_NANO_NO_INSTALL=1 HOME="$tmp/home" \
        ./install_nano.sh --yes --no-syntax --set-editor >/dev/null 2>&1
    rc=$?
    assert_eq "0" "$rc" "--set-editor exits 0"
    assert_contains "$(cat "$tmp/home/.zshrc")" "export EDITOR=nano" \
        "--set-editor exports EDITOR"
    assert_contains "$(cat "$tmp/home/.zshrc")" "export VISUAL=nano" \
        "--set-editor exports VISUAL"

    # Idempotent: a second --set-editor run must not duplicate.
    SHELL=/bin/zsh QOL_NANO_NO_INSTALL=1 HOME="$tmp/home" \
        ./install_nano.sh --yes --no-syntax --set-editor >/dev/null 2>&1
    rc=$?
    assert_eq "0" "$rc" "rerun of --set-editor exits 0"
    assert_eq "1" "$(grep -c 'export EDITOR=nano' "$tmp/home/.zshrc")" \
        "--set-editor does not duplicate on rerun"

    PATH="$saved_path"
    rm -rf "$tmp"
}

# On macOS, Terminal.app starts a login shell, which reads .bash_profile,
# not .bashrc — a .bashrc-only write left --set-editor with no visible
# effect there. set_default_editor now writes the same idempotent block to
# both files for bash. Both start pre-existing here (a fresh install with
# neither present is covered implicitly: touch creates them).
test_set_editor_bash_login() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/bin" "9.1"
    mkdir -p "$tmp/home"
    touch "$tmp/home/.bash_profile" "$tmp/home/.bashrc"

    local saved_path="$PATH"
    PATH="$tmp/bin:$saved_path"

    local rc
    SHELL=/bin/bash QOL_NANO_NO_INSTALL=1 HOME="$tmp/home" \
        ./install_nano.sh --yes --no-syntax --set-editor >/dev/null 2>&1
    rc=$?

    assert_eq "0" "$rc" "bash --set-editor exits 0"
    assert_contains "$(cat "$tmp/home/.bash_profile")" "export EDITOR=nano" \
        "bash: .bash_profile (the login-shell file Terminal.app reads) gets EDITOR"
    assert_contains "$(cat "$tmp/home/.bash_profile")" "export VISUAL=nano" \
        "bash: .bash_profile gets VISUAL"
    assert_contains "$(cat "$tmp/home/.bashrc")" "export EDITOR=nano" \
        "bash: .bashrc (the non-login interactive file) also gets EDITOR"

    # Idempotent per file too.
    SHELL=/bin/bash QOL_NANO_NO_INSTALL=1 HOME="$tmp/home" \
        ./install_nano.sh --yes --no-syntax --set-editor >/dev/null 2>&1
    assert_eq "1" "$(grep -c 'export EDITOR=nano' "$tmp/home/.bash_profile")" \
        "bash: .bash_profile does not duplicate on rerun"
    assert_eq "1" "$(grep -c 'export EDITOR=nano' "$tmp/home/.bashrc")" \
        "bash: .bashrc does not duplicate on rerun"

    PATH="$saved_path"
    rm -rf "$tmp"
}

# The rc file most likely to be hand-edited is the one most likely to have
# no trailing newline on its last line — `printf 'export X=1' >> ~/.zshrc`,
# a text editor configured not to add one, a heredoc without a final blank.
#
# set_default_editor used to append with a bare `cat >> "$rc"` starting
# directly at its start marker, so on such a file run 1 produced
#
#     export IMPORTANT_SETTING=1# >>> qol nano editor >>>
#
# which bash refuses to parse, so every new terminal errored and stopped
# sourcing the file — and run 2 then matched that combined line as the block
# start and DELETED the user's setting along with the block, taking no backup
# because the file already contained the marker. Three runs, because the
# corruption and the deletion are two different runs.
test_set_editor_rc_without_trailing_newline() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/bin" "9.1"
    mkdir -p "$tmp/home"

    local rcfile="$tmp/home/.zshrc"
    printf 'export IMPORTANT_SETTING=1' > "$rcfile"   # deliberately no \n
    assert_eq "0" "$(tail -c1 "$rcfile" | wc -l | tr -d ' ')" \
        "sanity: the fixture rc file really has no trailing newline"

    local saved_path="$PATH"
    PATH="$tmp/bin:$saved_path"

    local run prev=""
    for run in 1 2 3; do
        SHELL=/bin/zsh QOL_NANO_NO_INSTALL=1 HOME="$tmp/home" \
            ./install_nano.sh --yes --no-syntax --set-editor >/dev/null 2>&1

        assert_eq "1" "$(grep -c '^export IMPORTANT_SETTING=1$' "$rcfile")" \
            "run $run: the user's own setting survives, alone on its own line"
        assert_ok "bash -n '$rcfile'" \
            "run $run: the rc file is still valid shell syntax"
        assert_eq "1" "$(grep -cF "$EDITOR_BLOCK_START" "$rcfile")" \
            "run $run: exactly one editor-block start marker"
        assert_eq "1" "$(grep -cF "$EDITOR_BLOCK_END" "$rcfile")" \
            "run $run: exactly one editor-block end marker"
        assert_eq "1" "$(grep -c '^export EDITOR=nano$' "$rcfile")" \
            "run $run: exactly one EDITOR export"

        # Runs 2 and 3 must be byte-identical to the run before them.
        local now; now="$(cat "$rcfile")"
        if [[ "$run" -gt 1 ]]; then
            assert_eq "$prev" "$now" "run $run: byte-identical to the previous run"
        fi
        prev="$now"
    done

    # And the file this run touched must itself end in a newline, so the next
    # tool to append to it does not inherit the same problem.
    assert_eq "1" "$(tail -c1 "$rcfile" | wc -l | tr -d ' ')" \
        "the rewritten rc file ends in a newline"

    PATH="$saved_path"
    rm -rf "$tmp"
}

# The same shape for ~/.nanorc, which the shared helper also owns. A user who
# hand-wrote a .nanorc without a final newline would otherwise get
# `set nowrap# >>> qol nano block >>>` — an rc syntax error nano reports on
# every single launch.
test_write_nanorc_no_trailing_newline() {
    local tmp; tmp="$(mktemp -d)"
    mkdir -p "$tmp/share/nano"

    local saved_rc="$NANORC" saved_dir="$SYNTAX_DIR" saved_prefixes="${QOL_NANO_PREFIXES:-}"
    NANORC="$tmp/nanorc"
    SYNTAX_DIR="$tmp/absent"
    QOL_NANO_PREFIXES="$tmp/share/nano"
    # shellcheck disable=SC2034  # read by nano_supports (via write_nanorc -> render_nanorc)
    nano_help_cache="$NANO_HELP_FIXTURE"

    printf 'set nowrap' > "$NANORC"   # deliberately no \n

    local run prev=""
    for run in 1 2 3; do
        write_nanorc >/dev/null 2>&1
        assert_eq "1" "$(grep -c '^set nowrap$' "$NANORC")" \
            "nanorc run $run: the user's own setting survives, alone on its own line"
        assert_eq "1" "$(grep -cF "$BLOCK_START" "$NANORC")" \
            "nanorc run $run: exactly one start marker"
        local now; now="$(cat "$NANORC")"
        if [[ "$run" -gt 1 ]]; then
            assert_eq "$prev" "$now" "nanorc run $run: byte-identical to the previous run"
        fi
        prev="$now"
    done

    NANORC="$saved_rc"
    SYNTAX_DIR="$saved_dir"
    QOL_NANO_PREFIXES="$saved_prefixes"
    rm -rf "$tmp"
}

test_dry_run_writes_nothing
test_real_run_writes_config
test_set_editor_is_opt_in
test_set_editor_bash_login
test_set_editor_rc_without_trailing_newline
test_write_nanorc_no_trailing_newline

echo
echo "== main: pico vs genuinely-absent nano =="

# The critical bug this section guards against: main() used to run
# `resolve_nano 2>/dev/null` and treat every failure identically, so a
# pico-on-PATH student (the single most common Apple Silicon breakage —
# Homebrew installed, but its shellenv line missing from the rc, so `brew`
# itself isn't even on PATH) fell all the way through to
# install_nano_package and saw "No supported package manager found" instead
# of the specific, branded pico diagnostic that pico_diagnostic exists to
# produce. resolve_nano now returns 2 (not 1) for "found something, but
# it's not usable," and main() must never call install_nano_package for
# that case.
test_main_pico_no_install_attempt() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_pico "$tmp/bin"
    mkdir -p "$tmp/home"

    local saved_path="$PATH"
    PATH="$tmp/bin:$saved_path"

    local out rc
    out="$(QOL_NANO_NO_INSTALL=1 QOL_NANO_PICO_PATH="$tmp/bin/nano" \
           QOL_NANO_UNAME="Darwin" QOL_NANO_BREW_PREFIXES="$tmp/nobrew" \
           HOME="$tmp/home" ./install_nano.sh --yes --no-syntax </dev/null 2>&1)"
    rc=$?

    assert_eq "1" "$rc" "pico on PATH: script exits 1"
    assert_contains "$out" "UW pico" "pico on PATH: prints the branded diagnostic"
    assert_not_contains "$out" "QOL_NANO_NO_INSTALL" \
        "pico on PATH: install_nano_package is never called"
    assert_not_contains "$out" "No supported package manager found" \
        "pico on PATH: never falls through to the generic install-failure message"

    PATH="$saved_path"
    rm -rf "$tmp"
}

# The other half of the same fix: a genuinely absent nano (rc 1, not 2)
# must still reach install_nano_package. PATH is fully replaced, not
# prepended — this dev machine has a real Homebrew nano on it, and a
# prepend would let a regressed "no nano found" detection silently pass by
# falling through to that real binary instead of proving the "absent"
# path was actually exercised.
test_main_absent_nano_reaches_install() {
    local tmp; tmp="$(mktemp -d)"
    mkdir -p "$tmp/home" "$tmp/toolbox"
    # Only what's needed to exec the script's own #!/usr/bin/env bash
    # shebang under a fully replaced PATH; everything else on the path to
    # the QOL_NANO_NO_INSTALL seam firing is bash builtins.
    ln -s "$(command -v env)" "$tmp/toolbox/env"
    ln -s "$(command -v bash)" "$tmp/toolbox/bash"

    local saved_path="$PATH"
    # shellcheck disable=SC2123
    PATH="$tmp/toolbox"

    local out rc
    out="$(QOL_NANO_NO_INSTALL=1 HOME="$tmp/home" \
           ./install_nano.sh --yes --no-syntax </dev/null 2>&1)"
    rc=$?

    assert_eq "1" "$rc" "genuinely-absent nano: exits 1 (blocked by the install seam)"
    assert_contains "$out" "QOL_NANO_NO_INSTALL" \
        "genuinely-absent nano: install_nano_package is actually reached"

    PATH="$saved_path"
    rm -rf "$tmp"
}

test_main_pico_no_install_attempt
test_main_absent_nano_reaches_install

echo
echo "== confirm() =="

test_confirm() {
    local saved_yes="$ASSUME_YES"
    ASSUME_YES=""

    assert_ok "printf 'y\n' | QOL_NANO_FORCE_TTY=1 confirm 'proceed?' 2>/dev/null" \
        "forced-tty prompt: explicit 'y' proceeds"
    assert_ok "printf 'yes\n' | QOL_NANO_FORCE_TTY=1 confirm 'proceed?' 2>/dev/null" \
        "forced-tty prompt: explicit 'yes' proceeds"
    assert_fail "printf 'n\n' | QOL_NANO_FORCE_TTY=1 confirm 'proceed?' 2>/dev/null" \
        "forced-tty prompt: explicit 'n' declines"
    assert_fail "printf '\n' | QOL_NANO_FORCE_TTY=1 confirm 'proceed?' 2>/dev/null" \
        "forced-tty prompt: empty reply defaults to decline"
    assert_fail "printf 'sure\n' | QOL_NANO_FORCE_TTY=1 confirm 'proceed?' 2>/dev/null" \
        "forced-tty prompt: anything but y/yes declines"

    ASSUME_YES=1
    assert_ok "confirm 'proceed?' </dev/null 2>/dev/null" \
        "--yes skips the prompt entirely and proceeds"
    assert_ok "printf 'n\n' | QOL_NANO_FORCE_TTY=1 confirm 'proceed?' 2>/dev/null" \
        "--yes overrides the force-tty seam too"

    ASSUME_YES="$saved_yes"
}

test_confirm

# Function-level coverage above proves confirm()'s own contract. These four
# prove main() actually wires it in: a shown prompt, an accepted prompt, a
# declined prompt, and the plain non-tty default (no seam, no --yes) that
# every other end-to-end test in this suite has been relying on all along
# without ever checking it directly.

test_confirm_shown_and_accepted() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/bin" "9.1"
    mkdir -p "$tmp/home"

    local saved_path="$PATH"
    PATH="$tmp/bin:$saved_path"

    local out rc
    out="$(printf 'y\n' | QOL_NANO_NO_INSTALL=1 QOL_NANO_FORCE_TTY=1 \
           HOME="$tmp/home" ./install_nano.sh --no-syntax 2>&1)"
    rc=$?

    assert_eq "0" "$rc" "accepting the prompt exits 0"
    assert_contains "$out" "[y/N]" "the prompt is actually shown under the force-tty seam"
    assert_ok "[ -f '$tmp/home/.nanorc' ]" "accepting the prompt writes .nanorc"

    PATH="$saved_path"
    rm -rf "$tmp"
}

test_confirm_declined_skips_write() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/bin" "9.1"
    mkdir -p "$tmp/home"

    local saved_path="$PATH"
    PATH="$tmp/bin:$saved_path"

    local rc
    printf 'n\n' | QOL_NANO_NO_INSTALL=1 QOL_NANO_FORCE_TTY=1 \
        HOME="$tmp/home" ./install_nano.sh --no-syntax >/dev/null 2>&1
    rc=$?

    assert_eq "0" "$rc" "declining the prompt is not an error"
    assert_fail "[ -f '$tmp/home/.nanorc' ]" "declining the prompt writes no .nanorc"

    PATH="$saved_path"
    rm -rf "$tmp"
}

test_confirm_non_tty_proceeds_without_yes() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/bin" "9.1"
    mkdir -p "$tmp/home"

    local saved_path="$PATH"
    PATH="$tmp/bin:$saved_path"

    local rc
    QOL_NANO_NO_INSTALL=1 HOME="$tmp/home" \
        ./install_nano.sh --no-syntax </dev/null >/dev/null 2>&1
    rc=$?

    assert_eq "0" "$rc" "no --yes, non-tty stdin: still exits 0"
    assert_ok "[ -f '$tmp/home/.nanorc' ]" \
        "no --yes, non-tty stdin: still writes .nanorc (the automation default)"

    PATH="$saved_path"
    rm -rf "$tmp"
}

test_dry_run_never_prompts() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/bin" "9.1"
    mkdir -p "$tmp/home"

    local saved_path="$PATH"
    PATH="$tmp/bin:$saved_path"

    local out rc
    out="$(QOL_NANO_NO_INSTALL=1 QOL_NANO_FORCE_TTY=1 HOME="$tmp/home" \
           ./install_nano.sh --dry-run --set-editor </dev/null 2>&1)"
    rc=$?

    assert_eq "0" "$rc" "--dry-run with the force-tty seam still exits 0"
    assert_not_contains "$out" "[y/N]" \
        "--dry-run never shows a confirmation prompt, even under the force-tty seam"

    PATH="$saved_path"
    rm -rf "$tmp"
}

test_confirm_shown_and_accepted
test_confirm_declined_skips_write
test_confirm_non_tty_proceeds_without_yes
test_dry_run_never_prompts

echo
echo "== closing summary reflects what was actually written =="

# Declining still returned exit 0 and printed the normal "Config: ...
# nano is ready" summary over an empty home directory — the ⚠️  Skipped
# lines had already scrolled past by then, so a student who hits Enter out
# of habit (the documented empty-reply default) was told the job was done
# when nothing had changed. These three cover the shapes: accepted
# everything, declined everything, and a mixed y/n.

test_summary_accept_everything() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/bin" "9.1"
    mkdir -p "$tmp/home"

    local saved_path="$PATH"
    PATH="$tmp/bin:$saved_path"

    local out rc
    out="$(printf 'y\ny\n' | QOL_NANO_NO_INSTALL=1 QOL_NANO_FORCE_TTY=1 SHELL=/bin/zsh \
           HOME="$tmp/home" ./install_nano.sh --no-syntax --set-editor 2>&1)"
    rc=$?

    assert_eq "0" "$rc" "accept-everything: exits 0"
    assert_ok "[ -f '$tmp/home/.nanorc' ]" "accept-everything: .nanorc written"
    assert_contains "$(cat "$tmp/home/.zshrc")" "export EDITOR=nano" \
        "accept-everything: EDITOR written"
    assert_contains "$out" "nano is ready" \
        "accept-everything: summary shows the normal ready message"
    assert_not_contains "$out" "Nothing was changed" \
        "accept-everything: does not claim nothing changed"

    PATH="$saved_path"
    rm -rf "$tmp"
}

test_summary_decline_everything() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/bin" "9.1"
    mkdir -p "$tmp/home"

    local saved_path="$PATH"
    PATH="$tmp/bin:$saved_path"

    # Empty replies, not explicit 'n' — this is the documented default
    # (bare Enter declines) and the exact case the reviewer's repro used.
    local out rc
    out="$(printf '\n\n' | QOL_NANO_NO_INSTALL=1 QOL_NANO_FORCE_TTY=1 SHELL=/bin/zsh \
           HOME="$tmp/home" ./install_nano.sh --no-syntax --set-editor 2>&1)"
    rc=$?

    assert_eq "0" "$rc" "decline-everything: exits 0 (declining is not an error)"
    assert_fail "[ -f '$tmp/home/.nanorc' ]" "decline-everything: no .nanorc written"
    assert_fail "[ -f '$tmp/home/.zshrc' ] && grep -q EDITOR '$tmp/home/.zshrc'" \
        "decline-everything: EDITOR not written"
    assert_contains "$out" "Nothing was changed" \
        "decline-everything: summary says plainly that nothing changed"
    assert_contains "$out" "pass --yes" \
        "decline-everything: summary explains how to actually do it"
    assert_not_contains "$out" "nano is ready" \
        "decline-everything: does not claim the job is done"

    PATH="$saved_path"
    rm -rf "$tmp"
}

test_summary_mixed() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/bin" "9.1"
    mkdir -p "$tmp/home"

    local saved_path="$PATH"
    PATH="$tmp/bin:$saved_path"

    # Accept the qol block, decline EDITOR.
    local out rc
    out="$(printf 'y\nn\n' | QOL_NANO_NO_INSTALL=1 QOL_NANO_FORCE_TTY=1 SHELL=/bin/zsh \
           HOME="$tmp/home" ./install_nano.sh --no-syntax --set-editor 2>&1)"
    rc=$?

    assert_eq "0" "$rc" "mixed accept/decline: exits 0"
    assert_ok "[ -f '$tmp/home/.nanorc' ]" \
        "mixed accept/decline: .nanorc written (accepted)"
    assert_fail "[ -f '$tmp/home/.zshrc' ] && grep -q EDITOR '$tmp/home/.zshrc'" \
        "mixed accept/decline: EDITOR not written (declined)"
    assert_contains "$out" "nano is ready" \
        "mixed accept/decline: still shows ready, since something was written"
    assert_contains "$out" "EDITOR/VISUAL were not set (declined)" \
        "mixed accept/decline: summary reflects only what exists"
    assert_not_contains "$out" "Nothing was changed" \
        "mixed accept/decline: does not claim nothing changed"

    PATH="$saved_path"
    rm -rf "$tmp"
}

# The other half of the mix: decline the qol block, accept EDITOR. Proves
# the conditional summary logic is symmetric, not just checked one way.
test_summary_mixed_reverse() {
    local tmp; tmp="$(mktemp -d)"
    make_stub_nano "$tmp/bin" "9.1"
    mkdir -p "$tmp/home"

    local saved_path="$PATH"
    PATH="$tmp/bin:$saved_path"

    local out rc
    out="$(printf 'n\ny\n' | QOL_NANO_NO_INSTALL=1 QOL_NANO_FORCE_TTY=1 SHELL=/bin/zsh \
           HOME="$tmp/home" ./install_nano.sh --no-syntax --set-editor 2>&1)"
    rc=$?

    assert_eq "0" "$rc" "mixed decline/accept: exits 0"
    assert_fail "[ -f '$tmp/home/.nanorc' ]" \
        "mixed decline/accept: no .nanorc written (declined)"
    assert_contains "$(cat "$tmp/home/.zshrc")" "export EDITOR=nano" \
        "mixed decline/accept: EDITOR written (accepted)"
    assert_contains "$out" "was not written (declined)" \
        "mixed decline/accept: summary says the qol block was declined"
    assert_contains "$out" "nano is ready" \
        "mixed decline/accept: still shows ready, since something was written"

    PATH="$saved_path"
    rm -rf "$tmp"
}

test_summary_accept_everything
test_summary_decline_everything
test_summary_mixed
test_summary_mixed_reverse

printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ "$TESTS_FAILED" -eq 0 ]]
