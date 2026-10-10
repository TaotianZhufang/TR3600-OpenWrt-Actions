#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-iStore-part2.sh
# Description: OpenWrt DIY script part 2 (After Update Feeds)
#
# TR3600 build kit version:
#   * same tweaks as liangcanming/Cudy-tr3600-v1-6.12 (default IP, argon theme)
#   * ADDED: apply the four TR3600 board fixes
#       0001-tr3600-fan-pwm0.patch              -> PWM fan channel 1 -> 0
#       0004-tr3600-led-colours.patch           -> GPIO48 white / GPIO46 red
#       0005-tr3600-wifi-mac-layout.patch       -> 2.4 GHz base+0, 5 GHz base+0x10
#       0006-tr3600-fan-thermal-curve.patch     -> fan off below 60 C
#     Each one is verified with --dry-run first and re-checked afterwards; the
#     script aborts the build if a patch does not apply, so you never end up
#     flashing a silently broken image.
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

echo "========================================================"
echo " TR3600 build kit: diy-iStore-part2.sh"
echo " repo root : $REPO_ROOT"
echo " patch dir : $PATCHDIR"
echo "========================================================"

# =========================================================
# 修改默认 IP 地址（可选）
# =========================================================

# 将默认 IP 从 192.168.1.1 改为 192.168.6.1
sed -i 's/192.168.1.1/192.168.6.1/g' package/base-files/files/bin/config_generate

# =========================================================
# 修改默认主机名（可选）
# =========================================================

# sed -i 's/OpenWrt/Cudy-TR3600/g' package/base-files/files/bin/config_generate

# =========================================================
# 修改默认时区（可选）
# =========================================================

# 设置默认LuCI主题为argon
sed -i 's/luci.main.theme=bootstrap/luci.main.theme=argon/' package/base-files/files/etc/config/luci
# 备份兼容写法，防止上面没匹配到
echo "uci set luci.main.theme='argon'" >> package/base-files/files/etc/uci-defaults/99-default-theme
echo "uci commit luci" >> package/base-files/files/etc/uci-defaults/99-default-theme

# =========================================================
# 修正 1/2 — 板级 DTS：風扇通道 / LED 顏色 / WiFi MAC / 溫控曲線
# =========================================================
DTS=target/linux/mediatek/dts/mt7987b-cudy-tr3600-v1.dts

echo "--------------------------------------------------------"
echo "[1/2] board DTS fixes -> $DTS"
if [ ! -f "$DTS" ]; then
	echo "ERROR: $DTS not found. Is REPO_BRANCH still agent/cudy-tr3600-v1-6.12 ?"
	exit 1
fi

# apply_dts_patch <patch-basename> <marker-string>
#   applies patches/<basename>.patch with -p1, is idempotent, and aborts the
#   build if the patch neither applies nor lands.  Never ship a silently
#   broken DTS.
apply_dts_patch() {
	local name="$1" marker="$2"
	if grep -qF "$marker" "$DTS"; then
		echo "  $name: already applied, skipping"
	else
		patch -p1 --dry-run --forward -s < "$PATCHDIR/$name.patch" \
			|| { echo "ERROR: $name does not apply"; exit 1; }
		patch -p1 --forward -s < "$PATCHDIR/$name.patch"
		echo "  $name: applied"
	fi
	grep -qF "$marker" "$DTS" || { echo "ERROR: $name did not take effect"; exit 1; }
}

# 1. fan on PWM0 (PIN13) instead of PWM1; pinctrl-0 -> pwm_pins
apply_dts_patch 0001-tr3600-fan-pwm0          'pwms = <&pwm 0 50000 0>;'
# 2. GPIO48 = white, GPIO46 = red (there is no blue LED on this board)
apply_dts_patch 0004-tr3600-led-colours       'led_status_white: led-0 {'
# 3. 2.4 GHz = base + 0x00, 5 GHz = base + 0x10 (vendor layout)
apply_dts_patch 0005-tr3600-wifi-mac-layout   'nvmem-cells = <&macaddr_bdinfo_de00 16>;'
# 4. fan off below 60 C, 65/75/85 C ramp (was 50 % from 40 C upwards)
apply_dts_patch 0006-tr3600-fan-thermal-curve 'cooling-levels = <0 64 160 255>;'

grep -qF 'pinctrl-0 = <&pwm_pins>;' "$DTS" || { echo "ERROR: pinctrl not fixed"; exit 1; }
echo "  OK: PWM0 fan / white+red LEDs / vendor MAC layout / 65-75-85 C fan curve"

# =========================================================
# 修正 2/2 — mt76 STA_REC / VoW 順序
# =========================================================
P2="$PATCHDIR/0002-mt76-mt7996-sta-rec-before-vow.patch"
MT76PATCHDIR=package/kernel/mt76/patches

echo "--------------------------------------------------------"
echo "[2/2] mt76 backport -> $MT76PATCHDIR/"
if [ ! -f "$P2" ]; then
	echo "ERROR: $P2 not found"
	exit 1
fi

MT76_SHA=$(sed -n 's/^PKG_SOURCE_VERSION:=//p' package/kernel/mt76/Makefile | tr -d ' ')
echo "  mt76 PKG_SOURCE_VERSION = $MT76_SHA"
if [ "$MT76_SHA" != "39c960c3ada558b4c2e7915772483d3731573d09" ]; then
	echo "  WARNING: mt76 was bumped upstream. The backport was verified against"
	echo "           39c960c3ada558b4c2e7915772483d3731573d09 only."
	echo "           The patch may still apply - the build will fail loudly if not."
fi

mkdir -p "$MT76PATCHDIR"
cp "$P2" "$MT76PATCHDIR/0202-wifi-mt76-mt7996-send-the-STA_REC-before-the-per-station-VoW-setup.patch"
echo "  installed: $(basename "$MT76PATCHDIR"/0202-*.patch)"

echo "========================================================"
echo " TR3600 build kit patches applied successfully"
echo "========================================================"
