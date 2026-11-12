# OnePlus 6T (fajita)

Experimental. Luma does not publish images for this phone. You build them
yourself. You need an unlocked bootloader and a phone you can erase. The
OxygenOS firmware partitions must be intact (OxygenOS 11 on both slots is the
tested base); a phone running another Linux install has them.

## What works

Tested on Luma Nightly 20261108.5 (`luma/1/aarch64/nightly`), kernel
7.1.0-rc1-sdm845-luma:

- Display, touch, GPU (Adreno 630: GNOME Shell, GTK4, and Android with the
  hardware graphics path).
- Wi-Fi (WCN3990), Bluetooth, battery and charging.
- Speaker, headphones and microphones are listed; speaker playback works.
- USB networking (ECM, phone at 172.16.42.1).
- OTA updates use the shared ARM ref `luma/1/aarch64/nightly`.

Not working or not tested yet: calls and SMS, mobile data, cameras,
fingerprint, the earpiece output outside calls (switching to it leaves
PipeWire stuck), SELinux enforcing.

## Never write these

The install writes only `boot_a`, `boot_b` and `userdata`. Never write
`modemst1`, `modemst2`, `fsg`, `fsc`, `persist`, `vbmeta_a`, `vbmeta_b`,
`modem_a`, `modem_b` or `dtbo_a`/`dtbo_b`. `modemst1` and `modemst2` hold
the phone's own modem settings, including its IMEI. Back up all of them
before you start (read-only `dd` from a running Linux system, for example
`dd if=/dev/disk/by-partlabel/modemst1 of=modemst1.img`).

## How it boots

The phone uses the generic phone userdata image
(`scripts/mobile/build-phone-userdata.sh`) with its own boot image. There is
no signed device kit for this phone, so its packages come from the userdata
image instead:

- The boot image (`scripts/mobile/build-fajita-boot-image.sh`) carries the
  kernel, the DTB and the postmarketOS initramfs named in `device.toml`, plus
  the Luma OSTree pieces. It boots ostree's default deployment, so one boot
  image keeps working after updates and `rpm-ostree install`.
- Until the device packages are layered, the initramfs takes firmware from
  `/var/lib/luma/device-firmware` and kernel modules from
  `/var/lib/luma/device-modules`. After layering, the deployment's own
  `/usr/lib/firmware` and `/usr/lib/modules` are used.
- The device packages: `kernel-modules-luma-fajita`, `luma-fajita-firmware`
  (in `/usr/lib/firmware`) and `luma-fajita-platform` (rmtfs and tqftpserv,
  `qbootctl -m` after `boot-complete.target`, the clock, the Bluetooth
  address, the OnePlus 6T ALSA UCM, Android's hardware graphics path). Without
  qbootctl the bootloader counts every boot as a failed try, marks the slot
  unbootable after 7 boots and switches slots.

## Build

On Fedora 44 aarch64 or in its container
(`FEDORA_RPM_BUILD_CONTAINER_AARCH64` in `config/desktop/inputs.env`), with
`clang lld llvm make bc flex bison elfutils-libelf-devel openssl-devel dwarves
python3 perl git-core rpm-build systemd-rpm-macros cpio zstd xz kmod ostree
android-tools`. `OUT` is a work directory.

1. Kernel: `scripts/kernel/build-fajita.sh OUT/kernel`.
2. Firmware: `scripts/packages/assemble-luma-fajita-firmware.py --cache OUT/cache --output OUT/fajita-firmware.tar`.
3. The OS: pull `luma/1/aarch64/nightly` from `https://dl.simplyluma.com/os/repo`
   into `OUT/repo`, verified with `config/os/keys/luma-os-release.asc`.
4. Packages:
   `scripts/packages/build-kernel-modules-luma-fajita.sh OUT/kernel/modules`,
   `scripts/packages/build-luma-fajita-firmware.sh OUT/fajita-firmware.tar --ostree-repo OUT/repo --ref luma/1/aarch64/nightly`,
   `scripts/packages/build-luma-fajita-platform.sh`, and `dnf download`
   `qbootctl rmtfs tqftpserv` with any dependencies the commit lacks
   (the phone image turns Fedora's repositories off).
5. Boot image: download `base_boot_image` from `device.toml`, then
   `scripts/mobile/build-fajita-boot-image.sh --base-boot FILE --kernel-dir OUT/kernel --ostree-repo OUT/repo --ref luma/1/aarch64/nightly --output luma-fajita-boot.img`.
6. Userdata: make a seed directory with `lib/luma/device-modules` (the
   kernel's `modules/lib/modules`), `lib/luma/device-firmware` (the firmware
   tar's `usr/lib/firmware`) and `lib/luma/fajita-rpms` (the RPMs), then as
   root:
   `scripts/mobile/build-phone-userdata.sh --repo OUT/repo --ref luma/1/aarch64/nightly --var-seed SEED --output luma-fajita-userdata.sparse`.

## Flash

Enter fastboot: hold Volume Up and Power. Test a new boot image first, without
writing it: `fastboot boot luma-fajita-boot.img`. Then:

```sh
fastboot flash userdata luma-fajita-userdata.sparse
fastboot flash boot_a luma-fajita-boot.img
fastboot flash boot_b luma-fajita-boot.img
fastboot set_active a
fastboot reboot
```

## First boot

Sign in as `luma` (password `1234`) and change the password. Layer the device
packages, then restart:

```sh
sudo rpm-ostree install /var/lib/luma/fajita-rpms/*.rpm
systemctl reboot
```

After that boot, `rpm-ostree status` lists the packages, and
`/var/lib/luma/device-modules` and `/var/lib/luma/device-firmware` are no
longer used. Delete them to free the space. The USB rescue network is at
172.16.42.1.
