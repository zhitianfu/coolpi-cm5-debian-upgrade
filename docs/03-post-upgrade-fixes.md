# 03 — Post-upgrade fixes (what actually breaks)

These are the failures seen on a Cool Pi CM5 vendor image after the
bullseye → trixie upgrade, with the fix for each. `scripts/post-upgrade-fix.sh`
applies the gdm and plymouth fixes idempotently.

---

## 1. Black screen, no login screen — the gdm/Wayland trap  ⚠️ the big one

**Symptom**

- The machine boots (kernel messages, network up) but you never get a greeter;
  the display stays dark.
- `systemctl --failed` shows `gdm.service` failed.
- `journalctl -u gdm -b` shows:

  ```
  Gdm: GdmSession: no session desktop files installed, aborting...
  gdm.service: Main process exited, code=killed, status=5/TRAP
  gdm.service: Start request repeated too quickly.
  ```

**Cause** — a two-sided mismatch, and neither side is "broken":

- `/etc/gdm3/daemon.conf` contains `WaylandEnable=false` (typical for a
  Debian 11 era vendor image, which shipped an X11 session).
- Debian 13's GNOME ships **Wayland session files only**:
  `/usr/share/wayland-sessions/{gnome.desktop,gnome-wayland.desktop}` exists,
  while **`/usr/share/xsessions/` does not exist at all**.

So gdm is told "no Wayland", finds no X11 session to fall back to, and aborts.

**Diagnose**

```sh
systemctl status gdm --no-pager
journalctl -u gdm -b --no-pager | tail -40
ls /usr/share/wayland-sessions/ 2>/dev/null
ls /usr/share/xsessions/ 2>/dev/null || echo "no X11 sessions installed (expected on trixie)"
grep -n WaylandEnable /etc/gdm3/daemon.conf
```

**Fix**

```sh
sudo cp -a /etc/gdm3/daemon.conf /etc/gdm3/daemon.conf.bak
sudo sed -i 's/^[[:space:]]*WaylandEnable=.*/#&   # commented by post-upgrade fix: trixie GNOME is Wayland-only/' /etc/gdm3/daemon.conf
sudo systemctl restart gdm          # or: sudo systemctl reset-failed gdm && sudo systemctl start gdm
```

(Or install the X11 fallback session instead — `sudo apt install gnome-session`
plus the Xorg session package — but enabling Wayland is the smaller change. If
your GPU stack has no working Wayland driver, this is the moment you find out.)

**Verify**

```sh
systemctl is-active gdm                                  # active
pgrep -af 'gdm-session-worker'                           # greeter worker present
loginctl list-sessions                                   # a greeter session on tty1
journalctl -b | grep -i 'session opened for user'         # your successful login
```

A successful login logs, from the gdm side, a line like
`gdm-password]: *** session opened for user <user>(uid=1000)` and typically
`gkr-pam: unlocked login keyring` for the GNOME keyring.

---

## 2. `plymouth-quit.service` failed (`start-limit-hit`) — downstream symptom

Usually **not** a separate bug: while gdm crash-loops, the display never comes up,
so plymouth's quit job hits its start limit. Fix gdm first, then:

```sh
sudo plymouth --quit
sudo systemctl reset-failed plymouth-quit plymouth-quit-wait
systemctl --failed
```

Expect the count of failed units to drop on its own once gdm is healthy.

---

## 3. NetworkManager / WiFi quirks

```sh
systemctl is-active NetworkManager
nmcli dev status
nmcli con show --active
```

Two things worth knowing on this class of board:

- The station connection may be reported on `p2p0` while `wlan0` shows
  `disconnected`. On RTL8852BE/rtw89 with vendor kernels this is cosmetic — the
  link works. Don't "repair" it into an actual outage.
- If `wlan0` genuinely stays down, check `rfkill list` and
  `dmesg | grep -i rtw89` before touching profile config.

---

## 4. Harmless WiFi firmware noise (don't chase it)

```
Direct firmware load for TXPWR_LMT.txt failed with error -2
```

Repeated firmware-load failures for Realtek **power-limit tables** (and
sometimes `regulatory.db`) are expected on vendor images: they are optional
per-regulatory-domain tables. The driver falls back to defaults and the radio
works. Install `firmware-realtek` if you want the fullest set; do not treat this
as the cause of a "no WiFi" report until you have checked `nmcli dev status`.

---

## 5. Backlight assertion — a "black screen" that is not a crash

```
gsd-power: update_mutter_backlight: assertion 'backlights != NULL' failed
```

GNOME (via mutter) cannot find a controllable backlight device, so screen
brightness keys and automatic dimming do nothing. If you ever see a dark panel
with the machine clearly running, suspect the backlight (or panel power) before
suspecting the OS: check `ls /sys/class/backlight/`, and the display's presence
with `cat /sys/class/drm/*/status`.

---

## 6. Leftover greeter sessions after a crash loop

After gdm has crash-looped, stale sessions accumulate:

```sh
loginctl list-sessions
loginctl terminate-session <ID>      # for the stale greeter sessions
```

---

## 7. Final verification

```sh
scripts/verify-upgrade.sh
```

What "done" looks like: Debian 13.x, vendor kernel unchanged, `systemctl --failed`
empty or explained, gdm active with a greeter, you can log in, networking up.
