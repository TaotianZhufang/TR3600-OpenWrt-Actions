#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-pure-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update Feeds)
#              純淨基礎 + 性能優化版 — 只裝 iStore 與 TR3600 智能風扇插件
#
# 這一版刻意「什麼都不 clone」：
#   * 沒有任何科學上網 / DNS / 主題 / 工具類第三方倉庫
#   * 唯一的套件來源是 feeds（OpenWrt 官方）+ vendor/（本倉庫內建風扇插件）
#
# 為什麼不 clone：
#   上游作者（liangcanming）名下倉庫在 2026-10 全部 404，build #1 就是死在
#   「git clone 一個已經消失的倉庫」。第三方倉庫隨時可能消失，clone 得越多
#   越脆弱。純淨版直接把這個風險歸零。
#
# 風扇插件內建在 vendor/luci-app-tr3600-fan/（與 MichaelJiangg/luci-app-tr3600-fan
# 逐位元組相同），並在複製後強制把三個進入點改成 0755 —— 上游 git tree 把
# 它們存成 100644，OpenWrt 用 $(CP) = "cp -fpR" 複製時會保留該權限，結果
# /usr/sbin/tr3600-fan 上機是 0644，fs.exec_direct() EACCES，LuCI 風扇頁
# 顯示「未檢測到風扇」。這正是本套件最原始要修的症狀。
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
	echo "[tr3600-pure] WARNING: no patches/ directory found near $SCRIPT_DIR"
fi
PATCHDIR="$REPO_ROOT/patches"

echo "========================================================"
echo " TR3600 pure build: diy-pure-part1.sh"
echo " repo root : $REPO_ROOT"
echo "========================================================"

mkdir -p package/custom

# =========================================================
# TR3600 風扇控制插件（內建，不依賴任何第三方倉庫）
# =========================================================
VENDOR_FAN="$REPO_ROOT/vendor/luci-app-tr3600-fan"
FANPKG="package/custom/luci-app-tr3600-fan"

rm -rf "$FANPKG"
if [ -d "$VENDOR_FAN" ]; then
	echo "[tr3600-pure] 使用內建風扇套件: $VENDOR_FAN"
	cp -a "$VENDOR_FAN" "$FANPKG"
else
	# 理論上不會走到這裡（vendor/ 就在倉庫裡）。真的沒有就硬失敗，
	# 不要偷偷去 clone 一個可能已經消失的第三方倉庫。
	echo "ERROR: $VENDOR_FAN 不存在，無法編入風扇插件（純淨版不做第三方 clone 回退）"
	exit 1
fi

# --- 讓風扇 helper 與 init script 可執行 ---
for f in "$FANPKG/root/usr/sbin/tr3600-fan" "$FANPKG/root/etc/init.d/tr3600-fan" "$FANPKG/root/etc/uci-defaults/99-tr3600-fan"; do
	if [ -f "$f" ]; then
		chmod 0755 "$f"
		echo "[tr3600-pure] chmod 0755 $f"
	else
		echo "ERROR: $f not found"
		exit 1
	fi
done
# Belt and braces: make sure a later re-checkout cannot silently drop the bit.
chmod 0755 "$FANPKG/Makefile" 2>/dev/null || true

# --- LuCI 風扇頁不得覆蓋使用者尚未送出的輸入 ---
# 純外觀問題（5 秒輪詢會把滑桿彈回）。非致命：打不上去就繼續，
# 編出來的固件只是滑桿會跳，功能不受影響。
P3="$PATCHDIR/0003-luci-tr3600-fan-keep-pending-input.patch"
if [ -f "$P3" ]; then
	if ( cd "$FANPKG" && patch -p1 --dry-run --forward -s < "$P3" >/dev/null 2>&1 ); then
		( cd "$FANPKG" && patch -p1 --forward -s < "$P3" )
		echo "[tr3600-pure] applied 0003-luci-tr3600-fan-keep-pending-input.patch"
	else
		echo "[tr3600-pure] WARNING: 0003 LuCI patch does not apply, continuing without it"
	fi
else
	echo "[tr3600-pure] WARNING: $P3 not found"
fi

# =========================================================
# iStore 應用商店 feed
# =========================================================
echo "src-git istore https://github.com/linkease/istore;main" >> feeds.conf.default

echo "========================================================"
echo " TR3600 pure build: part1 done (只裝了風扇插件 + istore feed)"
echo "========================================================"
