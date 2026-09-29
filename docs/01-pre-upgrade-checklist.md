# 01 — Pre-upgrade checklist

Do these **before** the first `apt` command. On a vendor ARM image, most upgrade
pain is decided here.

## 1. Understand your boot chain (5 minutes, saves hours)

```sh
cat /proc/device-tree/model; echo
cat /proc/cmdline
ls -l /boot/firmware/ | head -30
cat /boot/firmware/extlinux/extlinux.conf
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
```

Questions to answer:

- Is the kernel a **vendor** `Image` in `/boot/firmware`, or a Debian
  `/boot/vmlinuz-*`? (Vendor: the upgrade will move userspace only.)
- Does boot use `extlinux.conf`, GRUB, U-Boot distro boot, or EFI?
- Is u-boot stored **separately in SPI-NOR**? If yes, treat it as precious:
  a Debian `u-boot-*` package must never overwrite it. Add the package to holds
  if the image ships one (`apt-mark hold u-boot-* flash-kernel` on vendor images).

## 2. Record the current state

```sh
sudo scripts/preflight-inventory.sh      # writes ./preflight-<date>.txt
```

It captures: OS/kernel/DTB, boot config, display-manager config, effective sshd
policy, held packages, PMIC/display kernel messages, network state, disk usage.

Keep that file. After an upgrade it is your "what changed" baseline.

## 3. Back up

```sh
sudo tar czf /root/etc-backup-$(date +%F).tgz /etc
sudo tar czf /root/bootfw-backup-$(date +%F).tgz /boot/firmware
dpkg --get-selections > /root/dpkg-selections-$(date +%F).txt
apt-mark showhold > /root/held-$(date +%F).txt
apt list --installed > /root/installed-$(date +%F).txt
```

If the machine has spare storage (e.g. an NVMe drive), also copy the root
filesystem there:

```sh
sudo rsync -aHAX --numeric-ids / /mnt/backup-rootfs/
```

Nothing here can restore SPI-NOR u-boot — for that, see
[`05-recovery-maskrom.md`](05-recovery-maskrom.md) and prepare the tooling.

## 4. Verify recovery is possible

Before you upgrade, confirm **both**:

1. You can reach the console (screen + keyboard) even if networking is dead.
2. You can enter **Maskrom mode** (usually: hold the Loader/Recovery key while
   powering on) and drive it from another machine.

Test the second one once. A board you can Maskrom is a board you cannot brick.

## 5. Power and space

- Run on **mains power**; a dist-upgrade over two releases takes a long time.
- Keep ≥10 GB free on `/`.
- Expect a long shutdown and (on some boards) a reboot that needs a power key.
  **Test a normal reboot now**, so you can tell later whether a failing reboot
  is new or pre-existing.

## 6. Decide about held packages

Vendor images commonly hold firmware and vendor libraries:

```sh
apt-mark showhold
```

- **Keep holds** on kernel/vendor packages that came with the image.
- **Consider releasing** holds on firmware packages; holding them can block
  security updates. Do it deliberately and note it.

## 7. Note the two configs that bite after the upgrade

```sh
cat /etc/gdm3/daemon.conf      # display manager (WaylandEnable matters on Debian 13)
sudo sshd -T | grep -Ei 'allowusers|denyusers|permitrootlogin|passwordauthentication'
```

- If the image was built for Debian 11, gdm is probably configured
  `WaylandEnable=false`. Debian 13's GNOME ships **only Wayland sessions**, so
  that setting breaks the login screen after the upgrade
  (see [`03-post-upgrade-fixes.md`](03-post-upgrade-fixes.md)).
- Note your SSH policy, especially `AllowUsers` restrictions. An upgrade can
  leave you locked out of a remote-only box — do the upgrade where you can reach
  the console.

## 8. Run the upgrade where a dropped connection can't kill it

Use the local console, or `tmux`/`screen` over SSH. If your session dies
mid-`apt`, you are left with a half-configured system.
