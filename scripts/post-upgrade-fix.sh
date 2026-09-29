#!/bin/sh
# Post-upgrade fixes for Debian 13 (trixie) on a vendor ARM image.
# Idempotent: safe to re-run. Backs up before changing anything.
# Usage: sudo sh scripts/post-upgrade-fix.sh
set -u

if [ "$(id -u)" != "0" ]; then
  echo "run as root (sudo sh $0)" >&2
  exit 1
fi

GDM=/etc/gdm3/daemon.conf

echo "=== 1. display manager: gdm Wayland session ==="
if [ -f "$GDM" ]; then
  if grep -qE '^[[:space:]]*WaylandEnable[[:space:]]*=[[:space:]]*false' "$GDM"; then
    [ -f "$GDM.bak" ] || cp -a "$GDM" "$GDM.bak"
    sed -i -E 's|^([[:space:]]*WaylandEnable[[:space:]]*=[[:space:]]*false.*)|#\1   # Debian 13 GNOME is Wayland-only; no X11 fallback session exists|' "$GDM"
    echo "  WaylandEnable=false commented out (backup kept at $GDM.bak)"
  else
    echo "  no WaylandEnable=false found - nothing to change"
  fi

  if [ -d /usr/share/wayland-sessions ] && [ -n "$(ls -A /usr/share/wayland-sessions 2>/dev/null)" ]; then
    echo "  wayland sessions present: $(ls /usr/share/wayland-sessions | tr '\n' ' ')"
  else
    echo "  WARNING: no session files in /usr/share/wayland-sessions - install a desktop session"
  fi
  [ -d /usr/share/xsessions ] || echo "  note: no X11 sessions installed (expected on trixie)"

  systemctl reset-failed gdm 2>/dev/null
  if systemctl restart gdm 2>/dev/null; then
    echo "  gdm restarted"
  else
    echo "  gdm restart failed - check: journalctl -u gdm -b | tail -40"
  fi
else
  echo "  $GDM not present - skipping (different display manager?)"
fi

echo
echo "=== 2. plymouth (usually a downstream symptom of a gdm crash loop) ==="
systemctl reset-failed plymouth-quit plymouth-quit-wait 2>/dev/null || true
plymouth --quit 2>/dev/null || true
echo "  reset-failed applied"

echo
echo "=== 3. stale greeter sessions from earlier crash loops ==="
loginctl list-sessions --no-legend 2>/dev/null | head -10

echo
echo "=== verify ==="
printf 'gdm state : %s\n' "$(systemctl is-active gdm 2>/dev/null)"
pgrep -af 'gdm-session-worker' | head -3
echo "failed units:"
systemctl --failed --no-pager

echo
echo "expected after a successful fix: gdm 'active', a gdm-session-worker process,"
echo "and failed units reduced to only pre-existing vendor noise (e.g. dnsmasq)."
