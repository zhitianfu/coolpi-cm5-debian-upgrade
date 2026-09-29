#!/bin/sh
# Read-only post-upgrade verification for a vendor ARM image.
# Usage: sh scripts/verify-upgrade.sh
set -u

echo "=== release / kernel ==="
(lsb_release -ds 2>/dev/null || grep -h PRETTY_NAME /etc/os-release)
uname -r

echo
echo "=== failed units ==="
systemctl --failed --no-pager

echo
echo "=== display manager ==="
printf 'gdm      : %s\n' "$(systemctl is-active gdm 2>/dev/null || echo n/a)"
pgrep -af 'gdm-session-worker' | head -2
loginctl list-sessions --no-legend 2>/dev/null | head -5

echo
echo "=== login evidence (current boot) ==="
journalctl -b --no-pager 2>/dev/null | grep -i 'session opened for user' | tail -3 \
  || echo "  (need root, or no logins recorded this boot)"

echo
echo "=== network ==="
printf 'NetworkManager: %s\n' "$(systemctl is-active NetworkManager 2>/dev/null || echo n/a)"
nmcli -t dev status 2>/dev/null | head -5
ip -br addr 2>/dev/null | head -5

echo
echo "=== boot files untouched? ==="
ls -l /boot/firmware/Image /boot/firmware/extlinux/extlinux.conf 2>/dev/null
awk '/^[[:space:]]*default/{print "extlinux default label:", $2}' \
    /boot/firmware/extlinux/extlinux.conf 2>/dev/null

echo
echo "=== disk ==="
df -h / | tail -1

echo
echo "Review: 'done' means Debian 13.x, vendor kernel unchanged, no unexplained failed"
echo "units, gdm active with a greeter, and a successful login in the journal."
