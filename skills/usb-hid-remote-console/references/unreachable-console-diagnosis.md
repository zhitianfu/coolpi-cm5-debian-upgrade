# Diagnosing "the machine is alive but I cannot get a shell"

A host can be running Linux, polling your USB keyboard, toggling its Caps Lock LED from
your keystrokes — and still be completely unreachable. Work down this list before
concluding anything about the hardware.

## 0. Is your own port alive? (do this first, every time)

- `cat /sys/class/usb_role/*/role` must be `device`, and `cat /sys/class/udc/*/state`
  must be `configured` (when the target is on). If the role is `host`, the target
  cannot see you at all and nothing you type exists. Rebuild the gadget, set the role,
  re-check before sending a single keystroke.

## 1. Does the target read your keyboard?

- `timeout 6 <typer> poke` → completing instantly means the host is polling you *now*.
- Ask the human to press Caps Lock on the **machine's own** keyboard: a toggling LED
  proves its kernel console layer is running. Then press Caps Lock from the phone: the
  *internal* keyboard's LED toggling proves **your** keystrokes were processed. Two LEDs
  on the target are a full-duplex liveness test with no software channel involved.

## 2. Why typing produces nothing anyway

| Situation | Signature | Consequence |
|---|---|---|
| Wayland greeter owns the seat | your keys work (LED toggles) but only the greeter reacts | console is in `K_OFF`; a blind password field needs a click; a correct password does nothing |
| Console phase, device not opened | poke blocks for tens of seconds; rounds stall | the poll only starts when something opens the keyboard — timing is everything |
| Host suspended the device | poke blocks forever | f_hid cannot remote-wake a suspended host; force re-enumeration or have the human touch the machine |
| Long compound lines | some lines vanish entirely | keep typed lines short; validate every character against the key map |
| PAM faillock | correct password rejected, repeatedly | repeated blind attempts keep refreshing the lock; a **reboot clears `/run/faillock`** |
| Caps Lock parity | usernames arrive upper-cased (`<USERNAME>`) | digits in a password are unaffected; usernames are not — check the LED state first |

## 3. What each fix route actually requires

- **Boot window (getty before the greeter):** needs the target's kernel to poll your device
  at that instant. Use the blocking-poke synchroniser; expect only a few seconds, and
  several attempts, because the greeter starts right after.
- **Bootloader (u-boot):** no compositor and u-boot polls USB keyboards, so this is the
  strongest software route — but only if `bootdelay > 0` and USB keyboard support is
  compiled in and started before the delay. RAM-only `setenv`, never `saveenv`.
- **Kernel args through the bootloader:** `systemd.unit=multi-user.target` plus
  `systemd.mask=gdm.service` boots normally to a text console (safer than `init=/bin/sh`,
  which needs a writable root and can miss `root=`).
- **Serial console (UART):** the only channel that works when the panel, the compositor
  and the network are all broken — and the only way to read bootloader output. Needs
  physical access (pins or header) and a 3.3 V USB-TTL adapter; expect `115200n8`.
- **Maskrom / recovery button:** last resort; needs the case open and a Loader key at
  power-on.

## 4. Report honestly

If a route's precondition cannot be met (no writable root, no poll during the window, no
UART adapter, case not to be opened), say so and name the physical requirement, rather
than repeating attempts that cannot succeed. Prefer the user's own criterion for "fixed"
(the panel lights, the machine returns on its own) over any proxy.
