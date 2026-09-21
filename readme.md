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

### Front panel: LAN and WAN on the integrated switch

The SoC contains an MT7530 compatible switch whose first five PHY ports go to
the front panel: port 0 is the socket labelled WAN, ports 1, 2 and 3 are the
three sockets labelled LAN, and port 4 is the footprint of an unpopulated
socket. The stock firmware reports the same map in its own
`/proc/tc3162/eth_portmap`: `wan_port_id` 0 and `lan_port_map` 1, 2, 3. Port 6
is the CPU port, a TRGMII link back into the frame engine, and it is the only
path a frame can take to reach Linux.

The stock driver leaves the switch in its flat, bootloader configuration: it
bridges all the sockets together and never programs the VLAN table, so every
frame arrives on eth0 untagged and nothing tells the WAN socket apart from a
LAN socket.

`patches/100-gsw-lan-wan-vlan.patch` gives the econet-eth module a VLAN
configuration instead. VLAN 1 holds the LAN ports plus the CPU port, VLAN 2
holds the WAN port plus the CPU port, and the CPU port is a tagged member of the
WAN VLAN only. So the WAN socket is separated from the LAN sockets in hardware
rather than by the kernel, and frames from it arrive carrying a tag, which
`base-files/etc/board.d/02_network` turns into the `eth0.2` VLAN device.
Untagged frames from a LAN socket keep arriving untagged on plain `eth0`, which
stays the LAN interface, so the LAN side is the interface it has always been.

The tag handling is built into the kernel (`CONFIG_VLAN_8021Q=y`), so no extra
package is needed; netifd creates the VLAN device itself when it brings up the
interface.

The driver fills in the VLAN table before it moves any port out of the flat
matrix, and it moves the ports to *fallback* mode rather than security mode, so
a VID that is missing from the table still forwards by the port matrix, which
the bootloader leaves as all ports. The intended failure mode is therefore "LAN
keeps working, no WAN": if anything in the patch does not take effect on this
part, the sockets keep switching the way they do without it. After flashing,
`dmesg | grep 'switch:'` shows which happened: a
`switch: VLAN 1 on ports 0x0e and VLAN 2 on port 0x01, tagged on CPU port 6
only; WAN is eth0.2` line means the split is in place, while
`switch: VLAN 1 reads back as ...` or `switch: keeping the flat configuration`
means it is not.

### ChinaMobile HK GS2210 (old notes)

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
