#!/bin/sh
# Read-only inventory of a vendor ARM image before a Debian release upgrade.
# Usage: sudo sh scripts/preflight-inventory.sh [outfile]
# Writes a timestamped report you can archive and diff after the upgrade.
set -u

OUT="${1:-preflight-$(date +%F-%H%M%S).txt}"

{
  echo "=== when ==="; date; uptime
  echo; echo "=== os / kernel ==="
  (lsb_release -a 2>/dev/null || cat /etc/os-release); uname -a
  echo; echo "=== board model / cmdline ==="
  tr -d '\0' < /proc/device-tree/model 2>/dev/null; echo
  cat /proc/cmdline
  echo; echo "=== block devices ==="; lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS
  echo; echo "=== disk usage ==="; df -h
  echo; echo "=== boot files ==="; ls -l /boot/firmware 2>/dev/null || ls -l /boot
  echo; echo "=== extlinux config ==="; cat /boot/firmware/extlinux/extlinux.conf 2>/dev/null
  echo "--- default label vs labels present ---"
  awk '/^[[:space:]]*default/{print "default label:", $2}' /boot/firmware/extlinux/extlinux.conf 2>/dev/null
  grep -n '^[[:space:]]*label' /boot/firmware/extlinux/extlinux.conf 2>/dev/null
  echo; echo "=== overlays ==="; ls -l /boot/firmware/overlays 2>/dev/null | head -20
  echo; echo "=== failed units ==="; systemctl --failed --no-pager
  echo; echo "=== held packages ==="; apt-mark showhold 2>/dev/null
  echo; echo "=== display manager config ==="
  grep -vE '^[[:space:]]*(#|$)' /etc/gdm3/daemon.conf 2>/dev/null || echo "(no /etc/gdm3/daemon.conf)"
  echo; echo "=== session files available ==="
  ls /usr/share/wayland-sessions/ 2>/dev/null || echo "(no wayland sessions)"
  ls /usr/share/xsessions/ 2>/dev/null || echo "(no X11 sessions)"
  echo; echo "=== effective sshd policy ==="
  sshd -T 2>/dev/null | grep -Ei 'allowusers|denyusers|permitrootlogin|passwordauthentication|pubkeyauthentication' \
    || echo "(needs root or sshd not installed)"
  echo; echo "=== network ==="; nmcli -t dev status 2>/dev/null; ip -br addr
  echo; echo "=== pmic / display messages ==="
  dmesg 2>/dev/null | grep -Ei 'rk8xx|rk806|pmic|edp|panel|backlight' | tail -30
  echo; echo "=== firmware load warnings ==="
  dmesg 2>/dev/null | grep -Ei 'firmware|regulatory' | tail -15
  echo; echo "=== watchdog / kexec availability ==="
  ls -l /dev/watchdog* 2>/dev/null || echo "no /dev/watchdog"
  ls -l /sys/kernel/kexec_crash_loaded 2>/dev/null || echo "no kexec_crash sysfs node"
} > "$OUT" 2>&1

echo "wrote $OUT"
echo "keep this file: it is your baseline for 'what changed' after the upgrade."
