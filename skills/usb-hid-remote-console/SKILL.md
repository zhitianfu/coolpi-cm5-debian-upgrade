---
name: usb-hid-remote-console
description: Use when a host has no console, keyboard, or network path.
---

# Remote Console: Phone-as-USB-HID + Beacon Output

Administer a machine you cannot reach any other way. An Android phone (Termux + root) presents itself to the target as a **USB boot-protocol keyboard**, so you can type into the target's console; the target's only output channel is an **HTTP request back to the phone**, whose arrival (and URL) carries your data.

## When to Use

- Target throws away every network path: sshd is key-only and restricted (e.g. an `AllowUsers` VPN range), no other ports open, LAN scan finds nothing.
- Target boots but is unusable/unreachable, and needs repair, patching, or diagnostics.
- You have a physical USB cable between phone and target, with the target acting as USB host.

## Conduct during a rescue

These override convenience, and they were learned live:

- **Never ask the user to perform a step, press a button, or confirm one.** Exhaust the
  autonomous routes first (LAN, USB Ethernet, HID keyboard). When something is genuinely
  impossible from the phone — a hung or powered-off SoC needs its physical power button —
  state it once as a hardware fact and stop. Never present an unreachable state as progress,
  and never fabricate what you could not observe.
- **Read-only diagnostics first; change things only with evidence.** Back up every file you
  edit (`cp -a file file.bak.<tag>`), keep edits minimal and reversible, and report the
  backup path.
- **Reproduce the reported failure on purpose before claiming a fix**, then judge from the
  machine's own journal. "It looks fine" is not evidence.
- **Do not weaken the target's security to gain access** — see rule 1.
- **Report deliverables against the machine's own logs** (unit active, session opened for a
  real user, service listening), not against what you intended.
- **Clean up when finished**: delete temp credential files, revert any sshd drop-in you
  added, restore the phone's normal USB gadget (`sys.usb.config adb,mtp` + vendor vid/pid),
  and tell the user exactly which keys remain in the target's `authorized_keys`.

## Order of Work

> **Try the ETHERNET channel first.** Before any blind typing, present the phone as a
> USB **Ethernet** gadget (ECM/RNDIS). The target's NetworkManager auto-connects a new
> wired device, so you can DHCP it an address **inside whatever range its sshd allows**
> and reach it with an interactive SSH shell — no typing, no greeter, full diagnostics.
> Recipe and pitfalls: `references/usb-ethernet-ssh-channel.md`. The HID keyboard below
> is the fallback for targets with no sshd, no key, or no session. This ordering was
> learned the hard way: an hour of blind keystrokes found nothing that one SSH session
> settled in two commands.

### 1. Prove what is reachable before diagnosing anything

A report of "it failed to reboot / black screen / nothing at all" is usually "it boots but has no network", not a dead boot chain. Gather evidence first:

- Sweep the subnet for port 22 (`concurrent.futures` + `socket.connect` beats nmap, which is usually absent on Termux).
- Read the SSH banner: `SSH-2.0-OpenSSH_10.0p2 Debian-7+deb13u4` names the exact distro release — proof the machine booted and is alive.
- Test a full handshake, not just TCP: `ssh -o PreferredAuthentications=none -o BatchMode=yes -o NumberOfPasswordPrompts=0 <user>@<host> true` → the parenthesised list (`Permission denied (publickey)`) is the server's **offered auth methods**. No `password` in that list means no credential path exists over SSH, only a key.
- ARP gives MACs; the same MAC on two IPs is one host with two leases.

Never conclude "dead hardware" while a service still answers. Never guess the fault from the user's description alone.

### 2. Reconnaissance while the easy channel still exists

Use the brief window where SSH answers (before you touch anything) to learn the target's policy:

- `sshd -T` on the target prints the **effective** config. Grepping `sshd_config` is misleading — commented defaults count as matches.
- Decisive checks: `permitrootlogin`, `allowusers`, `strictmodes`, `authorizedkeysfile`, `pubkeyauthentication`.
- An `AllowUsers` entry like `<user>@100.64.0.0/10` means SSH is deliberately VPN-only (Tailscale uses 100.64/10). That is not a bug to "fix".

### 3. Build the keyboard path

See `references/configfs-hid-gadget.md` for the full configfs recipe. Headline: the HID function usually already exists as `hid.gs0`, and the failure mode when linking it is a **stale config item**, not a missing driver.

### 4. Stage payloads on the phone; type short commands only

