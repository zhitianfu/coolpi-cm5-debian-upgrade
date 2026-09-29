# Cool Pi CM5 GenBook (user's RK3588 laptop)

Device profile for the machine behind the user's "cm5 laptop" reports.

## Hardware / OS

- RK3588 SoM in a laptop carrier: LPDDR5X, 64 GB eMMC, 8 MB SPI-NOR, 1920x1080 eDP panel, 1x USB 3.0 host + USB-C 3.0 (DP AltMode), M.2 NVMe, M.2 WiFi (Realtek, rtw89 driver).
- OS as found: Debian 13 (`/etc/debian_version` 13.x), hostname `<hostname>`, vendor kernel 6.1.75.
- Hostname and desktop user come from the vendor image (desktop user is uid 1000).

## Boot chain and recovery entry points

- u-boot SPL lives in SPI-NOR with **two copies** (offsets `0x10000` and `0x60000`); both must be intact for the BootROM to load one.
- BootROM Maskrom USB appears on the **left-side USB-C port**; the **Loader key on the bottom** (under the back cover) disables SPI and eMMC boot so the BootROM falls into Maskrom.
- Recovery tooling that works **phone-side** (aarch64 Termux, no x86 PC needed):
  - `rkdeveloptool` — builds from source but upstream uses `-Werror`, and clang fails on C++ VLAs: `make CXXFLAGS="-g -O2 -Wno-vla-cxx-extension"` (flag must come after `-Werror`). `pack`/`unpack` are not wired into this build.
  - `xrock` (MIT, `xrock maskrom <ddr> <usbplug> [--rc4-off]`, plus `flash read/write/erase`, `storage`, `reset maskrom`) — plain `make`, needs only libusb.
  - Blobs from `rockchip-linux/rkbin`, `bin/rk35/`: `rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.24.bin`, `rk3588_usbplug_v1.11.bin`, `rk3588_bl31_v1.56.elf`.
- Documented (not yet exercised here) u-boot rewrite path: build `coolpi-cm5-genbook-rk3588_defconfig` with `ROCKCHIP_TPL=<ddr blob>` + `BL31=<bl31 elf>` → `u-boot-rockchip-spi.bin` (write at SPI offset 0) and `u-boot-rockchip.bin` (eMMC, sector 64).

## Known post-upgrade defects

- **gdm ends up inactive** while `graphical.target` is active (stale user slices, `loginctl list-sessions` shows several) → no greeter, so the machine shows a boot log or a black screen and there is nothing to log into. Check `systemctl is-active gdm` before blaming the panel.
- **Warm reboot hangs.** `systemctl reboot` took the board down and it never re-entered the boot chain: no u-boot, no USB host activity, no network, no ARP entry. A cold power-on boots normally. Until this is fixed, treat any reboot test as needing a physical power press — do not promise an unattended reboot.
- Package state after the upgrade is generally **healthy**: `systemctl --failed` empty, `dpkg --configure -a` silent, `apt-get -f install` reports nothing to do. `dpkg -l` lines starting `hi` are *held* packages, not half-configured ones — do not "repair" them.
- Residual Debian 11 packages (`python3.9`, `deb11` versions) remain installed alongside trixie. Cosmetic.

## Network particulars

- sshd is **Tailscale-only by design**: `AllowUsers <user>@100.64.0.0/10` (effective config via `sshd -T`). LAN clients are refused with `Permission denied (publickey)` — that is policy, not breakage. `tailscale0` carries `<TAILNET-IP>/32`.
- Expected LAN label: `<hostname>:22` answering `SSH-2.0-OpenSSH_10.0p2 Debian-7+deb13u4`.
- NetworkManager drives the WiFi connection on the **`p2p0`** interface while `wlan0` stays DOWN — a vendor-driver quirk; `nmcli dev status` shows `p2p0 wifi connecting (configuring)` even when the link works.
- Missing-firmware warnings for `TXPWR_LMT.txt`, `TXPWR_ByRate.txt`, `TXPWR_OFT_6G.txt` and `regulatory.db` (`error -2`) are **non-fatal** Realtek power-table/regdb files; the driver still associates. Do not chase them as a connectivity root cause.

## Observed while the panel was dark (75 Hz + workspace change)

- The board was **running Debian the whole time**: `cat /sys/bus/usb/devices/*/authorized` on the host answered through the phone's HID-gadget probe, i.e. a live Linux kernel. A dark panel is not evidence of a dead board — check the USB host path first.
- **No VBUS is supplied to the phone** while attached (host `USB=0`, phone discharging). Do not infer "cable unplugged" from that; infer it from `udc state` + whether the host polls the keyboard endpoint.
- The host **autosuspends** the gadget keyboard when idle (`gadget SUSPEND`); a HID gadget cannot remote-wake it, so writes block until it re-enumerates.
- Fix recipe that was applied blind on a getty (short lines, one per command):
  `mv .config/monitors.xml /tmp/hermes_had_monitors` (the 75 Hz mode lives here),
  `sudo mv /var/lib/gdm3/.config/monitors.xml /tmp/hermes_had_gdm`,
  `sudo sed -i 's/^WaylandEnable=false/#WaylandEnable=false/' /etc/gdm3/daemon.conf` (the Debian-13 greeter crash-loop from the upgrade),
  `gsettings reset org.gnome.mutter dynamic-workspaces | workspaces-only-on-primary | org.gnome.desktop.wm.preferences num-workspaces` (via `dbus-run-session --`, since the console has no session bus),
  then `sudo systemctl restart NetworkManager`, `sudo rfkill unblock all`, `sudo systemctl restart gdm`.
- The panel needs a **cold boot** to recover from a wedged mode; a warm `systemctl reboot` on this board does not re-enter the boot chain, so ask for the 10-second power press.
