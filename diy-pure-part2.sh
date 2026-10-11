#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-pure-part2.sh
# Description: OpenWrt DIY script part 2 (After Update Feeds)
#              純淨基礎 + 性能優化版
#
# 這個腳本做四件事：
#   1. 預設 IP / 語言 / 主題（bootstrap，OpenWrt 原生）
#   2. 板級 DTS 修正 0001 / 0004 / 0005 / 0006 / 0007（風扇 + LED + WiFi MAC）
#   3. mt76 backport 0002（STA_REC 先於 VoW，修 wifi down/up 後連不上）
#   4. 性能優化：BBR + fq、硬體流量卸載（HWNAT）、TCP 緩衝區
#
# 每個 DTS patch 都先 --dry-run 再套用，套用後複查標記字串；任何一個沒生效
# 就 exit 1，絕不產出「看起來編過了但其實沒修」的固件。
#
# 註：0006 與 0007 都會動同一段，順序不能顛倒（0007 改的是 0006 放進去的值）。
#     0006 的偵測標記刻意用 `cpu_trip_active_low: active-low {`，
#     因為 0007 會把 0006 的 `cooling-levels = <0 64 160 255>` 改掉，
#     用那個當標記會讓「重跑」誤判成沒套用。
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -d "$SCRIPT_DIR/patches" ]; then
	REPO_ROOT="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/../patches" ]; then
	REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
	REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
	echo "[tr3600-pure] WARNING: no patches/ directory found near $SCRIPT_DIR"
fi
PATCHDIR="$REPO_ROOT/patches"

echo "========================================================"
echo " TR3600 pure build: diy-pure-part2.sh"
echo " repo root : $REPO_ROOT"
echo " patch dir : $PATCHDIR"
echo "========================================================"

# =========================================================
# 1. 預設 IP / 語言 / 主題
# =========================================================

# 預設 IP 從 192.168.1.1 改為 192.168.6.1
sed -i 's/192.168.1.1/192.168.6.1/g' package/base-files/files/bin/config_generate

# 主題：OpenWrt 原生 bootstrap。
# config 裡已經有 CONFIG_DEFAULT_THEME=bootstrap + CONFIG_PACKAGE_default-settings，
# 這裡再放一份 uci-defaults 兜底。注意 openwrt-25.12 的 base-files 已經沒有
# etc/config/luci，對它 sed 會在 `set -e` 下直接打死編譯，所以一定要先判斷。
LUCI_CFG=package/base-files/files/etc/config/luci
if [ -f "$LUCI_CFG" ]; then
	sed -i 's/luci.main.theme=argon/luci.main.theme=bootstrap/' "$LUCI_CFG"
	echo "[tr3600-pure] patched $LUCI_CFG -> bootstrap"
else
	echo "[tr3600-pure] $LUCI_CFG 不存在（openwrt-25.12 已移除），改用 uci-defaults"
fi

# =========================================================
# 2. 性能優化（sysctl）
# =========================================================
SYSCTL=package/base-files/files/etc/sysctl.conf
if [ -f "$SYSCTL" ]; then
	if grep -q '^net.ipv4.tcp_congestion_control=bbr' "$SYSCTL" 2>/dev/null; then
		echo "[tr3600-pure] sysctl 已經有 bbr，跳過"
	else
		cat >> "$SYSCTL" <<'EOS'

# ---- TR3600 pure build: 性能優化 ----
# BBR 擁塞控制 + fq 排程（低延遲、高吞吐，取代預設 cubic）
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
# 2.5G WAN 的 TCP 緩衝區（預設值在高頻寬 x 高延遲下會限制吞吐）
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 131072 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
EOS
		echo "[tr3600-pure] 已寫入 $SYSCTL"
	fi
else
	echo "[tr3600-pure] WARNING: $SYSCTL 不存在，改由 uci-defaults 於首次開機寫入"
	SYSCTL_FALLBACK=1
fi

# =========================================================
# 3. uci-defaults：語言 / 主題 / 硬體流量卸載
# =========================================================
THEME_UCI=package/base-files/files/etc/uci-defaults/99-tr3600-pure-defaults
mkdir -p "$(dirname "$THEME_UCI")"
cat > "$THEME_UCI" <<'EOS'
#!/bin/sh
# TR3600 pure build: 首次開機預設值 + 性能優化
# 這個檔案由 /etc/init.d/boot 執行一次，成功後會自我刪除。

# --- LuCI 預設語言 / 主題（OpenWrt 原生 bootstrap）---
uci -q set luci.main.lang='zh_cn'
uci -q set luci.main.theme='bootstrap'
uci -q commit luci

# --- 硬體流量卸載（HWNAT）---
# MediaTek filogic 的硬體 NAT：轉發幾乎不吃 CPU，2.5G 才跑得滿。
# 需要 kmod-mediatek_hnat + kmod-nf-flow（config 裡都有）。
# 若之後要用 SQM / 流量整形，記得把這兩項關掉。
uci -q set firewall.@defaults[0].flow_offloading='1'
uci -q set firewall.@defaults[0].flow_offloading_hw='1'
uci -q commit firewall

exit 0
EOS
chmod 0755 "$THEME_UCI"
echo "[tr3600-pure] installed $THEME_UCI"

# sysctl.conf 不存在時的備援：首次開機把設定寫進去並立即生效
if [ "${SYSCTL_FALLBACK:-0}" = "1" ]; then
	cat > "$THEME_UCI.sysctl" <<'EOS'
#!/bin/sh
if ! grep -q '^net.ipv4.tcp_congestion_control=bbr' /etc/sysctl.conf 2>/dev/null; then
	cat >> /etc/sysctl.conf <<'INNER'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 131072 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
INNER
fi
sysctl -q -w net.core.default_qdisc=fq 2>/dev/null || true
sysctl -q -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null || true
exit 0
EOS
	chmod 0755 "$THEME_UCI.sysctl"
	mv "$THEME_UCI.sysctl" "$(dirname "$THEME_UCI")/98-tr3600-pure-sysctl"
	echo "[tr3600-pure] installed 98-tr3600-pure-sysctl (sysctl.conf fallback)"
fi

# =========================================================
# 4. 板級 DTS 修正
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
# 4. 風扇溫控曲線：待機停轉，65/75/85 C 三段
#    標記用節點名而不是數值 —— 0007 會把數值改掉。
apply_dts_patch 0006-tr3600-fan-thermal-curve 'cpu_trip_active_low: active-low {'
# 5. 風扇曲線調校：拿掉無效的 25% 段，改成 50/78/100%，
#    整條曲線上移到 68/78/88 C，讓 64 C 的待機溫度真的落在停轉區
apply_dts_patch 0007-tr3600-fan-curve-tune    'cooling-levels = <0 128 200 255>;'

grep -qF 'pinctrl-0 = <&pwm_pins>;' "$DTS" || { echo "ERROR: pinctrl not fixed"; exit 1; }
grep -qF 'temperature = <68000>;' "$DTS"   || { echo "ERROR: fan curve 0007 did not land"; exit 1; }
echo "  OK: PWM0 fan / white+red LEDs / vendor MAC layout / 68-78-88 C fan curve"

# =========================================================
# 5. mt76 STA_REC / VoW 順序
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
echo " TR3600 pure build: part2 done (DTS + mt76 + 性能優化)"
echo "========================================================"
