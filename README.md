# Cudy TR3600 v1 — OpenWrt 自建固件（GitHub Actions）

編譯 Cudy TR3600 v1（MT7987B + MT7990，Wi-Fi 7）的 OpenWrt 固件，
一次修好**風扇 / LED / WiFi MAC / 無線 STA_REC** 四個硬體描述問題。

- **建置 HEAD**：`046aec0dccd9`（2026-08-11，「mediatek: add support for Cudy TR3600 v1」），
  即當前固件版本來源（`DISTRIB_REVISION = r0-046aec0`）
- **基底**：`openwrt-25.12` + TR3600 v1 板級支援（上游 PR #24596，**尚未合併**）

## 版本線

**2026-10-13 起只剩一條線。** iStore 版（`build-openwrt-iStore.yml`）已退休，
連同 iStore 應用商店本身（`luci-app-store` + `linkease/istore` feed）一起移除，
第三方主題（Argon / Aurora / Kucat）也一併清掉。

| | **精簡性能版** |
|---|---|
| Workflow | `Build Cudy TR3600 OpenWrt Pure` |
| 設定檔 | `mt7987-cudy-tr3600-pure.config` |
| DIY | `diy-pure-part1/2.sh` |
| 外掛 | **只有 TR3600 智能風扇** |
| 主題 | **OpenWrt 原生 bootstrap** |
| Patch | 0001–**0008** |
| Tag | `Cudy-TR3600-Pure-<時間>` |

另外做**性能優化**：`fq` + **BBR**、TCP 緩衝 16 MB、**HWNAT 硬體流量卸載**
（`flow_offloading` + `flow_offloading_hw`）、WED 無線卸載、zram。
Release 保留最近 10 個。

## 修了什麼

| Patch | 症狀 | 修法 |
|---|---|---|
| `0001-tr3600-fan-pwm0` | 風扇全速轉、LuCI 顯示「未檢測到」 | DTS 把 pwm-fan 從 PWM 通道 1 改回**通道 0**（硬體風扇實際接在 PWM0@PIN13） |
| `0002-mt76-mt7996-sta-rec-before-vow` | 改過 Wi-Fi MAC 過濾後客戶端再也連不上，**只有重開機能救** | mt76 `mt7996_mcu_add_sta()` 改成**先送 STA_REC 再送 VoW**（backport 上游 `da2c90d2`） |
| `0003-luci-tr3600-fan-keep-pending-input` | LuCI 風扇頁每 5 秒輪詢會蓋掉還沒按 Apply 的值 | 加 dirty flag（外觀，非致命） |
| `0004-tr3600-led-colours` | 狀態燈顏色與機身不符 | `led-0` = **白**@GPIO48、`led-1` = **紅**@GPIO46（上游誤標成 blue/white，**本板無藍燈**） |
| `0005-tr3600-wifi-mac-layout` | 2.4G / 5G 的 MAC 位址對不上 | 2.4 GHz = **base+0**（與 LAN 相同）、5 GHz = **base+0x10** |
| `0006-tr3600-fan-thermal-curve` | 待機時風扇持續低鳴 | 60 °C 以下**停轉**、65/75/85 °C 三段（上游 40 °C 就鎖 50 %） |
| `0007-tr3600-fan-curve-tune` | 0006 的 65 °C 那段是 25 % PWM，**實測完全沒有降溫效果**；本板待機剛好 64 °C，卡在門檻上 | 改成 **50 / 78 / 100 %**，曲線整條上移到 **68 / 78 / 88 °C**——待機真的停轉，要降溫時每一段都有用 |
| `0008-luci-tr3600-fan-smart-suggestions` | 風扇頁只有「固定曲線」與「手動」兩檔，換季得自己記得改 | 加**智能季節建議**：三檔曲線（winter `68/78/88`、mild `66/76/86`、summer `58/68/78`），頁面顯示**待機基準**與**建議方案＋理由**，可一鍵套用或手動覆寫季節 |

`diy-pure-part1.sh` 另外把 `luci-app-tr3600-fan` 的腳本 `chmod 0755`
（上游 git 樹全是 100644，上機後 0644 → `exec_direct` EACCES → LuCI 空狀態）。

風扇插件已內建在本倉庫 `vendor/luci-app-tr3600-fan/`，`diy-pure-part1.sh` 以
`cp -a` 安裝，**不依賴任何第三方倉庫**（連「找不到就 clone 上游」的回退都沒有，
直接失敗——第三方倉庫已經消失過一次了）。

