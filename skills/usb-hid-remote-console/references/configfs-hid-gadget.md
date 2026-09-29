# USB HID Keyboard Gadget from Android (configfs)

Goal: the phone appears to a USB-host target as a **boot-protocol keyboard**, so keystrokes can be typed into the target's console with no keyboard attached.

## Preconditions

- Kernel has the function built in: `zcat /proc/config.gz | grep USB_CONFIGFS_F_HID` → `CONFIG_USB_CONFIGFS_F_HID=y`.
- `CONFIG_USB_RAW_GADGET` is usually **not** set on Android kernels — check before planning a userspace gadget; if unset, configfs is the only route.
- Gadget configfs is mounted at `/config` (Android): `/config/usb_gadget/g1/`.
- The function instance often already exists: `functions/hid.gs0`, created by the vendor `init.<soc>.usb.rc` (`mkdir /config/usb_gadget/g1/functions/hid.gs0`). A vendor ROM rarely wires up a property path for it — `setprop sys.usb.config hid` does nothing on MediaTek (no matching init action), so do not rely on the ROM's property machinery.

## Recipe

1. **Configure the function before linking it** (all values are configfs attributes under `functions/hid.gs0/`):
   - `protocol` = `1` (keyboard), `subclass` = `1` (boot interface), `report_length` = `8`.
   - `report_desc` = the standard 63-byte boot keyboard descriptor (binary write, not text):
     ```python
     bytes([0x05,0x01,0x09,0x06,0xA1,0x01,0x05,0x07,0x19,0xE0,0x29,0xE7,0x15,0x00,0x25,0x01,
            0x75,0x01,0x95,0x08,0x81,0x02,0x95,0x01,0x75,0x08,0x81,0x03,0x95,0x05,0x75,0x01,
            0x05,0x08,0x19,0x01,0x29,0x05,0x91,0x02,0x95,0x01,0x75,0x03,0x91,0x03,0x95,0x06,
            0x75,0x08,0x15,0x00,0x25,0x65,0x05,0x07,0x19,0x00,0x29,0x65,0x81,0x00,0xC0])
     ```
2. **Link it into the config** with configfs's canonical form, because the kernel resolves a symlink target against the **caller's cwd**:
   ```sh
   cd /config/usb_gadget/g1 && ln -s functions/hid.gs0 configs/b.1/f2
   ```
   Absolute targets from an unrelated cwd, and Python's `os.symlink` without chdir, fail.
3. **Bind in device role**: `echo device > /sys/class/usb_role/<ctrl>-role-switch/role`, then `echo <udc> > /config/usb_gadget/g1/UDC`.
4. **Confirm from both ends**: `cat /sys/class/udc/*/state` == `configured` (a host enumerated you), `ls -l /dev/hidg0` exists (root, `crw-------`), and the kernel log shows the HID interrupt endpoints: `mtu3 ... mtu3_ep_enable ep1in maxp:8 interval:4`.

## The EINVAL trap (the thing that costs an hour)

Symlinking a HID function into an **already-bound / stale config item** fails with `EINVAL`, and so does linking a freshly created instance (`hid.usb0`, `mass_storage.usb1`, `acm.acm1`). The check that rejects it lives in `config_usb_cfg_link()`: the instance must appear in the gadget's `available_func` list.

The fix that works is to **rebuild the config item from scratch** while the UDC is unbound:

```sh
G=/config/usb_gadget/g1
echo '' > $G/UDC                                   # unbind
rm -f $G/configs/b.1/f1 $G/os_desc/b.1             # unlink functions + os_desc
rmdir $G/configs/b.1/strings/0x409 $G/configs/b.1/strings $G/configs/b.1
mkdir $G/configs/b.1 && mkdir $G/configs/b.1/strings/0x409
echo 500  > $G/configs/b.1/MaxPower
echo 0xc0 > $G/configs/b.1/bmAttributes
cd $G && ln -s functions/hid.gs0 configs/b.1/f1    # now succeeds
```

Verified behaviour: the identical link command failed `EINVAL` seconds before the rebuild and succeeded immediately after. Notes: only one configuration is permitted (`mkdir configs/c.1` → `EBUSY`), and the phone's normal gadget (ADB/MTP) is gone while your HID config is bound — restore it afterwards with `setprop sys.usb.config adb,mtp`, which does work.

## Typing

Write 8-byte reports to `/dev/hidg0` and always follow each with an all-zero release:

- Report layout: `[modifier, 0, key1, key2, key3, key4, key5, key6]`.
- Modifiers: ctrl `0x01`, shift `0x02`, alt `0x04`, gui/super `0x08`.
- Common usages: `a`..`z` = `0x04..0x1D`, `1`..`9` = `0x1E..0x26`, `0` = `0x27`, Enter `0x28`, Esc `0x29`, Backspace `0x2A`, Tab `0x2B`, Space `0x2C`, `-` `0x2D`, `=` `0x2E`, `/` `0x38`, `;` `0x33`, `'` `0x34`; shift is needed for `_ : | " ( ) $ >` etc.; F1..F12 start at `0x3A`.
- Timing: ~20 ms hold, ~40 ms release, ~50 ms between characters. Use a mapping table and refuse to type an unmapped character loudly — a silently skipped character corrupts a blind-typed command.
- Useful combos: Ctrl+Alt+F3 switches the target to a text console (the reliable place to log in, independent of a broken/black GUI), Ctrl+Alt+F1 returns to the GUI VT, Ctrl+Alt+T opens a terminal **only if a graphical session is already logged in**.
