#!/bin/sh
#
# Build the OpenWrt image for the China Mobile Hong Kong GS2210 (EN751221).
#
# This checks out the pinned upstream tree, overlays the GS2210 board support
# files kept in this repository, and builds the tclinux.trx image.
#
# The script can be run from any directory: it always operates on the
# directory that holds it.

# Stop at the first failing step, and treat unset variables as an error.
set -eu

# The rm -rf and the overlay copies below are relative paths, so anchor them to
# this script's directory instead of the caller's working directory.
cd "$(dirname "$0")"

REPO=https://github.com/cjdelisle/openwrt.git
HASH=ba9f212b567ee1cda360ba1fdb98629862ec974b

# 1. 清理旧目录并精准检出作者锁定的官方 OpenWrt 源码树
rm -rf ./openwrt
mkdir openwrt
cd openwrt
git init -q
git remote add origin "$REPO"
git fetch --depth 1 origin "$HASH"
git checkout "$HASH"

# =====================================================================
# 2. 【核心注入】通过 Shell 直接动态创建专属于 CMHK GS2210 的 DTS 设备树文件
# =====================================================================
DTS_PATH="target/linux/econet/dts/"
echo "正在注入 CMHK GS2210 专属安全设备树 (DTS)..."
cp -f ../en751221_cmhk_gs2210.dts "$DTS_PATH"


# =====================================================================
# 3. 【核心追加】通过 Shell 向 image/en751221.mk 动态追加 GS2210 打包规则
# =====================================================================
MK_PATH="target/linux/econet/image/"
echo "正在向 en751221.mk 追加专属打包链与 CSK0 原生魔数..."
cp -f ../en751221.mk "$MK_PATH"
cp -f ../tclinux-trx.sh "$MK_PATH"

# =====================================================================
# 4. 拉取依赖包并注入主编译使能开关配置
# =====================================================================
./scripts/feeds update -a
./scripts/feeds install -a

# The seed must be written after the overlay files, otherwise make defconfig
# drops symbols whose device or package does not exist yet.
cat > .config <<'CONFIG_EOF'
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
CONFIG_EOF

# 5. 校验并补全依赖配置项
make defconfig

# 6. 火力全开加速编译 (nproc is not POSIX, fall back to a single job)
make -j"$(nproc 2>/dev/null || echo 1)"

# =====================================================================
# 7. 固件后处理：更名并提取专属于 CMHK GS2210 的完美包
# =====================================================================
cd ./bin/targets/econet/en751221

# Normalise the image file names by dropping the version prefix. Written as a
# glob rather than "ls | sed | sh" so that no file name is ever executed.
for f in openwrt-*-econet-en751221-*; do
    [ -f "$f" ] || continue
    mv "$f" "openwrt-econet-${f##*-econet-}"
done

# Fail loudly if the image is missing, so a broken build cannot be reported as
# a success by the trailing message.
OUT="openwrt-econet-en751221-cmhk_gs2210-squashfs-tclinux.trx"
if [ ! -f "$OUT" ]; then
    echo "ERROR: $OUT was not produced" >&2
    ls -l >&2
    exit 1
fi

echo "✅ 固件打包完成: $OUT"