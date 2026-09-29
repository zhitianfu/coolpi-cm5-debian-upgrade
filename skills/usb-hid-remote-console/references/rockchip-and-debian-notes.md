# Rockchip boards and Debian-release breakage — notes for phone-side rescues

## Maskrom / boot-chain tooling built on the phone (no x86 PC needed)

- `rkdeveloptool` (rockchip-linux): `pkg install libusb autoconf automake libtool make clang pkg-config git`, then `autoreconf -i && ./configure && make CXXFLAGS="-g -O2 -Wno-vla-cxx-extension"`. Upstream compiles with `-Werror` and modern clang rejects its C++ VLAs, so that extra flag is required. Its advertised `pack` / `unpack` are **not wired into this build** (exit 255) — do not plan on generating a loader container with it.
- `xrock` (xboot/xrock, MIT): `make` with libusb is enough; `xrock maskrom <ddr.bin> <usbplug.bin> --rc4-off` covers the two-stage Maskrom load, plus `flash read/write/erase`, `storage`, `reset maskrom`.
- Blobs come from `rockchip-linux/rkbin`, `bin/rk35/`: `rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.*.bin`, `rk3588_usbplug_v1.11.bin`, `rk3588_bl31_v1.*.elf`. **List the directory through the GitHub API instead of guessing names** — a wrong guess returns a 14-byte `404: Not Found` file that looks like a real download until you inspect the header bytes.
- Typical u-boot build: `ROCKCHIP_TPL=<ddr blob> BL31=<bl31 elf> make <board>_defconfig && make` → `u-boot-rockchip.bin` (eMMC, sector 64) and `u-boot-rockchip-spi.bin` (SPI-NOR, offset 0).
- Maskrom entry: hold the board's Loader/recovery key and power on; the BootROM exposes itself on the documented USB-C port. The host must be powered and in host role — **an unpowered board presents nothing on a C-to-C link because its CC lines are dead**, so "the cable shows nothing" may simply mean "no power".

## GenBook-class hardware (RK3588 + RK806)

- RK3588 SoM on a laptop carrier: 8 MB SPI-NOR holding SPL/u-boot, eMMC root (`/boot/firmware` + `/` labelled `writable`), optional M.2 NVMe, eDP 1920x1080, RTL8852BE WiFi.
- WiFi quirk: NetworkManager may drive the station connection on **`p2p0`** while `wlan0` stays `DOWN`. A working network with `wlan0` down is normal here — do not "fix" the wrong interface.
- `Direct firmware load for TXPWR_*.txt failed with error -2` are optional Realtek power-limit tables; cosmetic, not the cause of a dead network.
- PMIC is RK806 over SPI. The log line `no reset-setting pinctrl state` means the device tree never defines the PMIC reset pinmux.

## Warm reboot that lands dead (no bootloader, no USB, no network)

Evidence pattern: the OS shuts down cleanly (`journalctl -b -1 -e` ends with `NetworkManager ... exiting (success)` and `systemd-journald: Journal stopped`), then the board never restarts until someone presses the power key. That is a firmware/reset fault, not a Debian bug.

- Why: RK3588 vendor device trees universally leave PMIC-based reset unconfigured (confirmed in upstream discussion), so warm reset falls back to PSCI and the board ends up unpowered or hung.
- Mitigations usually unavailable — check before proposing them: no `/dev/watchdog` (so no `RebootWatchdogSec` rescue), no kexec (`/sbin/kexec`, `kexec_load_disabled`).
- Real fix = a device-tree overlay adding the PMIC reset state, or a vendor u-boot/ATF update. Both touch the boot chain: get explicit consent first, and have Maskrom tooling ready as the recovery path.
- Otherwise the honest deliverable is the workaround: after `reboot` the power key brings it back. Say so plainly instead of implying reboots are fixed.

## Debian release upgrade on a vendor image (bullseye → trixie class)

- **The display path breaks first.** Trixie's GNOME ships only `/usr/share/wayland-sessions/*.desktop` and no `/usr/share/xsessions` at all. A vendor `/etc/gdm3/daemon.conf` containing `WaylandEnable=false` (a bullseye-era workaround) makes gdm abort with `GdmSession: no session desktop files installed`, die with `status=5/TRAP`, and hit `Start request repeated too quickly` — no greeter, so a black screen with nothing to log into. Fix: back the file up, comment out `WaylandEnable`, `systemctl reset-failed gdm`, restart, then verify *gdm active*, a `gnome-shell` greeter running, and a `pam_unix(gdm-password:session): session opened for user <u>` line after a real login attempt.
- `plymouth-quit.service` failing (`start-limit-hit`) rides along with a crashing gdm and clears with the same fix; it is not an independent fault.
- A boot-time NetworkManager failure can be transient — check `systemctl is-active NetworkManager` before "repairing" it, and note that restarting NM drops the WiFi link for about a minute.
- `dpkg -l` status `hi` means hold + installed, not half-installed; held old-release leftovers (e.g. `python3.9` on a trixie system) are common and harmless.
- `dnsmasq.service` failing is typically unrelated (tailnet) — mention it, do not chase it.
- `gsd-power: update_mutter_backlight: assertion 'backlights != NULL' failed` means GNOME cannot drive the panel backlight; a "black screen" complaint can be a backlight/plane issue (`drm:vop2_plane_atomic_check` min-size errors) rather than a boot failure.

## Access-policy pattern on hardened images

`AllowUsers user@100.64.0.0/10` restricts SSH to the tailnet/CGNAT range: a LAN source is correctly refused, and that is **intentional**. Read it with `sshd -T` (the effective config prints lowercase keywords), do not edit it to get in, and use the machine's own console instead.
