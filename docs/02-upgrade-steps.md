# 02 — Upgrade procedure (bullseye → bookworm → trixie)

Debian supports upgrading **one release at a time**. Skipping a release
(bullseye → trixie directly) is not supported and is the most common way people
break a vendor image. Budget a couple of hours per hop on ARM/eMMC.

Do the whole thing with the console in front of you, or inside `tmux`.

## Step 0 — Sanity baseline

```sh
lsb_release -a
uname -r
systemctl --failed
df -h /
```

Fix anything already failing before you start (especially `systemctl --failed`):
you want a clean starting point so the upgrade's damage is distinguishable.

## Step 1 — Hop one: bullseye → bookworm

Edit `/etc/apt/sources.list` (and `/etc/apt/sources.list.d/*`) replacing
`bullseye` with `bookworm`. Use a mirror you can actually reach; on ARM keep the
`[arch=arm64]` qualifiers if the image used them.

```sh
sudo cp -a /etc/apt/sources.list /root/sources.list.bak
sudo sed -i 's/\bbullseye\b/bookworm/g' /etc/apt/sources.list
grep -rn "bullseye\|bookworm" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null

sudo apt update
apt-get -s full-upgrade | tail -40          # DRY RUN — read it
sudo apt full-upgrade
```

Read the dry run for:

- packages that will be **removed** (a removal list of hundreds means a source
  or architecture problem — stop and fix it),
- "held back" packages (usually the held firmware/vendor set — expected,
  see checklist §6),
- whether a Debian kernel is being installed (it may change your boot config).

During the upgrade you will get **config file prompts**. For files the vendor
customised (kernel cmdline, dnsmasq/network config, display manager config)
choose *keep the currently-installed version* first; you can diff them later:

```sh
sudo apt install --reinstall -o Dpkg::Options::=--force-confnew <package>   # only if you decide to take the new file
dpkg-divert --list | grep -i local        # see files the vendor diverted
```

Finish cleanly, then reboot and confirm you still boot and log in:

```sh
sudo apt --fix-broken install
sudo dpkg --configure -a
systemctl --failed
sudo reboot
```

**If the login screen is broken after this hop, fix it now** (that is the gdm
trap in [`03-post-upgrade-fixes.md`](03-post-upgrade-fixes.md)) before hopping
again — otherwise you will be debugging two overlapping failures later.

## Step 2 — Hop two: bookworm → trixie

```sh
sudo cp -a /etc/apt/sources.list /root/sources.list.bookworm.bak
sudo sed -i 's/\bbookworm\b/trixie/g' /etc/apt/sources.list
grep -rn "bookworm\|trixie" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null

sudo apt update
apt-get -s full-upgrade | tail -40
sudo apt full-upgrade
```

Same rules as hop one. Trixie changes that matter on a vendor image:

- **GNOME / display manager**: Wayland-only sessions (see doc 03).
- **NetworkManager** and firmware package renames/additions; keep an eye on
  `nmcli dev status` after the reboot.
- `usrmerge`-era layout assumptions: most vendor images are already merged, but
  read any `usrmerge`/`usr-is-merged` warnings instead of ignoring them.

## Step 3 — Reboot and verify

```sh
lsb_release -a; uname -r
systemctl --failed
scripts/verify-upgrade.sh
```

Check that **`uname -r` is still your vendor kernel** and that
`/boot/firmware/{Image,initrd.img,*dtb,extlinux/extlinux.conf}` still reference
your board's DTB. If a Debian kernel got installed and your board boots the
vendor `Image` from `extlinux.conf`, make sure nothing rewrote that file —
`/boot/firmware/extlinux/extlinux.conf` should still have exactly one `default`
label that exists in the file (a vendor update once pointed `default` at a label
that did not exist, and the board silently booted a different board's DTB).

## Step 4 — Clean up

```sh
sudo apt --purge autoremove
sudo apt clean
sudo apt --fix-broken install; sudo dpkg --configure -a
systemctl --failed
```

Remove stale release-specific sources you no longer need, and re-check your
`apt-mark showhold` list: a hold that made sense on bullseye may silently block
a security update on trixie.

## Rollback

There is no automated rollback for a release upgrade; that is what the backups in
[`01-pre-upgrade-checklist.md`](01-pre-upgrade-checklist.md) §3 are for. In order
of preference: restore `/etc` + `/boot/firmware` from the tarballs, restore the
rootfs from the rsync copy, or restore the whole system image from your own
backup. If the board no longer boots at all, use
[`05-recovery-maskrom.md`](05-recovery-maskrom.md).
