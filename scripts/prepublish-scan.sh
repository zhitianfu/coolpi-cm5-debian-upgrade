#!/bin/sh
# Pre-publish scan for a repo like this one.
# Tier 1 (fails the scan): high-confidence secrets - must never be published.
# Tier 2 (reported only): identifiers such as IPs, MACs and home paths - review them
#         and make sure any hit is a documentation example or placeholder.
# Usage: sh scripts/prepublish-scan.sh [dir]     (default: current directory)
set -u

DIR="${1:-.}"
SELF='prepublish-scan.sh'
FAIL=0

hr() { echo "------------------------------------------------------------"; }

echo "TIER 1 - high-confidence secrets (publish only if this prints 'none')"
SECRETS='-----BEGIN [A-Z ]*PRIVATE KEY-----|ssh-rsa AAAA|ssh-ed25519 AAAA|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN CERTIFICATE'
if hits=$(grep -rInE "$SECRETS" "$DIR" --exclude="$SELF" --exclude-dir=.git 2>/dev/null); then
  printf '%s\n' "$hits"
  FAIL=1
else
  echo "  none"
fi
hr
echo "TIER 2 - identifiers to review (IPs, MACs, home paths, hostnames you recognise)"
IDS='([0-9]{1,3}\.){3}[0-9]{1,3}|([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}|/home/[a-z0-9_-]+|/data/data/com\.termux|ssid|hostname|serial'
if hits=$(grep -rInE "$IDS" "$DIR" --exclude="$SELF" --exclude-dir=.git 2>/dev/null); then
  printf '%s\n' "$hits" | head -40
  echo "  (review each hit; placeholders like <LAN-IP> or 192.0.2.10 are fine)"
else
  echo "  none"
fi
hr
if [ "$FAIL" = 0 ]; then
  echo "RESULT: no high-confidence secrets found. Now read every line of Tier 2 output."
else
  echo "RESULT: SECRETS FOUND - do not publish until removed."
fi
exit "$FAIL"
