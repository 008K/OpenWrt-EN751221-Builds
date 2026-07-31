#!/bin/sh

REPO=https://github.com/cjdelisle/openwrt.git
HASH=ba9f212b567ee1cda360ba1fdb98629862ec974b

# 1. 清理旧目录并精准检出作者锁定的官方 OpenWrt 源码树
rm -rf ./openwrt
mkdir openwrt
cd openwrt
git init
git remote add origin $REPO
git fetch --depth 1 origin $HASH
git checkout $HASH

# =====================================================================
# 2. 【核心注入】通过 Shell 直接动态创建专属于 CMHK GS2210 的 DTS 设备树文件
# =====================================================================
DTS_PATH="target/linux/econet/dts/en751221_cmhk_gs2210.dts"
echo "正在注入 CMHK GS2210 专属安全设备树 (DTS)..."

cat << 'EOF' > "$DTS_PATH"
// SPDX-License-Identifier: (GPL-2.0-only OR BSD-2-Clause)
/dts-v1/;

#include "en751221.dtsi"

/ {
	model = "China Mobile HK GS2210";
	compatible = "cmhk,gs2210", "econet,en751221";

	memory@0 {
		device_type = "memory";
		reg = <0x00000000 0x20000000>; /* 512MB 总物理内存 */
	};

	chosen {
		stdout-path = "/serial@1fbf0000:115200";
		linux,usable-memory-range = <0x00020000 0x1b7e0000>; /* 对齐原厂 440MB 可用内存边界 */
	};
};

&spi_nand {
	status = "okay";
	econet,bmt;

	partitions {
		compatible = "fixed-partitions";
		#address-cells = <1>;
		#size-cells = <1>;

		/* mtd0: 256KB */
		partition@0 {
			label = "bootloader";
			reg = <0x0 0x40000>;
			read-only;

			nvmem-layout {
				compatible = "fixed-layout";
				#address-cells = <1>;
				#size-cells = <1>;

				macaddr_bootloader_ff48: macaddr@ff48 {
					compatible = "mac-base";
					reg = <0xff48 0x6>;
					#nvmem-cell-cells = <1>;
				};
			};
		};

		/* mtd1: 256KB */
		partition@40000 {
			label = "romfile";
			reg = <0x40000 0x40000>;
		};

		/* mtd4: 16MB 主系统 (合并原厂内核与文件系统边界，绝不越界覆盖) */
		partition@80000 {
			label = "firmware";
			reg = <0x80000 0x1000000>;
		};

		/* mtd7: 16MB 备份系统 */
		partition@1080000 {
			label = "tclinux_slave";
			reg = <0x1080000 0x1000000>;
			read-only;
		};

		/* mtd8: 52MB */
		partition@2080000 {
			label = "osgi";
			reg = <0x2080000 0x3400000>;
		};

		/* mtd9: 128MB */
		partition@5480000 {
			label = "yaffs";
			reg = <0x5480000 0x8000000>;
		};

		/* mtd10: 128KB */
		partition@d480000 {
			label = "upgradeflag";
			reg = <0xd480000 0x20000>;
		};

		/* mtd11: 8MB */
		partition@d4a0000 {
			label = "scdata";
			reg = <0xd4a0000 0x800000>;
		};

		/* mtd12: 1.75MB 保留配置区 */
		partition@dca0000 {
			label = "reservearea";
			reg = <0xdca0000 0x1c0000>;
			read-only;

			nvmem-layout {
				compatible = "fixed-layout";
				#address-cells = <1>;
				#size-cells = <1>;

				eeprom_reserve_140000: eeprom@140000 {
					reg = <0x140000 0x200>;
				};

				eeprom_reserve_180040: eeprom@180040 {
					reg = <0x180040 0x600>;
				};
			};
		};
	};
};

&gmac0 {
	status = "okay";
	nvmem-cells = <&macaddr_bootloader_ff48 0>;
	nvmem-cell-names = "mac-address";
};

&pcie0 { status = "okay"; };
&slot0 {
	wifi@0,0 {
		compatible = "mediatek,mt76";
		reg = <0x0000 0 0 0 0>;
		nvmem-cells = <&eeprom_reserve_180040>, <&macaddr_bootloader_ff48 1>;
		nvmem-cell-names = "eeprom", "mac-address";
	};
};

