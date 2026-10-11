# Cudy TR3600 v1 — OpenWrt 自建固件（GitHub Actions）

編譯 Cudy TR3600 v1（MT7987B + MT7990，Wi-Fi 7）的 OpenWrt 固件，
一次修好**風扇 / LED / WiFi MAC / 無線 STA_REC** 四個硬體描述問題。

- **建置 HEAD**：`046aec0dccd9`（2026-08-11，「mediatek: add support for Cudy TR3600 v1」），
  即當前固件版本來源（`DISTRIB_REVISION = r0-046aec0`）
- **基底**：`openwrt-25.12` + TR3600 v1 板級支援（上游 PR #24596，**尚未合併**）

## 兩條版本線

| | **iStore 版** | **純淨性能版** |
|---|---|---|
| Workflow | `Build Cudy TR3600 OpenWrt iStore Ajay` | `Build Cudy TR3600 OpenWrt Pure Ajay` |
| 設定檔 | `mt7987-cudy-tr3600-iStore.config` | `mt7987-cudy-tr3600-pure.config` |
| DIY | `diy-iStore-part1/2.sh` | `diy-pure-part1/2.sh` |
| 外掛 | iStore + 科學上網 / DNS / 工具類一大堆 | **只有 iStore + 智能風扇** |
| 主題 | Argon | **OpenWrt 原生 bootstrap** |
| Patch | 0001–0006 | 0001–**0007** |
| Tag | `Cudy-TR3600-iStore-Ajay-<時間>` | `Cudy-TR3600-Pure-Ajay-<時間>` |

純淨版另外做**性能優化**：`fq` + **BBR**、TCP 緩衝 16 MB、**HWNAT 硬體流量卸載**
（`flow_offloading` + `flow_offloading_hw`）、WED 無線卸載、zram。
兩條線的 Release 互相獨立，各自保留最近 10 個。

## 修了什麼

| Patch | 症狀 | 修法 |
|---|---|---|
| `0001-tr3600-fan-pwm0` | 風扇全速轉、LuCI 顯示「未檢測到」 | DTS 把 pwm-fan 從 PWM 通道 1 改回**通道 0**（硬體風扇實際接在 PWM0@PIN13） |
| `0002-mt76-mt7996-sta-rec-before-vow` | 改過 Wi-Fi MAC 過濾後客戶端再也連不上，**只有重開機能救** | mt76 `mt7996_mcu_add_sta()` 改成**先送 STA_REC 再送 VoW**（backport 上游 `da2c90d2`） |
| `0003-luci-tr3600-fan-keep-pending-input` | LuCI 風扇頁每 5 秒輪詢會蓋掉還沒按 Apply 的值 | 加 dirty flag（外觀，非致命） |
| `0004-tr3600-led-colours` | 狀態燈顏色與機身不符 | `led-0` = **白**@GPIO48、`led-1` = **紅**@GPIO46（上游誤標成 blue/white，**本板無藍燈**） |
| `0005-tr3600-wifi-mac-layout` | 2.4G / 5G 的 MAC 位址對不上 | 2.4 GHz = **base+0**（與 LAN 相同）、5 GHz = **base+0x10** |
| `0006-tr3600-fan-thermal-curve` | 待機時風扇持續低鳴 | 60 °C 以下**停轉**、65/75/85 °C 三段（上游 40 °C 就鎖 50 %） |
| `0007-tr3600-fan-curve-tune` | 0006 的 65 °C 那段是 25 % PWM，**實測完全沒有降溫效果**；本板待機剛好 64 °C，卡在門檻上 | 改成 **50 / 78 / 100 %**，曲線整條上移到 **68 / 78 / 88 °C**——待機真的停轉，要降溫時每一段都有用（**只給純淨版**） |

`diy-*-part1.sh` 另外把 `luci-app-tr3600-fan` 的腳本 `chmod 0755`
（上游 git 樹全是 100644，上機後 0644 → `exec_direct` EACCES → LuCI 空狀態）。

風扇插件已內建在本倉庫 `vendor/luci-app-tr3600-fan/`，兩個 `part1` 都以
`cp -a` 安裝，**不依賴任何第三方倉庫**（純淨版連「找不到就 clone 上游」的回退都沒有，
直接失敗——第三方倉庫已經消失過一次了）。

## 目錄結構

```
.
├── .github/workflows/
│   ├── build-openwrt-iStore-Ajay.yml   # iStore 版
│   └── build-openwrt-pure-Ajay.yml     # 純淨性能版
├── diy-iStore-part1.sh      # feeds 之前：裝插件源 + chmod + patch 0003
├── diy-iStore-part2.sh      # feeds 之後：套用 0001/0004/0005/0006 + 0002
├── diy-pure-part1.sh        # 純淨版：只裝風扇插件 + istore feed
├── diy-pure-part2.sh        # 純淨版：0001~0007 + 0002 + 性能優化
├── diy-partX.sh             # 關掉 Ruby YJIT，避免 Rust 長編譯
├── mt7987-cudy-tr3600-iStore.config                  # iStore 版設定檔
├── mt7987-cudy-tr3600-pure.config                    # 純淨版設定檔
├── patches/
│   ├── 0001-tr3600-fan-pwm0.patch
│   ├── 0002-mt76-mt7996-sta-rec-before-vow.patch
│   ├── 0003-luci-tr3600-fan-keep-pending-input.patch
│   ├── 0004-tr3600-led-colours.patch
│   ├── 0005-tr3600-wifi-mac-layout.patch
│   ├── 0006-tr3600-fan-thermal-curve.patch
│   └── 0007-tr3600-fan-curve-tune.patch
└── vendor/
    └── luci-app-tr3600-fan/  # 內建的風扇插件（10 個檔案）
```

`0006` 與 `0007` 動同一段 DTS，**順序不能顛倒**（0007 改的是 0006 放進去的值）。
`diy-pure-part2.sh` 對 0006 的偵測標記刻意用節點名 `cpu_trip_active_low: active-low {`
而不是 `cooling-levels` 的數值，否則 0007 改完之後會被誤判成「沒套用」。

## 刷機前必讀

> **不要刷 U-Boot。** 本機沒有可用的第三方 U-Boot（OpenWrt `uboot-mediatek` 無
> `cudy_tr3600`；`hanwckf/bl-mt798x` 只支援 MT7981/MT7986）。刷 U-Boot 會覆蓋
> `mtd0 BL2` + `mtd4 FIP`，等於**拆掉現有的救援網**。

刷機前先做**全分區備份**（唯讀、零風險，約 60 秒）——逐個 `mtd` 分區 `dd` 出來即可：

| 分區 | 內容 | 大小 |
|---|---|---|
| `mtd0` | BL2 | 1 MiB |
| `mtd1` | backup | 512 KiB |
| `mtd2` | Factory | 4 MiB |
| `mtd3` | bdinfo | 256 KiB |
| `mtd4` | FIP（ATF + U-Boot） | 2 MiB |
| `mtd5` | ubi（系統，slot A/B） | 232 MiB |

這台有 **A/B 雙開機槽** + `mtk-wdt` watchdog，sysupgrade 寫到另一個槽，
新固件開不起來會**自動回退舊槽**，所以刷機風險低。

## 參考

- 上游 PR #24596（TR3600 支援，base `openwrt-25.12`，**未合併**）：
  <https://github.com/openwrt/openwrt/pull/24596>

