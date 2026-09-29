# USB Ethernet Gadget -> SSH: the strongest cable-only channel

Present the phone as a USB **network card**, DHCP the target an address inside the range
its `sshd` allows, then SSH in. This gives a fully interactive shell — far better than
blind keyboard work — and it needs only the charging cable you already have.

Verified end to end on a CM5 laptop with `AllowUsers <user>@100.64.0.0/10` (Tailscale
range), reached over the cable with an address inside that range: no policy change was
made on the target at all.

## 1. Build the gadget (HID optional, Ethernet essential)

configfs, `functions/`:

- `ecm.usb0` — ECM. Host side: `cdc_ether`. Set `dev_addr` (our MAC, e.g.
  `02:00:00:00:00:01`) and `host_addr` (the target's side, e.g. `02:00:00:00:00:02`).
- `rndis.usb0` — RNDIS. Host side: `rndis_host`. Add both if you do not know which the
  target's kernel has; whichever it supports becomes its netdev. (On some Android
  kernels `rndis` is unavailable and the mkdir fails — proceed with ECM.)
- Keep `hid.usb0` if you also want the keyboard fallback; keep `acm.usb0` only if you
  want a serial port.

Order matters: create the **function instances first**, then build a **fresh config item
`configs/b.1`**, then link (`cd $G && ln -s functions/ecm.usb0 configs/b.1/f3`). Linking
into a stale config fails `EINVAL`. If the vendor USB stack keeps tearing your tree down
mid-build (`EBUSY`, `ENOENT`, attributes vanishing), **build a brand-new gadget** with a
new name (`g3`, `g4`) rather than repairing the damaged one.

Then: `echo device > /sys/class/usb_role/<ctrl>-role-switch/role`, `echo <udc> > $G/UDC`.

## 2. Bring up our end

```sh
ip addr add 100.64.0.1/24 dev usb0     # ANY address; inside the target's allow-list if it has one
ip link set usb0 up
cat /sys/class/net/usb0/carrier        # 1 = the target is connected
ip -s link show usb0                   # RX rising = the target is transmitting
```

## 3. DHCP the target

Termux has **no dnsmasq**; a ~60-line Python UDP server on port 67 is enough (OFFER on
DISCOVER, ACK on REQUEST, options 1/3/6/28/51/54). Notes that cost time:

- Bind with `SO_BINDTODEVICE` (needs root) and reply to broadcast.
- Packet layout: `ciaddr + yiaddr + siaddr + giaddr` are four addresses — writing a
  stray `\x00` into that field raises `ValueError: embedded null character`.
- The target's request **is your proof**: a DISCOVER from the target's `host_addr` MAC
  means NetworkManager auto-connected. Log every message with the client MAC.
- NetworkManager auto-connects new wired devices by default; no profile is needed.

## 4. Reach it

```sh
ssh -i <key> -b 100.64.0.1 <user>@100.64.0.2      # -b pins the source address
```

The source address is what an `AllowUsers user@CIDR` entry is checked against, so
choosing an address inside that CIDR turns a hard restriction into a non-issue — the
target's configuration is not weakened or modified in any way.

## 5. The two traps after the link is up

- **The phone's VPN steals the route.** `ip route get <target>` may show `dev tun0`
  (Clash/VPN policy routing). Then every TCP connection is terminated by the proxy: SSH
  reports `Connection reset by peer` and the banner never arrives, while ping and DHCP
  work. Fix: `ip rule add to <target>/32 lookup main priority 200` (a lower number than
  the VPN's rules) and re-check `ip route get`.
- **Re-enumeration resets our end.** After the target reboots, our `usb0` address and
  the policy rule can vanish: re-add both, restart the DHCP server, and it re-leases on
  its own (the DHCP log shows a fresh DISCOVER at reboot time — a useful boot detector).
  Android's `netd` also **flushes the interface address spontaneously** (any link event
  will do it), so `Cannot assign requested address` from ssh usually means just that:
  re-add the address, re-check `ip -br addr show usb0`, and retry before concluding the
  channel is broken. Keep a small restore script for this, since it happens often.

