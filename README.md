# Cudy TR3600 v1 — OpenWrt 自建「穩固版」固件（GitHub Actions）

在 GitHub Actions 上免費編譯一版 Cudy TR3600 v1（MT7987B + MT7990，Wi-Fi 7）的
OpenWrt 固件，**一次修好風扇 / LED / WiFi MAC / 無線 STA_REC 四個問題**。

## 編譯基底

| 項目 | 值 |
|---|---|
| 原始碼 | `openwrt-25.12` + Cudy TR3600 v1 板级支援（自建編譯分支） |
| 建置時 HEAD | `046aec0dccd9`（2026-08-11，「mediatek: add support for Cudy TR3600 v1」） |
| 基底版本 | `openwrt-25.12` + TR3600 v1 裝置支援（上游 PR #24596，尚未合併） |

> 這個分支就是你**現用固件**的來源（`DISTRIB_REVISION = r0-046aec0`）。

## 這個版本修了什麼

| Patch | 症狀 | 修法 |
|---|---|---|
| `0001-tr3600-fan-pwm0` | 風扇全速轉、LuCI 顯示「未檢測到」 | DTS 把 pwm-fan 從 PWM 通道 1 改回**通道 0**（硬體風扇實際接在 PWM0@PIN13） |
| `0002-mt76-mt7996-sta-rec-before-vow` | 改過 Wi-Fi MAC 過濾後客戶端再也連不上，**只有重開機能救** | mt76 `mt7996_mcu_add_sta()` 改成**先送 STA_REC 再送 VoW**（backport 上游 `da2c90d2`） |
| `0003-luci-tr3600-fan-keep-pending-input` | LuCI 風扇頁每 5 秒輪詢會蓋掉還沒按 Apply 的值 | 加 dirty flag（外觀，非致命） |
| `0004-tr3600-led-colours` | 狀態燈顏色與機身不符 | `led-0` = **白**@GPIO48、`led-1` = **紅**@GPIO46（上游誤標成 blue/white，**本板無藍燈**） |
| `0005-tr3600-wifi-mac-layout` | 2.4G / 5G 的 MAC 位址對不上 | 2.4 GHz = **base+0**（與 LAN 相同）、5 GHz = **base+0x10** |
| `0006-tr3600-fan-thermal-curve` | 待機時風扇持續低鳴 | 60 °C 以下**停轉**、65/75/85 °C 三段（上游 40 °C 就鎖 50 %） |

`diy-iStore-part1.sh` 另外把 `luci-app-tr3600-fan` 的腳本 `chmod 0755`
（上游 git 樹全是 100644，上機後 0644 → `exec_direct` EACCES → LuCI 空狀態）。

## 風扇插件已內建（不依賴第三方倉庫）

原版是 `git clone https://github.com/liangcanming/luci-app-tr3600-fan.git`，
但 **2026-10 該帳號名下倉庫全部 404**（連 Actions 外殼倉庫 `Cudy-tr3600-v1-6.12`
也一起消失），build #1 因此死在：

```
fatal: could not read Username for 'https://github.com': No such device or address
```

所以整個套件改為**內建在本倉庫** `vendor/luci-app-tr3600-fan/`，
內容與 `MichaelJiangg/luci-app-tr3600-fan`（`tr3600-v1-fanfix-v2` 的作者，
也就是 patch 0003 撰寫時所依據的上游）**逐位元組相同**，
已用 SHA256 對 `TR3600-build-kit/reference/` 快照驗證：

```
tr3600-fan.js  ff39ef3e6175e161974bb97553ca20df0ce7b9c57937225fdb7a140fb488b43b
```

`diy-iStore-part1.sh` 直接 `cp -a vendor/luci-app-tr3600-fan → package/custom/`；
只有 `vendor/` 不存在時才回退去 clone GitHub。**第三方倉庫再消失也不影響編譯。**

## 目錄結構

