# netstatus — shell-startup network status line

**Date:** 2026-07-26
**Status:** approved, not yet implemented

## Goal

A single compact line printed when a terminal opens, giving a quick read on Wi-Fi
association and internet reachability. Must feel instant, must work on macOS and
Linux, and must not repeat itself in every tmux pane.

Supersedes `linux/wifi_check.sh` and `linux/internet_check.sh`.

## Problems with the current scripts

1. `internet_check.sh` blocks on `ping -c 1 -W 2` plus a DNS lookup — worst case
   roughly four seconds of dead terminal, on exactly the broken network where you
   most want the readout.
2. Both files call their function at the bottom, so sourcing runs them. That makes
   them shell-startup snippets rather than reusable libraries; nothing else can
   source them to ask a question without also triggering output.
3. `wifi_check.sh` is Linux-only (`nmcli` / `iw` / `iwgetid`). The primary machine
   is macOS.
4. ICMP is a poor internet signal. Firewalls blackhole it, producing false
   negatives, and it cannot detect a captive portal.

## Verified environment facts

Confirmed by direct probe on macOS 26.5.2, 2026-07-26:

- `networksetup -getairportnetwork en0` reports `You are not associated with an
  AirPort network.` **while actually associated**. It is unreliable on modern
  macOS and must not be the primary source.
- **The SSID is gated behind Location Services.** Since macOS 14, a process must
  hold location authorization to read the network name. Without it macOS does not
  return an error — it returns the literal ten-character string `<redacted>`,
  confirmed byte-exact with `od -c`. Every path is gated identically:
  `ipconfig getsummary` and `system_profiler SPAirPortDataType` both yield
  `<redacted>`, and `networksetup` claims no association. `wdutil` needs sudo and
  redacts anyway; CoreWLAN returns nil. There is no unprivileged workaround.

  This is the dangerous case, because `<redacted>` is a plausible-looking value
  that renders as a network name unless explicitly checked. `_ns_ssid_macos` must
  test for it and signal status 2 — associated, name withheld — which is distinct
  from both "here is the name" and "no Wi-Fi". Its presence still proves
  association, so the renderer shows `🛜 Wi-Fi` rather than falling through to
  `🔌 Wired` and implying a link type that isn't there.

  There is no configuration fix. Apps appear in System Settings → Privacy &
  Security → Location Services only *after* requesting authorization, and
  terminal emulators never call CoreLocation, so they never register. Granting
  access would require shipping a helper binary that requests it — deliberately
  not done. `🛜 Wi-Fi` is the accepted answer.
- `ipconfig getsummary en0` returns the SSID correctly **when authorized**.
- `ipconfig getsummary` prints `BSSID` (line 2) before `SSID` (line 69). The SSID
  matcher must be anchored (`/^[[:space:]]*SSID[[:space:]]*:/`) or it captures the
  BSSID instead.
- `curl` to a `generate_204` endpoint completes in ~50 ms on a healthy network.
- tmux 3.7b: `tmux show-option -t <sess> -qv @name` reads empty, `set-option`
  then reads `1`, and the value does **not** appear in `show-option -gqv`. The
  `-t` flag must precede `-qv`; the reverse order errors with
  `command show-options: too many arguments (need at most 1)`.

## Architecture

One new sourceable file at the repo root: `netstatus.sh`. It defines functions and
runs nothing on source. Callers decide when to execute.

### Public interface

| Function | Purpose |
|---|---|
| `netstatus` | Print status, honouring the cache freshness policy. |
| `netstatus -f` | Force a fresh synchronous probe, then print. |
| `netstatus_boot` | `.zshrc` entry point: applies the tmux gate, then calls `netstatus`. |

Internal helpers are prefixed `_ns_`.

### Probe strategy

The happy path costs one network call. `curl` to a *hostname* 204 endpoint
exercises DNS, reachability, and portal interception at once. Only on failure does
a second call to a *bare IP* separate "DNS is broken" from "nothing is reachable".

| Probe A (hostname) | Probe B (IP) | Rendered |
|---|---|---|
| 204 | not run | `✅ Internet  ✅ DNS` |
| 200 / 302 / 511 | not run | `🔒 Captive portal` |
| fail | ok | `✅ Internet  ❌ DNS` |
| fail | fail | `❌ Offline` |

Captive-portal detection is the state ping cannot see and the one most often hit in
hotels and airports.

Tunable via environment, with defaults:

- `NETSTATUS_URL_HOST` — `http://connectivitycheck.gstatic.com/generate_204`
- `NETSTATUS_URL_IP` — `http://1.1.1.1/`
- `NETSTATUS_TIMEOUT` — `2` (seconds, per probe)

If `curl` is absent, fall back to `ping`. Note the portability trap: `ping -W`
takes **milliseconds on macOS and seconds on Linux**. Use `ping -c1 -t1` on macOS
and `ping -c1 -W1` on Linux.

### SSID detection

