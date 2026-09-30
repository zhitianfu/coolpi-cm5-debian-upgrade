# v1.0.0 — Debian 11 → 13 upgrade runbook + remote-console rescue skill

First tagged snapshot. Everything here was produced while actually upgrading a
Cool Pi CM5 GenBook (RK3588) laptop from Debian 11 (bullseye) to Debian 13
(trixie) on the vendor image, with the machine unreachable over the network —
the whole job was driven from a rooted Android phone over USB.

## What's in this release

**Upgrade runbook** (`docs/`)

- `01-pre-upgrade-checklist.md` — inventory what matters, back up `/etc` and
  `/boot/firmware`, prepare a Maskrom recovery path, test a reboot *before*
  upgrading, decide on held packages.
- `02-upgrade-steps.md` — the two-hop procedure (bullseye → bookworm → trixie),
  dry-run before each `full-upgrade`, config-file prompt policy, post-hop checks,
  and the `extlinux.conf` `default`-label trap.
- `03-post-upgrade-fixes.md` — the failures that actually occur, chiefly the
  gdm/Wayland trap: Debian 13's GNOME ships Wayland sessions only, so a
  bullseye-era `WaylandEnable=false` makes gdm abort with
  `no session desktop files installed` and crash-loop to a black screen.
- `04-known-issues.md` — the firmware-level warm-reboot fault (power key
  required, not fixable from the OS; the `no reset-setting pinctrl state` warning
  is a red herring), WiFi firmware noise, backlight assertion, SSH policy.
- `05-recovery-maskrom.md` — recovering a non-booting board over USB Maskrom,
  including building `rkdeveloptool`/`xrock` on ARM.

**Scripts** (`scripts/`, all read-only or backing up before changing)

- `preflight-inventory.sh` — timestamped baseline of OS, kernel, boot config,
  display-manager config, effective sshd policy, held packages.
- `post-upgrade-fix.sh` — idempotent gdm/plymouth fix with backups.
- `verify-upgrade.sh` — read-only post-upgrade verification report.
- `prepublish-scan.sh` — secret/PII gate used before publishing this repo.

**Hermes Agent skill** (`skills/usb-hid-remote-console/`)

Administering a machine with no console, keyboard or network path: USB HID
keyboard injection for input, USB Ethernet for a real SSH shell where possible,
an HTTP beacon channel for output, a JSON-plan typing driver, hex exfiltration,
25 field-tested rules, plus a RK3588 laptop profile and the Debian vendor-image
upgrade notes.

## Known limitation in this release

A **warm reboot may not restart the board** — it needs a power key press. This is
a firmware-level (PMIC/ATF/bootloader) issue, documented with its evidence and the
proper diagnosis route (serial console) rather than papered over with a device-tree
hack. Everything else — OS, packages, login screen, network — works.

## Sanitised

No credentials, keys, serial numbers, MAC addresses, SSIDs, LAN/tailnet addresses,
hostnames or usernames from the source machines: those are `<PLACEHOLDERS>` or
RFC-reserved example addresses, and `scripts/prepublish-scan.sh` enforces that.

## Licence

MIT.