## 6. What to check first once you have the shell

For a machine that boots but shows nothing, in this order:

1. `tr -d '\0' < /proc/device-tree/model` — is this the board you think it is?
2. `ls /sys/class/drm/` and each `card*-*/status` — is there a connector for the panel?
   No `card*-eDP-1`/`card*-DSI-1` at all = the wrong device tree or no panel node.
3. `cat /sys/class/backlight/*/bl_power` — `4` is FB_BLANK_POWERDOWN (no glow, ever).
4. `cat /proc/cmdline`, the boot config, and the mtimes under `/boot`.
5. `systemctl is-active gdm`, `loginctl list-sessions` — is a GUI actually running?

A wrong `.dtb` explains a dark panel **and** dead WiFi **and** odd sensors in one shot;
the user's story ("I changed the refresh rate") may be pure coincidence, so date the real
regression from the filesystem, not from the narrative.

## 7. After you have fixed the original fault: restore networking, do not break it

Your access link is a *change* to the target's network world. Respect two rules or you
will leave the machine worse than you found it:

- **Your DHCP reply must not offer a router or a DNS server.** If it does, the target
  installs a default route through your phone (metric 100, beating Wi-Fi's 600) and
  resolves names against a phone with no upstream — the user sees "the Wi-Fi is broken"
  while the Wi-Fi is perfectly associated. Omit options 3 and 6 entirely.
- **Tell the target's NetworkManager that the link is access-only:**
  `nmcli device modify <iface> ipv4.never-default yes ipv6.never-default yes ipv4.route-metric 5000 ipv4.ignore-auto-dns yes`
  then `nmcli device reapply <iface>`, and delete any default route it already installed
  (`ip route del default via <our-ip> dev <iface>`). Avoid `connection down/up` for this:
  it drops the interface and with it your own SSH session; reapply + route deletion keeps
  access while fixing the routing.
- **Never sweep every saved Wi-Fi profile.** A loop over all wireless connections tries
  neighbours' networks and hangs for 90 s on profiles needing a password; on a machine
  with a live shot at your sshd this wedged it (accept-then-close, no banner). Filter to
  the exact SSID/name you mean, verify by "the interface has an IPv4 address", and if
  sshd does wedge, only a reboot of the target clears it.

## 8. DNS hooks: the quiet way a machine loses all name resolution

A VPN daemon (Tailscale, or any resolvconf hook) can own `/etc/resolv.conf` long after it
stops working. Symptom: the machine has Wi-Fi, a router ARP entry and a correct default
route, yet **every lookup returns nothing** and service logins that reverse-resolve stall
(the well-known "sshd accepts, then times out during banner exchange").

- `tailscale status` showing *logged out / NoState / cannot reach the coordination
  server* while `/etc/resolv.conf` says `nameserver 100.100.100.100` is the signature.
- The file's mtime dates when the hook last wrote it — useful for correlating with the
  user's "it broke around X o'clock".
- Fix in escalating order:
  1. `tailscale set --accept-dns=false` (persistent preference), then **restart the
     daemon** — the setting only takes effect when it re-applies;
  2. if the file is still the VPN's, `systemctl stop tailscaled` (it restores the saved
     resolv.conf when it lets go);
  3. otherwise write a plain resolver (`nameserver <router>` + a public one such as
     `223.5.5.5`) and confirm with `getent hosts <name>` **and** a raw TCP test
     (`bash -c 'echo > /dev/tcp/223.5.5.5/443'`) so DNS and routing are checked separately.
- Once the internet is back, the VPN usually reconnects by itself if its node key is
  still valid — `tailscale up` may need no login at all, and the tailnet returns with its
  own address intact.
