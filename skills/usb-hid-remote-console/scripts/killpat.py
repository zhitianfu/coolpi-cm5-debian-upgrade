#!/usr/bin/env python3
"""Kill processes whose cmdline matches a substring, excluding self and all ancestors.

Why: `pkill -f <pattern>` matches your own shell (the command line contains the pattern)
and SIGTERMs it - as root it will happily kill your own tool session.

Usage: killpat.py <substring>
"""
import os, sys, signal, glob

pat = sys.argv[1] if len(sys.argv) > 1 else None
if not pat:
    sys.exit("usage: killpat.py <substring>")

mypid = os.getpid()
me = set()
p = mypid
while p and p > 1:
    me.add(p)
    try:
        with open(f"/proc/{p}/stat") as f:
            p = int(f.read().split(") ")[1].split()[1])
    except Exception:
        break

killed = []
for path in glob.glob("/proc/[0-9]*/cmdline"):
    pid = int(path.split("/")[2])
    if pid in me:
        continue
    try:
        cmd = open(path, "rb").read().replace(b"\0", b" ").decode(errors="replace")
    except Exception:
        continue          # non-root cannot read root processes' cmdline - run as root to catch those
    if pat in cmd:
        try:
            os.kill(pid, signal.SIGTERM)
            killed.append((pid, cmd.strip()[:60]))
        except Exception as e:
            print("  could not kill", pid, e)

print(f"killed {len(killed)} process(es) matching {pat!r}:")
for pid, cmd in killed:
    print("  ", pid, cmd)