- Serve payloads from the phone over HTTP and type one short fetch-and-run line: `wget -qO /tmp/r <phone-ip>/r;sh /tmp/r`. This keeps blind keystrokes to ~40 characters instead of hundreds, where a single unmapped/typo'd character is unrecoverable.
- Keep the phone's HTTP drop small and purpose-named per step; verify each file is fetchable (`curl -o /dev/null -w '%{http_code}'`) before typing the command that uses it.
- Long-command typing is for one-off queries only, and even then encode results in the URL (step 5).

### 5. Get output back through the beacon channel

See `references/beacon-output-channel.md`. Headline: the target fetches `http://<phone>/<tag>-<encoded>`, the phone's HTTP server log records the request, and that log line **is** your stdout.

### 6. Repair least-invasively, then verify with the user's own criterion

The user's test defines done. "Fix the reboot" means: actually reboot the machine and confirm it returns on its own. Do not substitute a proxy (a service restart, a reachable port) for that test, and do not report success before it passes.

## Always-On Rules and Pitfalls

1. **Do not weaken the target's auth policy as a first move.** Adding your source IP to `AllowUsers`, flipping `PermitRootLogin`, or disabling `StrictModes` is a security change to someone's machine. A root shell on the local console reaches everything; prefer it. If you must change policy, disclose it plainly and offer to revert.
2. **Re-verify the USB link immediately before every keystroke batch.** The gadget drops to `not attached` silently (host reset, suspend, re-enumeration) and typed characters vanish with no error anywhere. Check `cat /sys/class/udc/*/state` == `configured` each time; restore with `echo '' > $G/UDC`, set the role, then `echo <udc> > $G/UDC`.
3. **Send Ctrl+C before each new typed command.** A foreground command that hangs on the target (a `wget` to an unreachable host, a `dpkg` debconf prompt) swallows every later keystroke; the shell looks dead but is merely busy. Ctrl+C is modifier `0x01` + usage `0x06`.
4. **Exfiltrate as hex, never base64 with a character-substitution map.** Base64's own alphabet contains `x`, `y`, and `z`, so any `+/=` → `xyz` mapping silently corrupts the stream. Use `od -An -v -tx1 <file> | tr -d ' \n'`, which is `[0-9a-f]` and therefore URL-safe with no mapping at all.
5. **Cap the chunk loop, then resume by offset.** A per-run chunk cap truncates the payload without any error; after reassembling, assert the joined length, and fetch the remainder with `cut -c<N>-` using a second index range rather than re-sending everything.
6. **Never `pkill -f <pattern>` from Termux.** The wrapper shell's own command line contains the pattern, so you SIGTERM yourself and the tool reports a bare signal death. Kill by explicit PID, or scan `/proc/*/cmdline` in Python while excluding `os.getpid()` and its ancestors.
7. **Do not hammer SSH auth.** Probing many usernames on a short interval trips `fail2ban` on the target. The signature is a reset during the handshake while a plain TCP connect still succeeds. Stop probing, wait for the ban window, then use single attempts.
8. **Prefer the evidence the target prints itself.** Have the target encode its own state into the beacon (counts, hashes, `systemctl is-active`) instead of inferring from the phone side. A hash comparison settles "is my key installed correctly" in one round trip.
9. **Android denies hardware access to the Termux uid.** `/sys/bus/usb/devices`, netlink (`ip`, `ip neigh`), `lsusb`, and `/dev` enumeration fail with permission errors under the app user. Run them through `su -c '...'`. Note `su` has no Termux `PATH` (use absolute binary paths) and root's `$HOME` differs, so `~` expansion points somewhere unexpected — hardcode absolute paths in scripts that run as root.
10. **Credentials the user volunteers stay out of everything durable.** Keep them in a mode-600 file and reference the file (`... typestdin < file`), never echo them, never put them in persistent memory, and delete the file when the work is done. Say so explicitly so the user can verify.
11. **A warm reboot can hang while a cold power-on works.** On some SBC/laptop boards the warm reset never re-enters the boot chain (no console, no USB, no network). Reproduce the user's reboot complaint deliberately, and if the board stays dark, say plainly that only a physical power press can revive it — then state that rather than claiming progress.
12. **Never pass typed text through `su -c "<py> typer.py type 'the text'"`.** The text is re-parsed by Android's `/system/bin/sh`: inner quotes terminate early, so the tail of your command is EXECUTED LOCALLY (as root, on the phone) and the typer receives one mangled word. Symptom seen live: `/system/bin/sh: can't create /sys/class/backlight/*/brightness`. A command containing a space, quote or `;` becomes garbage on the target (a 4-command sequence was silently truncated to `wget`, `sh`, `sudo`). Fix: drive the typer from a **JSON plan** (`scripts/hid_drive.py`) that loads the typer module by path, so no shell ever sees the text. Validate every planned line against the key map before sending it (a dict lookup over `M`), and report unmapped characters rather than skipping them.
13. **A completed write to `/dev/hidg*` is the liveness proof; a blocked write means the host is suspended.** Writes on the interrupt IN endpoint complete only when the host polls it. Send one all-zero report ("no keys", therefore harmless) before every typing burst: a 1 ms/endpoint completes instantly, while an autosuspended bus blocks forever. Corollary: **a HID gadget cannot remote-wake a suspended host** — f_hid never issues `usb_gadget_wakeup()`, so after `mtu3 ... gadget SUSPEND` your keystrokes queue and vanish. Force re-enumeration (unbind/rebind the gadget) or have the user touch the machine, then re-poke.
14. **A host that autosuspends your device is running an OS, not a bootloader.** `gadget SUSPEND` a few minutes after enumeration is OS-level USB power management (Linux/Windows); u-boot never does it. Use it as evidence before concluding "the board is dead": the machine may simply have a dark panel and no network.
15. **A checked-out host is worth nothing if the phone's own network path is fake.** A transparent proxy / fake-IP DNS on the Android side (e.g. Clash in VPN mode) answers DNS for *any* name and accepts then drops TCP, so ping and "port open" tests succeed against a control address too. Before concluding a machine is reachable, repeat the probe against a known-dead address; if both behave identically, the "live" result is the proxy.
16. **configfs `UDC`: unbind with ONE byte, and bind immediately.** A zero-byte write is a no-op (the file still shows the old UDC name), and on a vendor ROM the init action for `sys.usb.config` re-links and re-binds its own gadget within a second — so `unbind; sleep; bind-yours` fails `EBUSY`. Do `echo "" > g1/UDC` and the very next command `echo <udc> > g2/UDC`. Also `stop vendor.usb_gadget_default` first; a stopped HAL cannot re-link. Vendor attempts afterwards log `EBUSY` and leave your gadget alone — that is success, not failure to chase.
17. **Do not poke the host's USB state machine to prove your commands landed.** It works (deauthorising the phone's own device on the host produced a `gadget SUSPEND` → `RESET` pair, proving root commands executed) but on this MediaTek phone the repeated re-enumeration flipped the port to host role (`ssusb_host_register 1`) and **rebooted the phone**: uptime reset, gadget gone, helpers dead, and the human had to restart the agent. Prefer non-USB proofs: a payload with a persistent side effect (marker file, parked config you can re-check), or the user's eyes on the panel/backlight.
18. **Blind typing is only as good as the line length.** Long compound lines (300+ chars) were silently lost twice; short one-purpose lines (≤90 chars, one command each) landed every time. When a line must be long, verify it landed with a cheap side effect before building on it, and re-enter the login on a FRESH VT (`Ctrl+Alt+F4`/`F6`) when a VT stops responding: a `systemctl restart gdm` earlier in the session can take over the VT you were typing on, and a getty that has accumulated failed logins delays or ignores further input.
19. **Check the phone's USB ROLE before blaming the target.** On Android a port can silently flip to `host` (`cat /sys/class/usb_role/*/role` -> `host`), and a gadget cannot be seen by a host while the port is in host mode — every keystroke is discarded with no error on either side. Symptom: `udc state = not attached` even though the target is powered on and was enumerating you minutes earlier; `sys.usb.config` back to `adb`. Recovery: `stop vendor.usb_gadget_default`, `setprop sys.usb.config none`, rebuild the gadget, and verify `role = device` **and** `udc state = configured` before typing anything. Treat this as step zero of every retry: an hour was lost to typing into a dead port while the target was perfectly alive.
20. **The blocking poke is a synchronisation primitive, not just a liveness test.** A write to the interrupt IN endpoint completes only when the host polls it, so a poke that blocks means "the host is not listening"; a poke that returns means "the host is listening *now*". Use it to *time* keystrokes instead of guessing: wait on a poke (cap it generously, e.g. 180 s), then type immediately. During a boot, the first return marks the earliest moment the host owns the device — the only window where a console can accept a login. Rounds driven this way beat rounds driven by a fixed sleep, and a per-step alarm (1.5 s per report, 8 s per round) keeps a stalled write from freezing the whole campaign.
21. **A live kernel does not imply a reachable console: a Wayland greeter owns the keyboard and suppresses the console.** Proof the machine runs Linux (it polls us, its Caps Lock LED toggles from *our* keystrokes) can coexist with total inability to type a command: the compositor sets `K_OFF`/graphics mode, so the kernel's VT keyboard layer ignores the keys and everything lands in the greeter — whose user list/password field needs a *click* to focus. A correct password then does nothing at all. Blind typing cannot cross that boundary; only preventing the greeter from starting (boot args, or a `set-default multi-user` + `mask gdm` typed from a shell you already have) can.
22. **Verify the return path before trusting any marker, and prefer two independent ones.** The USB-serial link was repeatedly *assumed* to carry output, so "no marker" could not distinguish "no shell" from "one-way broken link". Before building a plan on a back-channel, prove it end to end, and add a second channel of a different kind (e.g. an HTTP beacon over the network, plus a marker to the serial port) so a silent channel cannot masquerade as failure.
23. **Typing at the bootloader: spam continuously, and never `saveenv`.** `setenv bootargs ${bootargs} ...` + `boot` typed in RAM is undone by a power cycle, so a failed boot costs nothing — as long as `saveenv` is never typed (put that in the script comment so it cannot be "helpfully" added later). Spam the interrupt key *before* and across the power-on, because a bootloader's autoboot delay is only a second or two and you cannot know when it starts; a repeated `setenv`+`boot` inside the spam covers the unknown prompt timing. But if the vendor u-boot has `bootdelay=0`, no USB keyboard driver, or starts USB after the delay, the interrupt is impossible — then only a serial console (UART) reaches the bootloader.
24. **A black screen with a live kernel: check the DEVICE TREE and the DRM connectors before touching display config.** Booted with the wrong `.dtb`, a board has no panel node at all — `/sys/class/drm/` shows no `card0-eDP-1`, the backlight reports `bl_power = 4` (powered down), and unrelated subsystems (WiFi wiring, sensors) misbehave too. Read `tr -d '\0' < /proc/device-tree/model` and compare it with the machine you are looking at; a vendor boot config with a `default <label>` naming a **label that does not exist** silently falls back to the FIRST entry, which is how a laptop ends up booting a single-board-computer device tree. Fix the default, not the refresh rate: a user-visible "I changed X and it broke" is often coincidence, and the real regression is dated in the file mtimes (`find /boot -newermt '2 days ago'`).
25. **On the phone side, a VPN can silently steal the cable route.** Clash/VPN policy routing sent `100.64.0.2` into `tun0`, so every TCP connection to the target was terminated by the proxy (SSH showed `Connection reset by peer` with no banner, while ICMP and DHCP passed — a convincing fake). Always `ip route get <target>` before trusting a failure, and add an explicit rule ahead of the VPN: `ip rule add to <target>/32 lookup main priority 200`. This is the same fake-aliveness trap as rule 15, now at layer 3.

## References

- `references/configfs-hid-gadget.md` — the whole configfs HID-keyboard recipe: descriptor bytes, the EINVAL/stale-config fix, report format, role/UDC handling.
- `scripts/hid_drive.py` — quoting-free JSON plan driver (steps: combo / type / enter / key / password / poke / sleep). Supersedes ad-hoc `su -c "... type '...'"` calls.
- `references/beacon-output-channel.md` — building the one-way output channel: HTTP drop on the phone, hex chunking, log parsing, encode/decode pitfalls.
- `references/coolpi-cm5-genbook.md` — device profile for a RK3588 laptop: boot chain, Maskrom entry, phone-side recovery tooling, and its known post-upgrade defects.
- `references/rockchip-and-debian-notes.md` — Maskrom tooling built on the phone, GenBook-class hardware, and the breakage patterns a Debian release upgrade leaves behind on a vendor image (display path first).
- `references/usb-ethernet-ssh-channel.md` — present the phone as USB Ethernet (ECM/RNDIS) and reach the target with a real SSH shell instead of blind typing.
- `references/unreachable-console-diagnosis.md` — triage order for a machine that is reported dead.
- `scripts/exfil_hex.sh` — target-side hex exfiltration script (chunk loop + END marker).
- `scripts/killpat.py` — kill by cmdline match while excluding self and ancestors (never `pkill -f`).
