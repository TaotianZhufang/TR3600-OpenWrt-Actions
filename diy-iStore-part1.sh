#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-iStore-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update Feeds)
#
# TR3600 build kit version:
#   * same feed/plugin set as liangcanming/Cudy-tr3600-v1-6.12
#   * CHANGED: luci-app-tr3600-fan is no longer cloned from GitHub.
#     The upstream repo (liangcanming/luci-app-tr3600-fan) and the whole
#     liangcanming account went 404 in 2026-10, which killed build #1 with
#     "fatal: could not read Username for 'https://github.com'". The package
#     is now vendored in this repository under vendor/luci-app-tr3600-fan/
#     (byte-identical to MichaelJiangg/luci-app-tr3600-fan, which is the
#     upstream the fix patches were written against). A clone from GitHub is
#     kept only as a fallback if the vendored copy is missing.
#   * ADDED: force the tr3600-fan init script and helper to be executable.
#     The luci-app-tr3600-fan git tree stores every file as mode 100644, and
#     OpenWrt copies the package 'root/' directory with $(CP) = "cp -fpR",
#     which preserves that mode. The result was /usr/sbin/tr3600-fan and
#     /etc/init.d/tr3600-fan landing on the device as 0644, so
#     fs.exec_direct('/usr/sbin/tr3600-fan') failed with EACCES, the LuCI
#     page got an empty status and reported
#     "The PWM fan cooling device was not detected."
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Locate the build-kit repo root. In GitHub Actions the workflow copies this
# script into the openwrt/ checkout and runs it from there, so the repo root
# is one level up. When run straight from the repo root (local testing) it is
# SCRIPT_DIR itself. Prefer whichever one actually contains patches/.
if [ -d "$SCRIPT_DIR/patches" ]; then
	REPO_ROOT="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/../patches" ]; then
	REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
	REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
	echo "[tr3600-fix] WARNING: no patches/ directory found near $SCRIPT_DIR"
fi
PATCHDIR="$REPO_ROOT/patches"

mkdir -p package/custom

# =========================================================
# 科学插件
# =========================================================

# Passwall
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/custom/passwall-packages
rm -rf feeds/luci/applications/luci-app-passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall.git package/custom/passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2.git package/custom/passwall2

# OpenClash
rm -rf feeds/luci/applications/luci-app-openclash
git clone --depth=1 -b master https://github.com/vernesong/OpenClash.git package/custom/openclash

# Nikki / Momo
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki.git package/custom/nikki
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-momo.git package/custom/momo

# Daed
git clone --depth=1 -b kix https://github.com/QiuSimons/luci-app-daed.git package/custom/daed
git clone --depth=1 https://github.com/QiuSimons/vmlinux-btf.git package/custom/vmlinux-btf

# SSR+
git clone --depth=1 https://github.com/fw876/helloworld.git package/custom/ssrp

# =========================================================
# Cudy TR3600 风扇控制插件（内建，不依赖第三方仓库）
# =========================================================
# 原版这里是：
#   git clone --depth=1 https://github.com/liangcanming/luci-app-tr3600-fan.git
# 但 liangcanming 名下仓库（含 Actions 外壳仓库 Cudy-tr3600-v1-6.12）在
# 2026-10 已全部 404，导致 build #1 直接失败：
#   fatal: could not read Username for 'https://github.com'
# 因此把整个套件内建在本仓库 vendor/luci-app-tr3600-fan/，
# 与 MichaelJiangg/luci-app-tr3600-fan 逐字节相同
# （已用 SHA256 与 TR3600-build-kit/reference/ 快照比对通过），
# 这样即使第三方仓库再次消失，编译也不会受影响。
VENDOR_FAN="$REPO_ROOT/vendor/luci-app-tr3600-fan"
FANPKG="package/custom/luci-app-tr3600-fan"

rm -rf "$FANPKG"
if [ -d "$VENDOR_FAN" ]; then
	echo "[tr3600-fix] 使用内建风扇套件: $VENDOR_FAN"
	cp -a "$VENDOR_FAN" "$FANPKG"
else
	echo "[tr3600-fix] WARNING: $VENDOR_FAN 不存在，回退到上游 clone"
	git clone --depth=1 https://github.com/MichaelJiangg/luci-app-tr3600-fan.git "$FANPKG" \
		|| git clone --depth=1 https://github.com/liangcanming/luci-app-tr3600-fan.git "$FANPKG"
fi

# --- TR3600 build kit fix: make the fan helper + init script executable ---
for f in "$FANPKG/root/usr/sbin/tr3600-fan" "$FANPKG/root/etc/init.d/tr3600-fan" "$FANPKG/root/etc/uci-defaults/99-tr3600-fan"; do
	if [ -f "$f" ]; then
		chmod 0755 "$f"
		echo "[tr3600-fix] chmod 0755 $f"
	else
		echo "[tr3600-fix] WARNING: $f not found"
	fi
done
# Belt and braces: make sure a later re-checkout cannot silently drop the bit.
chmod 0755 "$FANPKG/Makefile" 2>/dev/null || true

