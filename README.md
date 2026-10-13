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
| 外掛 | **只有 TR3600 智能風扇**（LuCI 模組名就叫「智能風扇」，中英文模式一致） |
| 主題 | **OpenWrt 原生 bootstrap** |
| Patch | 0001–**0007**（0008 已下線） |
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

> ⚠️ **0007 才是最終值**：`cooling-levels = 0 128 200 255`、trip `68000 / 78000 / 88000`。
> 拿 0006 的 `0 64 160 255` / 65000 去比，會誤判成「patch 沒生效」。

`0008-luci-tr3600-fan-smart-suggestions`（風扇頁智能季節建議）已於 **2026-10-13 下線**：
那三條季節曲線 + 日曆 + 待機基準，全是內核 `step_wise` 的**第二次實作**，只多一層會壞的
東西。補丁留在 build kit 的 `retired/patches/`，**本倉庫不含**。

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
├── diy-pure-part1.sh        # feeds 之前：裝風扇插件 + 0003
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
│   └── 0007-tr3600-fan-curve-tune.patch
└── vendor/
    └── luci-app-tr3600-fan/  # 內建的風扇插件（10 個檔案）
```

`0006` 與 `0007` 動同一段 DTS，**順序不能顛倒**（0007 改的是 0006 放進去的值）。
`diy-pure-part2.sh` 對 0006 的偵測標記刻意用節點名 `cpu_trip_active_low: active-low {`
而不是 `cooling-levels` 的數值，否則 0007 改完之後會被誤判成「沒套用」。

`0003` 是唯一動 LuCI 風扇頁的補丁（0008 下線後），**必須套而且必須成功**。
`part1` 對它是**硬失敗**（不再「打不上去就繼續」），並且加 `-F 0` 關掉 fuzz——
預設 fuzz=2 會讓 patch 在上游漂移時「模糊命中」照樣回 rc=0。

## 風扇控制：只有 auto / manual

風扇頁（**系統 → 智能風扇**）只有兩種模式：

| 模式 | 行為 |
|---|---|
| **自動**（預設） | 交給內核 `step_wise` governor，按板級 DTS 曲線調速 |
| **手動** | 固定 0–3 檔；100 °C 會被強制拉滿，110 °C 交還自動（保命線） |

DTS 曲線（patch 0006 + **0007**，**0007 才是最終值**）：

| trip | PWM 檔位 |
|---|---|
| 68 °C | 50 % |
| 78 °C | 78 % |
| 88 °C | 100 % |
| < 68 °C | 停轉 |

實測（**無線關閉**）：待機約 **59 °C**；4 核 `yes` 滿載 100 秒只爬到 **66 °C**。
兩個都還在 68 °C 第一段之下，所以**這條曲線實務上風扇幾乎不會轉**（無線開著會再
高一些）。要讓風扇真的參與散熱就得把第一段往下調，但那就是待機噪音的取捨。

設定檔在 `/etc/config/tr3600-fan`（只有 `mode` / `level`），預設 `mode 'auto'`。
指令列：`/usr/sbin/tr3600-fan set auto`、`set manual 0-3`、`get`。

### `set auto` 會清掉手動模式留下的檔位（2026-10-13 修）

內核 `step_wise` governor **只在 trip 跨越門檻時才會動作**。實測：
把 `trip_point_N_temp` 改一下（造成一次跨越）風扇會立刻反應；溫度穩定停在
trip 之下時，governor 完全不會被叫到。

所以手動模式（走 `user_space`）留下的 `cur_state`，在溫度已經落回所有 trip 之下
時不會被清掉——沒有跨越事件——風扇就一直停在手動檔位，正是「待機低鳴」。

重現：`set manual 1` 之後 `set auto`，SoC 59 °C（比第一個 trip 低 9 °C），
風扇在檔位 1 卡住 60 秒不動。

修法：`set_auto` 切回 `step_wise` 之後，**只在溫度低於最低的 active trip 時**
明確把 `cur_state` 歸零。這個條件下關風扇一定正確；門檻是從
`/sys/class/thermal/thermal_zone0/trip_point_*_temp` 讀的，不是把曲線再寫一份在
用戶態（所以沒有 0008 那種漂移問題）。溫度在 trip 之上時完全不動它——
**永遠不會在高溫時降轉速**。

### ⚠️ 0008「智能季節建議」已於 2026-10-13 下線

它曾經加上第三種模式 `smart`、三條季節曲線（winter 68/78/88、mild 66/76/86、
summer 58/68/78）、日曆判斷、待機基準建議與季節覆寫。

**拿掉的理由：那些全是內核 `step_wise` 已經在做的事的第二次實作。**
DTS 的 trip 點本來就會驅動風扇，用戶態每 10 秒再用 shell 重算一遍同樣的曲線，
只是多一層會壞的東西——它得自己維護 hysteresis、自己的待機基準啟發式、一套日曆，
而且會跟 DTS 的數值漂移（mild 用 66/76/86，DTS 是 68/78/88）。拿掉之後風扇行為
不變，可壞的東西少一大半，UI 回到一眼看得懂。

- 補丁留在 build kit 的 `retired/patches/0008-…`（**本倉庫不含，也不再套用**）
- 編譯守門改成**反向斷言**：`season_trips` / `set_smart` / `SEASON_TRIPS` /
  `Smart suggestion` / `option season` 只要出現在固件裡就 `exit 1`

## 模組名：智能風扇

LuCI 選單與頁面標題都是 **智能風扇**，**中英文模式都一樣**。

做法是讓 menu.d 的 `title` 與頁面 `h2` 用同一個字面量，`po/zh_Hans` 裡也放同名條目
（`msgid == msgstr`）。中文模式查到條目回傳自身；英文模式沒有 en 目錄，回退到 msgid
也是自身——兩邊都穩定顯示「智能風扇」，不會退回 `TR3600 Fan Control`。編譯守門會斷言這件事。

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