## 目錄結構

```
.
├── .github/workflows/
│   └── build-openwrt-pure.yml          # 唯一的建置線（精簡性能版）
├── diy-pure-part1.sh        # feeds 之前：裝風扇插件 + 0003 + 0008
├── diy-pure-part2.sh        # feeds 之後：0001~0007 + 0002 + 性能優化
├── diy-partX.sh             # 關掉 Ruby YJIT，避免 Rust 長編譯
├── mt7987-cudy-tr3600-pure.config                    # 設定檔
├── patches/
│   ├── 0001-tr3600-fan-pwm0.patch
│   ├── 0002-mt76-mt7996-sta-rec-before-vow.patch
│   ├── 0003-luci-tr3600-fan-keep-pending-input.patch
│   ├── 0004-tr3600-led-colours.patch
│   ├── 0005-tr3600-wifi-mac-layout.patch
│   ├── 0006-tr3600-fan-thermal-curve.patch
│   ├── 0007-tr3600-fan-curve-tune.patch
│   └── 0008-luci-tr3600-fan-smart-suggestions.patch
└── vendor/
    └── luci-app-tr3600-fan/  # 內建的風扇插件（10 個檔案）
```

`0006` 與 `0007` 動同一段 DTS，**順序不能顛倒**（0007 改的是 0006 放進去的值）。
`diy-pure-part2.sh` 對 0006 的偵測標記刻意用節點名 `cpu_trip_active_low: active-low {`
而不是 `cooling-levels` 的數值，否則 0007 改完之後會被誤判成「沒套用」。

`0003` 與 `0008` 動同一個 LuCI 檔案，**0003 必須先套而且必須成功**：0008 的
hunk 用 0003 加進去的 `dirty` 旗標那幾行當 context。實測顛倒順序 → 7 個 hunk 有 3 個
FAILED，留下 `.rej` 與半套的風扇頁。所以 `part1` 改成**硬失敗**
（不再「打不上去就繼續」），並且加 `-F 0` 關掉 fuzz——預設 fuzz=2 會讓 patch 在
上游漂移時「模糊命中」照樣回 rc=0。

## 風扇頁的智能季節建議

風扇頁（**系統 → TR3600 風扇控制**）現在有三種模式：

| 模式 | 行為 |
|---|---|
| **內核自動溫控** | `step_wise` governor + DTS 曲線（預設，等同刷機前的行為） |
| **智能季節溫控** | daemon 依季節曲線自己決定轉速（見下） |
| **手動轉速** | 固定 0–3 檔 |

三檔季節曲線（第一段都是 50 % PWM，停轉門檻 = 第一段 −5 °C hysteresis）：

| 季節 | 起轉 / 中速 / 全速 | 什麼時候用 |
|---|---|---|
| winter | 68 / 78 / 88 °C | 本板待機 ~64 °C → **待機完全停轉**，有負載才轉 |
| mild | 66 / 76 / 86 °C | 室溫再高一點 |
| summer | 58 / 68 / 78 °C | 夏天，**會一直吹**，主動把溫度壓下來 |

**季節不是用即時溫度判斷的。** 有負載時溫度一定往上跑，用溫度自動切換會在
「路由器一忙就換季」之間來回跳。所以：**日曆**決定季節（6–8 月 summer、
12–2 月 winter、其餘 mild），而頁面上的**待機基準**（風扇停轉時的最低溫，
本身已經帶有室溫資訊）只用來**建議**，由人決定要不要套用。

- 現在是低溫天氣 → 待機基準讀到約 64 °C → 建議 **winter**（和現在的曲線一致，不用改）
- 到了夏天 → 日曆自動切到 **summer**，不用手動動任何設定

`mild` 的第一段刻意只比 winter 低 2 °C：本板風扇停轉時量到 **64.1 °C**，
門檻一旦低於這個值，風扇就會起轉而且**永遠降不回停轉點**——正是 0006/0007 要消滅的
「待機低鳴」。改動這幾個數字時，**每一檔的第一段都必須高於實測的停轉待機溫**。

設定檔在 `/etc/config/tr3600-fan`（`mode` / `level` / `season`），預設 `mode 'auto'`、
`season 'auto'`，**出廠行為與刷機前完全一致**，智能模式在頁面上按一下就到。
指令列：`/usr/sbin/tr3600-fan set smart`、`set season summer`、`get`。

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

