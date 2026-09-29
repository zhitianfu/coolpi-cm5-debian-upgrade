# 05 — Recovery: unbricking over USB Maskrom (no x86 PC required)

Every Rockchip board can be recovered over USB in **Maskrom mode** — the SoC's
ROM bootloader listens on USB even with no bootable storage. This is the safety
net that makes boot-chain experiments survivable, and it works from any Linux
host, including a rooted Android phone in Termux.

> Practise this **before** you need it. A recovery path you have never executed
> is a plan, not a capability.

## 1. Enter Maskrom

1. Connect the board's flashing USB-C port to the host.
2. Hold the **Loader/Recovery** key (on many CM5 carriers it is on the bottom,
   under the cover) and apply power, or hold it while pressing reset.
3. On the host:

```sh
lsusb -d 2207:350b && echo "Maskrom OK"
```

`2207` is Rockchip's vendor ID; `350b` is the loader PID for RK3588. If nothing
appears, the board is not in Maskrom (usually: wrong port, key not held, or the
board is unpowered — an unpowered USB-C target presents nothing at all, which is
itself a useful diagnostic).

## 2. Get the tools and the loader blobs

Tools (both build from source on ARM64 — no x86 machine needed):

```sh
# rkdeveloptool
git clone https://github.com/rockchip-linux/rkdeveloptool
cd rkdeveloptool && autoreconf -i && ./configure
make -j4 CXXFLAGS="-g -O2 -Wno-vla-cxx-extension"   # upstream compiles C++ VLAs under -Werror
sudo make install

# xrock (libusb only, alternative implementation)
git clone --depth 1 https://github.com/xboot/xrock && cd xrock && make
```

Blobs (from Rockchip's `rkbin`, or the vendor's own `MiniLoaderAll.bin`):

- `rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.24.bin` — the DDR init
- `rk3588_usbplug_v1.11.bin` — the USB plug-in loader

Download them to a working directory. Note that `rkdeveloptool pack` is not wired
into the upstream `main()`, so building a `MiniLoaderAll.bin` yourself may fail;
use the vendor blob, or xrock's two-blob flow.

## 3. Inspect before you write

```sh
sudo rkdeveloptool ld                  # list Maskrom/Loader devices
sudo rkdeveloptool rci                 # chip info
sudo rkdeveloptool rfi                 # flash info
```

**Back up the existing flash first**, always:

```sh
sudo rkdeveloptool rl 0 0x8000 spinor-backup.bin     # e.g. read the first 32 KiB of SPI-NOR
```

## 4. Write the bootloader

With `rkdeveloptool`:

```sh
sudo rkdeveloptool db  rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.24.bin
sudo rkdeveloptool wl  0  u-boot-rockchip-spi.bin      # SPI-NOR at offset 0
sudo rkdeveloptool rd                                  # reset
```

With `xrock`:

```sh
sudo xrock maskrom rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.24.bin rk3588_usbplug_v1.11.bin --rc4-off
sudo xrock flash write 0 u-boot-rockchip-spi.bin
sudo xrock reset
```

Use the vendor's own **`MiniLoaderAll.bin`** if you have it — for a specific
carrier board it is the safest loader. For eMMC targets write `u-boot-rockchip.bin`
to sector 64 (`wl 64 u-boot-rockchip.bin`); for SPI-NOR write
`u-boot-rockchip-spi.bin` at offset 0.

## 5. Notes for building U-Boot for this board

```sh
make coolpi-cm5-genbook-rk3588_defconfig      # board-specific defconfig (name varies by vendor tree)
make CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)"
```

Produces `u-boot-rockchip.bin` (eMMC, sector 64) and
`u-boot-rockchip-spi.bin` (SPI-NOR, offset 0). Some vendors keep **two SPL
copies** in SPI-NOR (e.g. at 0x10000 and 0x60000) — check the vendor's
documentation before writing only one.

## 6. If the update breaks the board again

Keep the vendor bootloader files you were running (plus your flash backup) in
version control or on the NVMe. Recovery is only fast when the *previous* known
good loader is one command away.
