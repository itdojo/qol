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

    # Real pico, when present (macOS ships it at /usr/bin/nano). Guarded so
    # the suite still passes on Linux, where that path is real GNU nano.
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

printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ "$TESTS_FAILED" -eq 0 ]]
