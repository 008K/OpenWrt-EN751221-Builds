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

# CI hands us a download directory that lives outside the tree: this script
# deletes and re-fetches ./openwrt on every run, so downloads kept in the
# tree's own dl/ would never survive into the next build. Symlinking the
# external directory into place is all make needs to see.
if [ -n "${OPENWRT_DL_DIR:-}" ]; then
    mkdir -p "$OPENWRT_DL_DIR"
    ln -sfn "$OPENWRT_DL_DIR" dl
fi

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
# 3b. Board support files that belong in the target base-files: the preinit
#     hook that deals with the unmountable flash overlay, and the first-boot
#     wireless defaults. Both are shipped from this repository so they are
#     versioned next to the image that uses them.
# =====================================================================
BF_PATH="target/linux/econet/base-files/"
BOARD_FILES="lib/preinit/81_gs2210_ram_etc etc/config/wireless"
for f in $BOARD_FILES; do
    mkdir -p "$BF_PATH$(dirname "$f")"
    cp -f "../base-files/$f" "$BF_PATH$f"
done

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

# LuCI. There is no package feed wired up on this board yet (and this
# snapshot uses apk rather than opkg), so the web interface has to be baked
# in; without it the only way into the box is the serial console. luci-base
# pulls the module set it needs, the explicit lines below keep the pieces
# that matter from being dropped silently by a later defconfig.
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-mod-network=y
CONFIG_PACKAGE_luci-mod-status=y
CONFIG_PACKAGE_luci-mod-system=y
CONFIG_PACKAGE_luci-theme-bootstrap=y
CONFIG_PACKAGE_luci-app-firewall=y
CONFIG_PACKAGE_uhttpd=y
CONFIG_PACKAGE_uhttpd-mod-ubus=y
CONFIG_PACKAGE_rpcd=y
CONFIG_PACKAGE_rpcd-mod-file=y
CONFIG_PACKAGE_rpcd-mod-iwinfo=y
CONFIG_PACKAGE_rpcd-mod-luci=y
CONFIG_PACKAGE_rpcd-mod-ucode=y
CONFIG_PACKAGE_iwinfo=y
CONFIG_TARGET_INITRAMFS_COMPRESSION_NONE=y
CONFIG_TARGET_ROOTFS_INITRAMFS=y
# Keep the version out of the image file names. The image, sha256sums and
# profiles.json all take their names from these two prefixes; leaving them on
# yields openwrt-snapshot-<revision>-econet-en751221-..., which is why the build
# used to rename the image afterwards and leave sha256sums pointing at a file
# name that no longer existed.
# VERSIONOPT must be enabled first: both prompts are hidden behind
# "if VERSIONOPT", and a hidden prompt makes them ignore what is written here
# and fall back to their default of "y".
CONFIG_VERSIONOPT=y
# CONFIG_VERSION_FILENAMES is not set
# CONFIG_VERSION_CODE_FILENAMES is not set
CONFIG_EOF

# 5. 校验并补全依赖配置项
make defconfig

# Fail early if the LuCI packages did not survive defconfig. An image without
# them boots and looks healthy over the serial console but has no web UI at all.
for sym in CONFIG_PACKAGE_luci-base CONFIG_PACKAGE_uhttpd \
           CONFIG_PACKAGE_uhttpd-mod-ubus CONFIG_PACKAGE_rpcd \
           CONFIG_PACKAGE_luci-theme-bootstrap; do
    grep -q "^$sym=y" .config || {
        echo "ERROR: $sym is not enabled in .config" >&2
        exit 1
    }
done

# Fail here rather than an hour into the build if the seed above did not take
# effect: the releases job downloads the image by an unversioned name.
if grep -qE '^CONFIG_VERSION_(CODE_)?FILENAMES=y' .config; then
    echo "ERROR: version prefixes are still enabled in .config" >&2
    grep -E '^CONFIG_VERSION' .config >&2 || true
    exit 1
fi

# 6. 火力全开加速编译 (nproc is not POSIX, fall back to a single job)
make -j"$(nproc 2>/dev/null || echo 1)"

# =====================================================================
# 7. 固件后处理：校验产物并输出校验值
# =====================================================================
cd ./bin/targets/econet/en751221

# Nothing to rename here any more: with the version prefixes switched off in
# .config, the image lands under the name the release job expects, which is also
# the name sha256sums and profiles.json recorded for it.
#
# Fail loudly if the image is missing, so a broken build cannot be reported as
# a success by the trailing message.
OUT="openwrt-econet-en751221-cmhk_gs2210-squashfs-tclinux.trx"
if [ ! -f "$OUT" ]; then
    echo "ERROR: $OUT was not produced" >&2
    ls -1 >&2
    exit 1
fi

# sha256sums is generated from the files on disk, so it has to list the image we
# are about to publish; checking it here keeps a name mismatch from shipping as
# a release asset that nobody can verify.
if [ -f sha256sums ]; then
    if ! grep -qF -- "$OUT" sha256sums; then
        echo "ERROR: $OUT is missing from sha256sums" >&2
        grep -F -- 'econet-en751221' sha256sums >&2 || true
        exit 1
    fi
    grep -F -- "$OUT" sha256sums | sha256sum -c -
fi

sha256sum "$OUT"
echo "✅ 固件打包完成: $OUT"