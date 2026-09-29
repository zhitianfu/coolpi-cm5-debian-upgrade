# Cool Pi CM5 (RK3588) — Debian 11 → 13 upgrade notes

Field notes and scripts from upgrading a **Cool Pi CM5 GenBook** laptop from
**Debian 11 (bullseye)** to **Debian 13 (trixie)** running the *vendor* image
(vendor kernel + extlinux boot + u-boot on SPI-NOR).

The upgrade itself is ordinary Debian work. The pain is everything the vendor
image does differently, so this repo documents the traps, the fixes, and the one
thing that cannot be fixed from the OS.

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

| File | Purpose |
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

## Scope, honesty, and non-goals

- These are **field notes for one class of vendor image**, not an official
  procedure. Validate on your hardware; keep a recovery path.
- The scripts are conservative: they back up before changing, they are
  re-runnable, and none of them write to the boot chain or flash.
- No credentials, tokens, serial numbers, MAC addresses, SSIDs or public IPs are
  stored here — every environment-specific value is a `<PLACEHOLDER>`.

## Licence

MIT — see [LICENSE](LICENSE).
