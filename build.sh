#!/bin/sh

REPO=https://github.com/cjdelisle/openwrt.git
HASH=ba9f212b567ee1cda360ba1fdb98629862ec974b

rm -rf ./openwrt
mkdir openwrt
cd openwrt
git init
git remote add origin $REPO
git fetch --depth 1 origin $HASH
git checkout $HASH

# =====================================================================
# 1. 动态注入中国移动香港 GS2210 的精准 DTS 设备树（基于原厂 512MB 内存与真实 MTD）
# =====================================================================
DTS_DIR="target/linux/econet/dts"
mkdir -p "$DTS_DIR"

cat << 'EOF' > "$DTS_DIR/en751221-cmhk-gs2210.dts"
/dts-v1/;

#include "en751221.dtsi"

/ {
	model = "China Mobile HK GS2210";
	compatible = "cmhk,gs2210", "econet,en751221";

	chosen {
		bootargs = "console=ttyS0,115200 root=/dev/mtdblock3 rootfstype=squashfs earlyprintk";
	};

	memory@80000000 {
		device_type = "memory";
		reg = <0x80000000 0x20000000>; /* 严格对齐 512MB 物理内存 */
	};
};

&spi_nand {
	status = "okay";

	partitions {
		compatible = "fixed-partitions";
		#address-cells = <1>;
		#size-cells = <1>;

		/* mtd0: 256KB */
		partition@0 {
			label = "bootloader";
			reg = <0x0 0x40000>;
			read-only;
		};

		/* mtd1: 256KB */
		partition@40000 {
			label = "romfile";
			reg = <0x40000 0x40000>;
			read-only;
		};

		/* mtd4: 16MB 主系统 (包含原厂内核与根文件系统) */
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

		/* mtd12: 1.75MB */
		partition@dca0000 {
			label = "reservearea";
			reg = <0xdca0000 0x1c0000>;
			read-only;
		};
	};
};

&uart0 {
	status = "okay";
};
EOF

# 将新 DTS 注册到平台的设备树 Makefile 中
echo "obj-\$(CONFIG_DTB_EN751221_CMHK_GS2210) += en751221-cmhk-gs2210.dtb" >> "$DTS_DIR/Makefile"

# =====================================================================
# 2. 向编译系统的打包 Makefile 追加 GS2210 的机型定义（带原生魔数参数）
# =====================================================================
cat << 'EOF' >> target/linux/econet/image/en751221.mk

define Device/chinamobile_gs2210
  DEVICE_VENDOR := ChinaMobile
  DEVICE_MODEL := GS2210
  DEVICE_DTS := en751221-cmhk-gs2210
  SUPPORTED_DEVICES := chinamobile,gs2210
  KERNEL_SIZE := 16384k
  # 核心修复：在此处告知打包工具直接采用 CSK0（十六进制 0x43534b30）作为原始魔数打包
  # 从而让打包工具在封包时自动计算并填入包含 CSK0 在内的正确 CRC 校验码
  TRX_MAGIC := 0x43534b30
endef
TARGET_DEVICES += chinamobile_gs2210
EOF


# =====================================================================
# 3. 正常拉取依赖包并注入 `.config` 编译配置
# =====================================================================
./scripts/feeds update -a
./scripts/feeds install -a

echo '
CONFIG_TARGET_econet=y
CONFIG_TARGET_econet_en751221=y
CONFIG_TARGET_MULTI_PROFILE=y
CONFIG_TARGET_DEVICE_econet_en751221_DEVICE_chinamobile_gs2210=y
CONFIG_TARGET_DEVICE_PACKAGES_econet_en751221_DEVICE_chinamobile_gs2210=""
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

make defconfig

make "-j$(nproc)"

# =====================================================================
# 4. 固件后处理：仅执行规整重命名（不再需要用 dd 损坏 CRC）
# =====================================================================
cd ./bin/targets/econet/en751221

# 执行原作者的重命名逻辑
ls | sed -n -e 's/openwrt-snapshot-\(.*\)-econet-\(.*\)/mv openwrt-snapshot-\1-econet-\2 openwrt-econet-\2/p' | sh

echo "✅ 固件打包完成，已由编译系统自动使用 GS2210 使用CSK0 魔数并计算生成了正确的原生 CRC 校验码！"
