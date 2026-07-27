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

printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ "$TESTS_FAILED" -eq 0 ]]
