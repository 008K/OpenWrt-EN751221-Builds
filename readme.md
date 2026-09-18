# OpenWrt builds for EN751221 Devices

This repository contains the github actions to build and release
OpenWRT for EN751221 devices including:

* SmartFiber XP8421-B
* TP-Link Archer VR1200v (v2)
* Nokia G-240G-E
* Zyxel PMG5617GA
* ChinaMobile GS3101
* ChinaMobile HK GS2210

**NOTE:** This is a SNAPSHOT build of OpenWrt, not a release.
Currently repositories are not setup so installing software doesn't
work yet.

### ChinaMobile HK GS2210

Out of the box the GS2210 has no persistent storage. The JFFS2 overlay partition
(mtd4, "rootfs_data") cannot be mounted, because jffs2 wants to read the erase
block clean markers from the OOB area and the SPI-NAND/BMT driver returns EBADFD
for OOB reads (`jffs2: cannot read OOB for EB at 00700000, requested 8 bytes,
read 0 bytes, error -77`). The root filesystem therefore stays read-only, and
without a writable /etc the first boot cannot write `/etc/board.json`,
`/etc/config/network` or `/etc/config/wireless` at all.

The stock firmware never used the `yaffs` partition (mtd7, 128MB) either, so the
image turns it into a UBI device and mounts a UBIFS volume named `rootfs_data`
on it as the overlay. `base-files/lib/preinit/79_gs2210_ubi_overlay` attaches
that UBI device before mount_root runs; on the first boot after a flash the
partition still holds yaffs data, so the hook first formats it (ubiformat only
erases the 34 of 1024 erase blocks that hold something, which takes seconds) and
creates the volume. From then on the hook only attaches the existing device,
fstools picks the volume up in `80_mount_root`, and `/etc` and everything else
written at runtime survives a reboot.

If any of that fails, `base-files/lib/preinit/81_gs2210_ram_etc` falls back to a
RAM copy of /etc, so the board still comes up on 192.168.1.1 with a DHCP server
and both radios enabled with the SSID `OpenWrt` (open, no encryption) - just
without persistence. LuCI is included.

The 5G radio has no calibration data on this unit (the EEPROM cell inside
`reservearea` reads back 0xff, `mt76x2e: EEPROM data check failed: ffff`), so it
comes up at minimum tx power. 2.4G is calibrated and runs at full power.

LAST BUILD: JULY 22 2026
