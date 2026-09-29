# 04 — Known issues and limits (read before you plan work)

## 1. Warm reboot does not restart the board — power key required  ⚠️ firmware-level

**Behaviour** (measured, reproducible):

- `systemctl reboot` (or `reboot`) shuts the OS down **cleanly** — the journal
  records `NetworkManager exiting (success)`, `Journal stopped`, then nothing.
- The board never comes back: no U-Boot, no display, no USB enumeration, no
  network, no ARP reply. It stays dark until the **power button** is pressed.
- A cold boot from the power key works normally.

**What is *not* the cause**

- Not the upgrade: the shutdown itself is clean, and the filesystem comes back
  without recovery.
- Not a missing PMIC reset configuration. On this board the device tree already
  configures the RK806 reset path (`pmic-reset-func = <...>`) and a
  `pmic-power-off` pinctrl state. Mainline-style kernel messages such as

  ```
  rk8xx: no reset-setting pinctrl state
  rk8xx: no sleep-setting state
  ```

  are **name mismatches, not defects**: the vendor DT deliberately uses the
  Rockchip `pmic-reset-func`/`pmic-power-off` scheme instead of the mainline
  `sleep`/`reset` state names. Adding those states via a device-tree overlay is
  therefore an unproven change against your only boot chain — not worth it.

**Why there is no OS-level mitigation**

- No `/dev/watchdog` (the SoC watchdog node exists in the DT but is not exposed),
  so systemd's `RebootWatchdogSec=` cannot rescue a hung reset.
- `kexec` is not available on the vendor kernel, so no kexec-based reboot.
- RTC-alarm wake (`rtcwake`) is a possible trick on boards that wire the RTC
  alarm to the PMIC's power-on path — untested here; verify with a spare
  power-cycle in hand before relying on it.

**How to actually diagnose it**

Put a USB-TTL adapter on the board's UART. The kernel cmdline already contains
`console=ttyS0,115200n81`, so the serial console shows SPL/U-Boot/kernel output
and will say whether the SoC resets at all and where it stops. Guessing at the
device tree is strictly worse than 30 seconds of serial output.

**Likely real fix:** a vendor **U-Boot/ATF update** (warm-reset/PMIC sequencing).
Do not attempt that without a working Maskrom recovery path —
see [`05-recovery-maskrom.md`](05-recovery-maskrom.md).

**Practical workaround:** after `reboot`, press the power key. Keep the shutdown
clean and this costs you one button press, not a reinstall.

---

## 2. Vendor kernel and DT are not upgraded by the release upgrade

Debian's upgrade moves **userspace**. Your kernel stays the vendor `6.1.75`
`Image` and your DTB stays the vendor DTB — which is usually what you want on
these boards, but it means:

- Kernel CVE fixes do not arrive via the dist-upgrade.
- A Debian `linux-image-*` installed by accident can fight with the vendor boot
  configuration. Check `uname -r` after the upgrade and keep
  `u-boot-*` / `flash-kernel` held if the image uses them.

### A trap worth knowing: a wrong `default` label

`/boot/firmware/extlinux/extlinux.conf` selects the boot entry by label, e.g.
`default <label>`. If a vendor update (or you) sets `default` to a label that
does not exist in the file, extlinux silently boots the **first** entry instead —
which may be another board's DTB. Symptom: boot works but the panel/network/PMIC
misbehave (a plausible "black screen after an update"). Always confirm the
`default` label exists:

```sh
awk '/^default/{print "default target:", $2}' /boot/firmware/extlinux/extlinux.conf
grep -n '^label' /boot/firmware/extlinux/extlinux.conf
```

---

## 3. Failed units that may be normal on vendor images

- `dnsmasq.service` — commonly failed on these images (vendor leftovers), and
  usually irrelevant unless you actually use it as a DNS/DHCP server.
- `plymouth-quit.service` — see doc 03 §2; it is a downstream symptom of a
  broken display manager, not an independent fault.

Treat "failed unit" as *a question to answer*, not an emergency: check
`systemctl status <unit>` and whether anything you use depends on it.

---

## 4. SSH policy can lock you out after an upgrade

Vendor images often restrict SSH to key-only authentication, a specific user,
and a specific source range, e.g.:

```
AllowUsers <user>@100.64.0.0/10      # VPN/tailnet range only
PasswordAuthentication no
```

Two consequences:

- LAN SSH may be **refused by design** even though port 22 is open and the key is
  correct — do not weaken the policy to "fix" it mid-upgrade.
- Do the release upgrade where you can reach a **local console** (or via the
  permitted VPN range), because if the display manager breaks you may have no
  graphical way in.

---

## 5. Do not chase cosmetic firmware warnings

`TXPWR_LMT.txt`, `regulatory.db` and similar load failures at boot are optional
firmware tables; the drivers fall back to defaults. They are noise unless you
have evidence the radio is actually down (doc 03 §4).

---

## 6. Flash/charge caveat (hardware)

On some CM5 carrier boards the USB-C wiring lacks back-feed protection: do
**not** power the board from one USB-C port while another port has a host
attached (e.g. a phone acting as a console). Power from the intended DC input.
