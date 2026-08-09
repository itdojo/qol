#!/usr/bin/env bash
# Proves kernel_update.sh will not offer to reboot into a kernel that cannot boot.
#
# The failure this guards against, observed on Ubuntu 24.04 arm64 in VMware
# Fusion on 2026-08-09: `mainline install-latest` installed 7.1.5-070105-generic,
# the linux-image postinst failed (dpkg left it `iF`), so update-initramfs never
# ran. /boot got vmlinuz-7.1.5-070105-generic with no initrd.img beside it.
# linux-modules had already unpacked, so /usr/lib/modules named the new kernel
# and the script offered to boot it. update-grub writes a menuentry with no
# initrd line when the initramfs is missing, so the reboot panicked with
# "VFS: Unable to mount root fs on unknown-block(0,0)".
#
# These tests drive the two guard helpers against fixture /boot trees. Case 2 is
# the VM's exact state and is the regression this file exists for.
#
# Run: ./tests/test-kernel-activate-guard.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/linux/kernel_update.sh"

TESTS_RUN=0
TESTS_FAILED=0

# Pull the guards out of kernel_update.sh rather than sourcing it: the script
# runs its whole update top-to-bottom the moment it is sourced.
extract_fn() { sed -n "/^$1() {/,/^}/p" "$SCRIPT"; }

for fn in kernel_boot_files_ok half_installed_kernel_packages; do
    body="$(extract_fn "$fn")"
    if [[ -z "$body" ]]; then
        printf '  FAIL %s: not defined in linux/kernel_update.sh\n' "$fn"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        continue
    fi
    eval "$body"
done

FIXTURES="$(mktemp -d)"
trap 'rm -rf "$FIXTURES"' EXIT

# case <name> <expected-rc> <boot-dir> <kernel-version> [reason-substring]
case_is() {
    local name="$1" want_rc="$2" boot="$3" kver="$4" want_reason="${5:-}"
    local got_rc
    TESTS_RUN=$((TESTS_RUN + 1))

    if ! declare -F kernel_boot_files_ok >/dev/null; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s: kernel_boot_files_ok is not defined\n' "$name"
        return
    fi

    KERNEL_BOOT_PROBLEM=""
    BOOT_DIR="$boot" kernel_boot_files_ok "$kver"
    got_rc=$?

    if [[ "$got_rc" != "$want_rc" ]]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s: expected rc %s, got %s (reason: %s)\n' \
            "$name" "$want_rc" "$got_rc" "${KERNEL_BOOT_PROBLEM:-none}"
        return
    fi
    if [[ -n "$want_reason" && "$KERNEL_BOOT_PROBLEM" != *"$want_reason"* ]]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL %s: reason %q does not mention %q\n' \
            "$name" "$KERNEL_BOOT_PROBLEM" "$want_reason"
        return
    fi
    printf '  ok   %s\n' "$name"
}

# An initramfs the size of a real one, in spirit: non-empty is what matters.
make_kernel() { printf 'kernel\n' >"$1/vmlinuz-$2"; printf 'initramfs\n' >"$1/initrd.img-$2"; }

# 1. A complete kernel: vmlinuz and its initramfs both present.
complete="$FIXTURES/complete"
mkdir -p "$complete"
make_kernel "$complete" "6.8.0-137-generic"
case_is "complete kernel passes" 0 "$complete" "6.8.0-137-generic"

# 2. THE REGRESSION. The VM's state: kernel image written, initramfs never built.
noinitrd="$FIXTURES/noinitrd"
mkdir -p "$noinitrd"
make_kernel "$noinitrd" "6.8.0-137-generic"
printf 'kernel\n' >"$noinitrd/vmlinuz-7.1.5-070105-generic"
case_is "missing initramfs is refused" 1 "$noinitrd" "7.1.5-070105-generic" "initramfs"

# 3. A zero-byte initramfs: what update-initramfs leaves behind when /boot fills
#    up mid-write. Present but useless, and it panics exactly the same way.
truncated="$FIXTURES/truncated"
mkdir -p "$truncated"
printf 'kernel\n' >"$truncated/vmlinuz-7.1.5-070105-generic"
: >"$truncated/initrd.img-7.1.5-070105-generic"
case_is "empty initramfs is refused" 1 "$truncated" "7.1.5-070105-generic" "initramfs"

# 4. Named kernel is not in /boot at all.
case_is "absent kernel image is refused" 1 "$noinitrd" "9.9.9-generic" "vmlinuz"

# 4. Raspberry Pi OS boots kernel8.img from firmware and uses no initramfs.
#    There is no vmlinuz/initrd pair to check, so the guard must not veto.
pi="$FIXTURES/pi"
mkdir -p "$pi"
touch "$pi/kernel8.img" "$pi/config.txt"
case_is "non-vmlinuz boot layout is not vetoed" 0 "$pi" "6.12.0-rpi-v8"

# 5. dpkg reports a half-installed kernel package.
if declare -F half_installed_kernel_packages >/dev/null; then
    TESTS_RUN=$((TESTS_RUN + 1))
    fake_bin="$FIXTURES/bin"
    mkdir -p "$fake_bin"
    cat >"$fake_bin/dpkg-query" <<'STUB'
#!/usr/bin/env bash
printf 'ii  linux-image-6.8.0-137-generic\n'
printf 'iF  linux-image-unsigned-7.1.5-070105-generic\n'
printf 'rc  linux-image-6.8.0-83-generic\n'
STUB
    chmod +x "$fake_bin/dpkg-query"
    got="$(PATH="$fake_bin:$PATH" half_installed_kernel_packages)"
    if [[ "$got" == "linux-image-unsigned-7.1.5-070105-generic" ]]; then
        printf '  ok   half-installed package is reported, ii and rc are not\n'
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL half-installed detection: got %q\n' "$got"
    fi
fi

printf '\n%d test(s), %d failure(s)\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ "$TESTS_FAILED" -eq 0 ]]
