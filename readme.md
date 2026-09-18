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
work yet. Other than the ChinaMobile GS3101, none of the devices
support persistent storage yet.

### ChinaMobile HK GS2210

The GS2210 has no persistent storage either, for the same reason the other
devices do not: the JFFS2 overlay partition (mtd4, "rootfs_data") cannot be
mounted, because jffs2 wants to read the erase block clean markers from the OOB
area and the SPI-NAND/BMT driver returns EBADFD for OOB reads
(`jffs2: cannot read OOB for EB at 00700000, requested 8 bytes, read 0 bytes,
error -77`). The root filesystem therefore stays read-only, and without a
writable /etc the first boot cannot write `/etc/board.json`, `/etc/config/network`
or `/etc/config/wireless` at all.

The image works around this with `base-files/lib/preinit/81_gs2210_ram_etc`,
which moves /etc to a RAM copy when the overlay is missing, so the normal first
boot path completes: the LAN comes up as 192.168.1.1 with a DHCP server, and the
2.4G and 5G radios are enabled with the SSID `OpenWrt` (open, no encryption).
LuCI is included. Everything configured at runtime is lost on reboot; making it
persistent needs a UBI overlay on the unused `yaffs` partition (mtd7).

The 5G radio has no calibration data on this unit (the EEPROM cell inside
`reservearea` reads back 0xff, `mt76x2e: EEPROM data check failed: ffff`), so it
comes up at minimum tx power. 2.4G is calibrated and runs at full power.

LAST BUILD: JULY 22 2026
