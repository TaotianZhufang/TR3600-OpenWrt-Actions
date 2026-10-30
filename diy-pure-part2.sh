#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-pure-part2.sh
# Description: OpenWrt DIY script part 2 (After Update Feeds)
#              純淨基礎 + 性能優化版
#
# 這個腳本做三件事：
#   1. 預設 IP / 語言 / 主題（Argon 3.1.1，vendor 內建）
#   2. 板級 DTS 修正 0001 / 0004 / 0005 / 0006 / 0007（風扇 + LED + WiFi MAC）
#   3. mt76 backport 0002（STA_REC 先於 VoW，修 wifi down/up 後連不上）
#   ＋ uci-defaults 兜底（語言 / 主題 / HWNAT 硬體流量卸載）
#
# 註：sysctl 性能調校（fq + BBR、TCP 16 MB 緩衝區、conntrack）**已經不在這裡**。
#     以前 append 到 package/base-files/files/etc/sysctl.conf，但那個檔案是 conffile，
#     被 /lib/upgrade/keep.d/base-files-essential 保留 → sysupgrade 後舊機上的檔案
#     會蓋掉新映像的版本，調校等於永遠不生效（實測 rmem_max 一直停在 208 KB）。
#     現在改由倉庫的 files/etc/sysctl.d/99-tr3600-pure.conf 交付（files/ 是 rootfs
#     overlay，而 /etc/sysctl.d/ 不被 sysupgrade 保留）。見 diy-pure-part1.sh。
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
# 0b. 跨 feed 重名去重：2026-10-30 随 iStore 一起移除
#     （luci-app-store / taskd / xterm 不再进镜像，不需要处理重名）
# =========================================================

