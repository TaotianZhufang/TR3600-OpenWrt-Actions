#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-iStore-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update Feeds)
#
# TR3600 build kit version:
#   * same feed/plugin set as liangcanming/Cudy-tr3600-v1-6.12
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
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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
# Cudy TR3600 风扇控制插件
# =========================================================
git clone --depth=1 https://github.com/liangcanming/luci-app-tr3600-fan.git package/custom/luci-app-tr3600-fan

# --- TR3600 build kit fix: make the fan helper + init script executable ---
FANPKG=package/custom/luci-app-tr3600-fan
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

# --- TR3600 build kit fix: LuCI fan page must not clobber pending input ---
# Cosmetic only (the 5 s poll used to snap the slider back). Non-fatal:
# if it does not apply the build continues with an unpatched LuCI page.
P3="$PATCHDIR/0003-luci-tr3600-fan-keep-pending-input.patch"
if [ -f "$P3" ]; then
	if ( cd "$FANPKG" && patch -p1 --dry-run --forward -s < "$P3" >/dev/null 2>&1 ); then
		( cd "$FANPKG" && patch -p1 --forward -s < "$P3" )
		echo "[tr3600-fix] applied 0003-luci-tr3600-fan-keep-pending-input.patch"
	else
		echo "[tr3600-fix] WARNING: 0003 LuCI patch does not apply, continuing without it"
	fi
else
	echo "[tr3600-fix] WARNING: $P3 not found"
fi
# -------------------------------------------------------------

# 添加 istore feed 到 feeds.conf.default
echo "src-git istore https://github.com/linkease/istore;main" >> feeds.conf.default


# =========================================================
# 功能插件（无 Docker）
# =========================================================

git clone --depth=1 https://github.com/sirpdboy/luci-app-poweroffdevice.git package/custom/poweroffdevice
git clone --depth=1 https://github.com/isalikai/luci-app-owq-wol.git package/custom/owq-wol
git clone --depth=1 https://github.com/gdy666/luci-app-lucky.git package/custom/lucky
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
