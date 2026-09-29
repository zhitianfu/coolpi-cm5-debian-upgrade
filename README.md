# Cool Pi CM5 (RK3588) — Debian 11 → 13 upgrade notes

Field notes and scripts from upgrading a **Cool Pi CM5 GenBook** laptop from
**Debian 11 (bullseye)** to **Debian 13 (trixie)** running the *vendor* image
(vendor kernel + extlinux boot + u-boot on SPI-NOR).

The upgrade itself is ordinary Debian work. The pain is everything the vendor
image does differently, so this repo documents the traps, the fixes, and the one
thing that cannot be fixed from the OS.

It also carries the Hermes Agent skill ([`skills/`](skills/)) that was used to
reach and repair the machine — the laptop was unreachable over the network, so
the whole job was driven from a rooted Android phone over USB. That skill is
board-agnostic; the CM5 profile and the upgrade-specific notes live in its
references.

## Hardware / image profile this was tested on

| Item | Value |
|---|---|
| SoC | Rockchip RK3588 (4×A76 + 4×A55) |
| PMIC | RK806 (SPI-attached, `rk806single@0`) |
| Boot chain | u-boot/SPL on **SPI-NOR**, `extlinux.conf` + kernel/DTB on eMMC `/boot/firmware` |
| Kernel | vendor `6.1.75`, shipped as `/boot/firmware/Image` (not a Debian kernel) |
| Root | ext4 on eMMC (`root=LABEL=writable`), NVMe present for scratch space |
| WiFi | Realtek RTL8852BE (rtw89 driver) |
| Display | eDP 1920×1080, vendor DRM stack |
| Userspace after upgrade | Debian 13.x, GNOME 48 |

## TL;DR

1. Before upgrading: `scripts/preflight-inventory.sh` (records what matters),
   back up `/etc` + `/boot/firmware`, and **test a reboot first** so you know
   whether your board already needs a power key.
2. Upgrade in **two hops** (bullseye → bookworm → trixie); never skip a release.
3. After the upgrade, if you get a black screen with no login, it is almost
   certainly the **gdm/Wayland** trap → `scripts/post-upgrade-fix.sh`.
4. Verify with `scripts/verify-upgrade.sh`.
5. Know the firmware-level issue in [`docs/04-known-issues.md`](docs/04-known-issues.md):
   a **warm reboot may not restart the board** (power key required). Don't hack
   the device tree for it.

## Contents

| Path | Purpose |
|---|---|
| [`docs/01-pre-upgrade-checklist.md`](docs/01-pre-upgrade-checklist.md) | What to record, back up, and decide before touching apt |
| [`docs/02-upgrade-steps.md`](docs/02-upgrade-steps.md) | The two-hop upgrade procedure and what to expect |
| [`docs/03-post-upgrade-fixes.md`](docs/03-post-upgrade-fixes.md) | The real post-upgrade breakages and their fixes |
| [`docs/04-known-issues.md`](docs/04-known-issues.md) | Warm-reboot fault, WiFi firmware noise, backlight, SSH policy |
| [`docs/05-recovery-maskrom.md`](docs/05-recovery-maskrom.md) | Recovering a non-booting board over USB Maskrom (no x86 PC needed) |
| `scripts/preflight-inventory.sh` | Read-only inventory → timestamped file you can archive |
| `scripts/post-upgrade-fix.sh` | Idempotent gdm/plymouth fix (with backups) |
| `scripts/verify-upgrade.sh` | Read-only post-upgrade verification report |
| `scripts/prepublish-scan.sh` | Secret/PII scan to run before publishing notes like these |
| [`skills/usb-hid-remote-console/`](skills/usb-hid-remote-console/) | Hermes Agent skill: administering an unreachable machine from a phone (see below) |

## Hermes Agent skill: `usb-hid-remote-console`

A [Hermes Agent](https://hermes-agent.nousresearch.com/docs) skill — a
`SKILL.md` the agent loads on a matching trigger, plus `references/` and ready-to-run
`scripts/`. Use it when a machine has no console, keyboard or network path: the phone
presents itself as a USB **boot-protocol keyboard** for input, a USB **Ethernet**
gadget where an SSH shell is possible, and an HTTP **beacon** channel for output.

Install it by copying the directory into a Hermes skills tree:

```sh
cp -a skills/usb-hid-remote-console ~/.hermes/skills/software-development/
```

What it covers:

- triage order for a machine reported "dead" (usually it boots and has no network),
- the configfs HID-keyboard recipe plus its `EINVAL`/stale-config trap,
- quoting-free typing via a JSON plan driver (`scripts/hid_drive.py`),
- hex-based output exfiltration (`scripts/exfil_hex.sh`),
- 25 field-tested rules: dropped USB links swallowing keystrokes, `pkill -f` killing
  your own shell, fail2ban, a VPN hijacking the cable route, a Wayland greeter owning
  the keyboard, and a wrong `.dtb` from a dangling `extlinux.conf` `default` label,
- `references/coolpi-cm5-genbook.md` — this laptop's profile (boot chain, Maskrom
  entry, phone-side recovery tooling), and
- `references/rockchip-and-debian-notes.md` — the breakage patterns a Debian release
  upgrade leaves on a vendor image.

## Scope, honesty, and non-goals

- These are **field notes for one class of vendor image**, not an official
  procedure. Validate on your hardware; keep a recovery path.
- The scripts are conservative: they back up before changing, they are
  re-runnable, and none of them write to the boot chain or flash.
- No credentials, tokens, serial numbers, MAC addresses, SSIDs or public IPs are
  stored here — every environment-specific value is a `<PLACEHOLDER>` or an
  RFC-reserved example address. `scripts/prepublish-scan.sh` checks that before
  any push.

## Licence

MIT — see [LICENSE](LICENSE).