# --- TR3600 build kit fix: LuCI fan page patches ---
#   0003: the 5 s poll must not clobber input the user has not applied yet.
#   0008: smart seasonal suggestion (idle baseline -> suggested curve,
#         season override, one-click apply).
#
# Order matters and 0003 must succeed: 0008's view hunks use the `dirty`
# flag lines that 0003 introduces as context. Measured without 0003 first:
# 3 of 7 hunks FAILED and a .rej was left behind, i.e. a half-patched page.
# Both are therefore fatal now instead of "warn and continue".
#
# -F 0 / --no-backup-if-mismatch are not cosmetic: the default fuzz of 2
# lets patch "fuzzily" match when upstream touches the lines at a hunk
# boundary, still returning rc=0 and leaving a .orig behind. Measured:
# after editing the temperatureText() line, 0008 still reported rc=0.
# With -F 0 the same drift fails loudly with rc=1.
apply_fan_patch() {
	local p="$1" name="$2"
	if [ ! -f "$p" ]; then
		echo "ERROR: $p not found"
		exit 1
	fi
	if ! ( cd "$FANPKG" && patch -p1 --dry-run --forward -s -F 0 --no-backup-if-mismatch < "$p" >/dev/null 2>&1 ); then
		echo "ERROR: $name does not apply (dry-run failed)."
		echo "       The package is a copy of vendor/luci-app-tr3600-fan;"
		echo "       this happens if the upstream content changed or if the"
		echo "       patch order was reversed."
		exit 1
	fi
	( cd "$FANPKG" && patch -p1 --forward -s -F 0 --no-backup-if-mismatch < "$p" )
	echo "[tr3600-fix] applied $name"
}

apply_fan_patch "$PATCHDIR/0003-luci-tr3600-fan-keep-pending-input.patch" \
	0003-luci-tr3600-fan-keep-pending-input.patch
apply_fan_patch "$PATCHDIR/0008-luci-tr3600-fan-smart-suggestions.patch" \
	0008-luci-tr3600-fan-smart-suggestions.patch
# -------------------------------------------------------------

# 添加 istore feed 到 feeds.conf.default
echo "src-git istore https://github.com/linkease/istore;main" >> feeds.conf.default


# =========================================================
# 功能插件（无 Docker）
# =========================================================

git clone --depth=1 https://github.com/sirpdboy/luci-app-poweroffdevice.git package/custom/poweroffdevice
git clone --depth=1 https://github.com/isalikai/luci-app-owq-wol.git package/custom/owq-wol
# luci-app-lucky (gdy666) 已移除：套件不夠完善，暫時不編進去。
# 要加回來就取消下面這行註解，並在 config 補上：
#   CONFIG_PACKAGE_luci-app-lucky=y
#   CONFIG_PACKAGE_luci-i18n-lucky-zh-cn=y
# git clone --depth=1 https://github.com/gdy666/luci-app-lucky.git package/custom/lucky
git clone --depth=1 https://github.com/sbwml/luci-app-openlist2.git package/custom/openlist2

git clone --depth=1 https://github.com/stackia/rtp2httpd.git package/custom/rtp2httpd

git clone --depth=1 https://github.com/sirpdboy/luci-app-watchdog.git package/custom/watchdog
git clone --depth=1 https://github.com/sirpdboy/luci-app-taskplan.git package/custom/taskplan
git clone --depth=1 https://github.com/iv7777/luci-app-authshield.git package/custom/authshield
git clone --depth=1 https://github.com/destan19/OpenAppFilter.git package/custom/OpenAppFilter
git clone --depth=1 https://github.com/janvanstiphout/luci-app-accesscontrol.git package/custom/accesscontrol

# =========================================================
# DNS 相关（mosdns / smartdns）
# =========================================================

# 升级替换 mosdns
find ./ | grep Makefile | grep v2ray-geodata | xargs rm -f
find ./ | grep Makefile | grep mosdns | xargs rm -f

git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/custom/mosdns
git clone https://github.com/sbwml/v2ray-geodata package/custom/v2ray-geodata

rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang

# 升级替换 smartdns
WORKINGDIR="`pwd`/feeds/packages/net/smartdns"
mkdir $WORKINGDIR -p
rm $WORKINGDIR/* -fr
wget https://github.com/pymumu/openwrt-smartdns/archive/master.zip -O $WORKINGDIR/master.zip
unzip $WORKINGDIR/master.zip -d $WORKINGDIR
mv $WORKINGDIR/openwrt-smartdns-master/* $WORKINGDIR/
rmdir $WORKINGDIR/openwrt-smartdns-master
rm $WORKINGDIR/master.zip

LUCIBRANCH="master"
WORKINGDIR="`pwd`/feeds/luci/applications/luci-app-smartdns"
mkdir $WORKINGDIR -p
rm $WORKINGDIR/* -fr
wget https://github.com/pymumu/luci-app-smartdns/archive/${LUCIBRANCH}.zip -O $WORKINGDIR/${LUCIBRANCH}.zip
unzip $WORKINGDIR/${LUCIBRANCH}.zip -d $WORKINGDIR
mv $WORKINGDIR/luci-app-smartdns-${LUCIBRANCH}/* $WORKINGDIR/
rmdir $WORKINGDIR/luci-app-smartdns-${LUCIBRANCH}
rm $WORKINGDIR/${LUCIBRANCH}.zip

# =========================================================
# VPN
# =========================================================

git clone --depth=1 https://github.com/EasyTier/luci-app-easytier.git package/custom/easytier
git clone --depth=1 https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community.git package/custom/tailscale-community

# =========================================================
# 主题
# =========================================================

git clone --depth=1 -b openwrt-25.12 https://github.com/sbwml/luci-theme-argon.git package/custom/luci-theme-argon

git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora.git package/custom/luci-theme-aurora
git clone --depth=1 https://github.com/eamonxg/luci-app-aurora-config.git package/custom/luci-app-aurora-config

git clone --depth=1 https://github.com/sirpdboy/luci-theme-kucat.git package/custom/luci-theme-kucat
git clone --depth=1 https://github.com/sirpdboy/luci-app-kucat-config.git package/custom/luci-app-kucat-config