# =========================================================
# 0a. 移除 feed 里的同名 Argon 主题（我们用 vendor 版本）
#     kenzok8 feed 也带 luci-theme-argon；feeds install -a 会把它 link 进
#     package/feeds/，与 package/custom/luci-theme-argon 重名 → 构建直接报
#     duplicate package。这里在编译前删掉 feed 的那份。
# =========================================================
for d in package/feeds/*/luci-theme-argon; do
	if [ -e "$d" ]; then
		rm -rf "$d"
		echo "[tr3600] 已移除 feed 同名主题: $d"
	fi
done
# =========================================================
# 0. 確保 files/ overlay 內的可執行檔有 +x
#    （用 GitHub 網頁上傳時 git 會丟掉執行位，uci-defaults 不執行就白搭）
# =========================================================
for f in files/etc/uci-defaults/99-tr3600-network files/usr/libexec/rpcd/tr3600.usb \
         files/usr/libexec/rpcd/homebox files/usr/bin/homebox files/etc/init.d/homebox \
         files/usr/libexec/rpcd/minieap files/usr/sbin/minieap files/etc/init.d/minieap \
         files/usr/sbin/tr3600-ipv6 files/etc/uci-defaults/90-tr3600-homebox \
         files/etc/uci-defaults/91-tr3600-minieap \
         files/usr/bin/bandix files/etc/init.d/bandix files/usr/libexec/rpcd/luci.bandix; do
	if [ -f "$f" ]; then
		chmod 0755 "$f" && echo "[tr3600] chmod +x $f"
	else
		echo "ERROR: $f 不存在（files/ overlay 沒進來？）"; exit 1
	fi
done
# minieap.conf 可能含账号密码
[ -f files/etc/minieap.conf ] && chmod 0600 files/etc/minieap.conf

# =========================================================
# 1. 預設 IP / 語言 / 主題
# =========================================================

# Cudy TR3600 v1：預設 LAN 維持 192.168.1.1/24（DHCP 池由
# files/etc/uci-defaults/99-tr3600-network 在首啟時兜底設定）
if grep -q '192.168.6.1' package/base-files/files/bin/config_generate 2>/dev/null; then
	sed -i 's/192.168.6.1/192.168.1.1/g' package/base-files/files/bin/config_generate
fi

# 主題：Argon 3.1.1（vendor 內建）。
# config 裡已經有 CONFIG_DEFAULT_THEME=Argon + CONFIG_PACKAGE_default-settings，
# 這裡再放一份 uci-defaults 兜底。注意 openwrt-25.12 的 base-files 已經沒有
# etc/config/luci，對它 sed 會在 `set -e` 下直接打死編譯，所以一定要先判斷。
LUCI_CFG=package/base-files/files/etc/config/luci
if [ -f "$LUCI_CFG" ]; then
	sed -i 's/luci.main.theme=bootstrap/luci.main.theme=Argon/' "$LUCI_CFG"
	echo "[tr3600-pure] patched $LUCI_CFG -> Argon"
else
	echo "[tr3600-pure] $LUCI_CFG 不存在（openwrt-25.12 已移除），改用 uci-defaults"
fi

# =========================================================
# 2. 性能優化（sysctl）—— 已搬到 files/etc/sysctl.d/99-tr3600-pure.conf
# =========================================================
# 這裡以前會 append 到 package/base-files/files/etc/sysctl.conf。
# 那個做法有兩個問題，所以整段拿掉了：
#   1. /etc/sysctl.conf 是 conffile，被 sysupgrade 保留 → 新映像的版本被舊檔蓋掉。
#   2. /etc/init.d/sysctl 讀取順序是 sysctl.d/*.conf 先、sysctl.conf 後，
#      所以 sysctl.conf 反而會覆蓋 sysctl.d。
# 現在統一由 files/ overlay 交付（files/ 由 include/image.mk 的 prepare_rootfs
# 蓋進 rootfs；/etc/sysctl.d/ 不被保留 → 永遠用新映像的）。
# files/ 的複製與守門在 diy-pure-part1.sh。

# =========================================================
# 3. uci-defaults：語言 / 主題 / 硬體流量卸載
# =========================================================
# zz- 前缀：确保最后执行 —— 万一上游 default-settings 也写 luci.main.mediaurlbase，
# 我们的选择必须赢。
THEME_UCI=package/base-files/files/etc/uci-defaults/zz-tr3600-pure-defaults
mkdir -p "$(dirname "$THEME_UCI")"
cat > "$THEME_UCI" <<'EOS'
#!/bin/sh
# TR3600 pure build: 首次開機預設值 + 性能優化
# 這個檔案由 /etc/init.d/boot 執行一次，成功後會自我刪除。

# --- LuCI 預設語言 / 主題（Argon 3.1.1）---
uci -q set luci.main.lang='zh_cn'
# ⚠️ luci-base 25.12 的 dispatcher 只認 mediaurlbase，主題名 = basename(mediaurlbase)：
#      let media = uci.get('luci','main','mediaurlbase');
#      trycompile('themes/' + basename(media) + '/header')
#   它**不讀** luci.main.theme（實查 luci-base 的 ucode）。所以要切主題必須寫
#   mediaurlbase；theme 只是給舊版/其他工具看的，一起寫不衝突。
#   兜底：Argon 沒進 rootfs 就回 bootstrap —— 否則 mediaurlbase 指向不存在的
#   模板，LuCI 得靠 luci.themes 的 fallback 才救得回來。
if [ -f /www/luci-static/argon/css/cascade.css ]; then
	uci -q set luci.main.theme='Argon'
	uci -q set luci.main.mediaurlbase='/luci-static/argon'
else
	uci -q set luci.main.theme='bootstrap'
	uci -q set luci.main.mediaurlbase='/luci-static/bootstrap'
fi
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

# 5b. MT7990 host-fill TXD（修 AP->client 速率被钳在 6 Mbps）
P3="$PATCHDIR/0300-mt7996-mt7990-host-fill-txd.patch"
if [ ! -f "$P3" ]; then
	echo "ERROR: $P3 not found"
	exit 1
fi
cp "$P3" "$MT76PATCHDIR/0300-mt7996-mt7990-host-fill-txd.patch"
echo "  installed: $(basename "$MT76PATCHDIR"/0300-*.patch)"

# =========================================================
# 5c. 固件标识：保持 OpenWrt 默认
#     以前这里把 VERSION_DIST 覆盖成自定义名，副作用：
#       - 镜像前缀不再以 openwrt- 开头；
#       - DISTRIB_DESCRIPTION 出现重复的版本号（"… 1.0 1.0"）。
#     现在不碰 version.mk：镜像仍是 openwrt-…，系统标识是 OpenWrt 25.12-SNAPSHOT，
#     构建时间只出现在 Release tag / 文件名之外的元数据里。
# =========================================================

echo "========================================================"
echo " TR3600 build: part2 done (DTS + mt76 + 性能优化)"
echo "========================================================"