macOS: discover the Wi-Fi device from `networksetup -listallhardwareports`, keying
on an anchored `^Hardware Port: (Wi-Fi|AirPort)$` and taking `$2` of the next line.
Then read `ipconfig getsummary <dev>` with the anchored SSID matcher. Fall back to
`networksetup -getairportnetwork <dev>` only if that yields nothing.

Linux: keep the existing cascade unchanged — `nmcli` (unescaping `\:` in `-t`
output), then `iw dev`, then `iwgetid --raw`.

### Rendered output

```
 🛜 MyNetwork   ✅ Internet   ✅ DNS
 🛜 HotelWiFi   🔒 Captive portal
 🛜 Wi-Fi       ✅ Internet   ✅ DNS
 🔌 Wired       ✅ Internet   ✅ DNS
 ❌ No network
```

**The label is chosen by the default route, not by Wi-Fi association.** Being
associated to Wi-Fi does not mean Wi-Fi carries your traffic: with a dock or USB
adapter attached, both links are up and the wired one wins. Labelling by
association alone credits connectivity to the wrong interface — observed on the
development machine, where `en7` (USB 2.5G Ethernet) held the default route while
`en0` was associated and idle.

- Default route is on the Wi-Fi device → SSID, or `🛜 Wi-Fi` if withheld.
- Default route is on anything else → `🔌 Wired`. Not probed beyond the route, so
  a VPN or tethered link renders this way too.
- No default route at all → the Wi-Fi label if associated (which usefully
  separates "associated but going nowhere" from "nothing connected"), otherwise
  `❌ No network`.

Wi-Fi interface identification: on macOS, compare against
`networksetup -listallhardwareports`; on Linux, test for `/sys/class/net/<dev>/wireless`.

### Cache

Path: `${XDG_CACHE_HOME:-$HOME/.cache}/qol/netstatus`

Two lines: epoch seconds, then the rendered text. Written to a temp file and moved
into place with `mv`, so a concurrent reader cannot see a torn write. No locking —
two simultaneous probes are harmless and a lock adds a stale-lock failure mode.

### Freshness policy

| Cache age | Behaviour |
|---|---|
| < 30 s | Print cached. No refresh. |
| 30 s – 5 min | Print cached instantly, refresh in the background. |
| > 5 min, or missing | Probe synchronously (~50 ms typical, 2 s cap), then print. |

This keeps the common case at zero cost while ensuring a lid-open after days shows
current information rather than a days-old line.

Background refresh is spawned as `( _ns_refresh >/dev/null 2>&1 & )`. The inner
job is orphaned when the subshell exits, so it survives the shell, never reports
job-control messages, and holds no terminal file descriptor. This form works in
sh, bash, and zsh, unlike zsh's `&!`.

### tmux gate

Outside tmux, always print. Inside tmux, print only if the session-scoped user
option `@qol_netstatus_shown` is empty, setting it immediately afterward. The
marker dies with the session, so no files are created and no cleanup is needed.
Attaching to an existing session correctly stays quiet.

Argument order matters: `tmux show-option -t "$sess" -qv @qol_netstatus_shown`.

## Wiring

The source line and a `hint` menu entry go into the repo's
`custom-zshrc-entries.txt`, matching its documented role as the personal
`.zshrc` additions file. The same lines are applied to the live `~/.zshrc`
**outside** the `# >>> qol starship block >>>` markers, since that block is
rewritten wholesale by `install_zsh_starship.sh` on every run.

`~/.zshrc` is backed up before editing and validated with `zsh -n` afterward.

## Removals

`linux/wifi_check.sh` and `linux/internet_check.sh` are deleted. The root
`README.md` tool table and `linux/README.md` are updated: two rows removed, one
row added for `netstatus.sh`.

## Testing

Behaviour that can be verified directly on this machine:

- SSID matcher returns the SSID, not the BSSID. Assert on the actual value, not
  on its shape — a "does it look like a MAC address" check passes the `<redacted>`
  placeholder, which is how that bug initially escaped review.
- The literal `<redacted>` never reaches the rendered line under any state.
- Healthy network renders `✅ Internet  ✅ DNS`.
- Offline is simulated by pointing `NETSTATUS_URL_HOST` and `NETSTATUS_URL_IP` at
  an unroutable address; expect `❌ Offline` within the timeout.
- DNS failure is simulated by pointing `NETSTATUS_URL_HOST` at a hostname that
  does not resolve while leaving `NETSTATUS_URL_IP` valid; expect
  `✅ Internet  ❌ DNS`.
- Cache file contains two lines and a plausible epoch; a second immediate call
  does not re-probe.
- In tmux, the first pane prints and a second pane in the same session does not.
- `zsh -n ~/.zshrc` and `bash -n netstatus.sh` both pass.

Captive-portal rendering cannot be reproduced locally and is verified by forcing
`NETSTATUS_URL_HOST` at an endpoint returning 200 instead of 204.