&pcie1 { status = "okay"; };
&slot1 {
	wifi@0,0 {
		compatible = "mediatek,mt76";
		reg = <0x0000 0 0 0 0>;
		nvmem-cells = <&eeprom_reserve_140000>, <&macaddr_bootloader_ff48 2>;
		nvmem-cell-names = "eeprom", "mac-address";
	};
};
EOF

# =====================================================================
# 3. 【核心追加】通过 Shell 向 image/en751221.mk 动态追加 GS2210 打包规则
# =====================================================================
MK_PATH="target/linux/econet/image/en751221.mk"
echo "正在向 en751221.mk 追加专属打包链与 CSK0 原生魔数..."

cat << 'EOF' >> "$MK_PATH"

define Device/cmhk_gs2210
  DEVICE_VENDOR := CMHK
  DEVICE_MODEL := GS2210
  DEVICE_DTS := en751221_cmhk_gs2210
  SUPPORTED_DEVICES := cmhk,gs2210
  IMAGES := tclinux.trx
  IMAGE/tclinux.trx := append-kernel | lzma | tclinux-trx
  TRX_MAGIC := 0x43534b30
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7603 kmod-mt76x2
endef
TARGET_DEVICES += cmhk_gs2210
EOF

# =====================================================================
# 4. 拉取依赖包并注入主编译使能开关配置
# =====================================================================
./scripts/feeds update -a
./scripts/feeds install -a

echo '
CONFIG_TARGET_econet=y
CONFIG_TARGET_econet_en751221=y
CONFIG_TARGET_MULTI_PROFILE=y
CONFIG_TARGET_DEVICE_econet_en751221_DEVICE_cmhk_gs2210=y
CONFIG_TARGET_DEVICE_PACKAGES_econet_en751221_DEVICE_cmhk_gs2210=""
CONFIG_TARGET_PER_DEVICE_ROOTFS=y
CONFIG_FEED_luci=y
CONFIG_FEED_packages=y
CONFIG_FEED_routing=y
CONFIG_FEED_telephony=y
CONFIG_FEED_video=y
CONFIG_IMAGEOPT=y
CONFIG_PACKAGE_kmod-crypto-sha256=y
CONFIG_PACKAGE_kmod-econet-eth=y
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_kmod-gpio-button-hotplug=y
CONFIG_PACKAGE_kmod-lib-crc16=y
CONFIG_PACKAGE_kmod-libphy=y
CONFIG_PACKAGE_kmod-mii=y
CONFIG_PACKAGE_kmod-nls-base=y
CONFIG_PACKAGE_kmod-nls-cp437=y
CONFIG_PACKAGE_kmod-nls-iso8859-1=y
CONFIG_PACKAGE_kmod-nls-utf8=y
CONFIG_PACKAGE_kmod-scsi-core=y
CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_kmod-usb-common=y
CONFIG_PACKAGE_kmod-usb-core=y
CONFIG_PACKAGE_kmod-usb-net-rtl8152=y
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_nand-utils=y
CONFIG_PACKAGE_libatomic=y
CONFIG_PACKAGE_libpthread=y
CONFIG_PACKAGE_librt=y
CONFIG_PACKAGE_libstdcpp=y
CONFIG_PACKAGE_r8152-firmware=y
CONFIG_PACKAGE_wpad-basic-mbedtls=y
CONFIG_TARGET_INITRAMFS_COMPRESSION_NONE=y
CONFIG_TARGET_ROOTFS_INITRAMFS=y
' > .config

# 5. 校验并补全依赖配置项
make defconfig

# 6. 火力全开加速编译
make "-j$(nproc)"

# =====================================================================
# 7. 固件后处理：更名并提取专属于 CMHK GS2210 的完美包
# =====================================================================
cd ./bin/targets/econet/en751221

# 执行原作者固有的更名规整命令
ls | sed -n -e 's/openwrt-snapshot-\(.*\)-econet-\(.*\)/mv openwrt-snapshot-\1-econet-\2 openwrt-econet-\2/p' | sh

# 捕获刚刚用 tclinux-trx 包装好且自带闭合原生 CSK0 CRC 的 trx 固件
echo "✅ 固件打包完成."