```
.
├── .github/workflows/build-openwrt-iStore-Ajay.yml   # 唯一的 workflow
├── diy-iStore-part1.sh      # feeds 之前：裝插件源 + chmod + patch 0003
├── diy-iStore-part2.sh      # feeds 之後：套用 0001/0004/0005/0006 + 0002
├── diy-partX.sh             # 關掉 Ruby YJIT，避免 Rust 長編譯
├── mt7987-cudy-tr3600-iStore.config                  # OpenWrt 設定檔
├── patches/
│   ├── 0001-tr3600-fan-pwm0.patch
│   ├── 0002-mt76-mt7996-sta-rec-before-vow.patch
│   ├── 0003-luci-tr3600-fan-keep-pending-input.patch
│   ├── 0004-tr3600-led-colours.patch
│   ├── 0005-tr3600-wifi-mac-layout.patch
│   └── 0006-tr3600-fan-thermal-curve.patch
└── vendor/
    └── luci-app-tr3600-fan/  # 內建的風扇插件（10 個檔案）
```

`patches/` 和 `vendor/` **必須在倉庫根目錄**：`diy-iStore-part1.sh` /
`diy-iStore-part2.sh` 會先看自己所在目錄有沒有 `patches/`（本機直接執行），
沒有就往上一層找（Actions 會把腳本複製進 `openwrt/` 再跑），放錯會直接
`ERROR: ... does not apply` 中止。

## 怎麼跑

1. 進 **Actions** 分頁 → 左側 **Build Cudy TR3600 OpenWrt iStore Ajay**
2. 右側 **Run workflow** → branch 選 `main` → **Run workflow**
3. 等 **90–180 分鐘**（第一次要建 toolchain，最慢）

**兩個把關步驟**讓你在白等之前就知道有沒有問題：

- **Verify mt76 backport applies**（下載完套件後、編譯前）
  解開已下載的 mt76 原始碼、乾跑一次 patch；打不上去會**立刻失敗**。
- **Dump build evidence**（編譯成功後）
  把 DTS 的 pwm / LED / MAC / thermal 行、mt76 patch 清單、`PKG_SOURCE_VERSION`、
  實際編出的 `mt7996_mcu_add_sta()` 尾段存成 artifact，方便事後查帳。

`diy-iStore-part2.sh` 內部對 4 個 DTS patch 也做了 dry-run + 套用後複查，
任何一個不生效就 `exit 1`——**寧可中止，也不產出壞 image**。

## 拿固件

編譯成功後兩處可取：

- **Actions → 該次 run → Artifacts**：`Cudy-TR3600-iStore-Ajay-<時間>`
- **Releases**：workflow 會自動建 Release（只保留最近 10 個）

要的是 `*sysupgrade.bin`。

## 刷機前必讀

> **不要刷 U-Boot。** 本機沒有可用的第三方 U-Boot（OpenWrt `uboot-mediatek` 無
> `cudy_tr3600`；`hanwckf/bl-mt798x` 只支援 MT7981/MT7986）。刷 U-Boot 會覆蓋
> `mtd0 BL2` + `mtd4 FIP`，等於**拆掉現有的救援網**。

刷機前先做**全分區備份**（唯讀、零風險，約 60 秒）：

```bash
ROUTER=192.168.6.1 ./scripts/tr3600-mtd-backup.sh
```

這台有 **A/B 雙開機槽** + `mtk-wdt` watchdog，sysupgrade 寫到另一個槽，
新固件開不起來會**自動回退舊槽**，所以刷機風險低。

## 參考

- 上游 PR #24596（TR3600 支援，base `openwrt-25.12`，**未合併**）：
  <https://github.com/openwrt/openwrt/pull/24596>
- mt76 修復 commit `da2c90d2`（2026-07-29, Felix Fietkau）
- 風扇插件（已內建於 `vendor/`）：<https://github.com/MichaelJiangg/luci-app-tr3600-fan>
  （原出處 `liangcanming/luci-app-tr3600-fan` 已 404）
