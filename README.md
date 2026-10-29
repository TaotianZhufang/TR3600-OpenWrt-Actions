# TR3600-Unclamp 1.0

Cudy TR3600 v1（MT7987B + MT7990，Wi-Fi 7 双频 BE3600）的 OpenWrt 自建固件，基于 GitHub Actions 构建。

> **Unclamp / 解钳**：修掉 MT7990 把 AP 发送速率钳制在 6 Mbit/s、导致下行掉到约 80 Mbps 的问题。

## 版本信息

| 项 | 值 |
|---|---|
| 固件名 | **TR3600-Unclamp 1.0** |
| 固件标识 | `DISTRIB_DESCRIPTION="TR3600-Unclamp 1.0 r0-046aec0"` |
| 构建基底 | `openwrt-25.12` + Cudy TR3600 v1 板级支持（上游 PR #24596，尚未合入） |
| 源码 HEAD | `soapmancn/openwrt` @ `agent/cudy-tr3600-v1-6.12`（钉在 `046aec0d`） |
| 内核 | 6.12.94 |
| mt76 | 2026.03.19（`39c960c3`） |
| 默认 LAN | **192.168.1.1/24**，DHCP 池 192.168.1.100-249 |
| 默认密码 | **无**（root 空密码，请首次登录后立即设置） |

## 这一版修了什么

### 核心修复

- **MT7990 SDO TX 路径**（`patches/0300-mt7996-mt7990-host-fill-txd.patch`）
  固件用 SDO 为 802.3 单播帧填写 TXD，在 MT7990 上该路径损坏，速率字段被写坏，
  AP 发送被钳在 6 Mbit/s。补丁让 MT7990 一律由 host 填充 TXD，绕过该路径。
  来源：kyoto44（openwrt/mt76 issue #1043），visualphoenix/beryl7 打包。
- **STA_REC 顺序**（`patches/0002`）：改为先发 STA_REC、后发 VoW/DRR，
  修掉 `wifi down/up` 或改无线配置后客户端再也连不上的问题。

### 板级修正

- 风扇 PWM 通道 1 → 0（`0001`），风扇可测可调；曲线设为 68/78/88°C 三段
- LED：`led-0` 白 @GPIO48、`led-1` 红 @GPIO46（`0004`，本板无蓝灯）
- WiFi MAC：2.4G = base+0x00、5G = base+0x10（`0005`）
- 风扇温控曲线与调校（`0006`、`0007`）
- LuCI 风扇页 dirty flag 修复（`0003`）

## 内置软件

| 类别 | 内容 |
|---|---|
| 风扇 | TR3600 智能风扇（`vendor/`，不依赖第三方仓库） |
| VPN / 组网 | ZeroTier、Tailscale、WireGuard、OpenVPN |
| DNS | mosdns、DDNS（`luci-app-ddns`）、ddns-go |
| 下载 | aria2 |
| 共享 | Samba4、WebDAV |
| USB | 存储（ext4/exfat/ntfs3 + block-mount）、约 11 种网卡芯片、手机共享（RNDIS/NCM/EEM）、WWAN（QMI/MBIM）、USB 串口 |
| 工具 | **ttyd 网页终端**、**USB 管理页**（状态→USB 状态；系统→USB 管理）、usbutils(lsusb)、pciutils(lspci)、ethtool、iperf3、tcpdump |
| 无线 | `wpad-mbedtls`（802.11r/k/v 快速漫游 + WPS） |

### 为控制体积而移除

设备 `rootfs` 卷只有 **59.9 MB**，可用空间仅 2.5 MB，因此本版：

- **未内置 PassWall2 / Xray / v2ray-geoip / v2ray-geosite / v2ray-plugin / geoview**
  （未压缩约 90 MB，压缩后约 25 MB）。需要代理可自行 `apk` 安装，或改用 OpenClash 方案。
- 未内置 iStore、SSR+、smartdns、第三方主题（Argon/Aurora/Kucat）、filemanager、authshield。

## 在线升级保护（重要）

本固件的内核 6.12.94、mt76 39c960c3 与板级补丁是同一批编译的配套，**不要在线升级**：

- `apk upgrade`、LuCI「软件包」页的升级、iStore 更新都可能把 kmod 换成与内核不匹配的版本，
  或把 mt76 换成没有 host-fill 修复的版本（MT7990 下行会回落到约 80 Mbps）；
- 一般 `apk add`（非内核相关包）不受影响；
- 安装 `kmod-*`、`kernel*`、`base-files`、`mt76*`、`wpad*` 会被拦截。

已内置两道锁：

| 锁 | 位置 | 作用 |
|---|---|---|
| apk 包装器 | `/usr/sbin/apk` | 拦截 `upgrade` / `fix` 与系统包安装 |
| LuCI 后端 | `/usr/libexec/package-manager-call` | 拦截软件包页的升级与系统包安装 |

确需解锁：`touch /etc/apk-allow-unsafe`（自担风险）。安全升级方式：**整包重编 + sysupgrade**。

## 性能优化

由 `/etc/sysctl.d/99-tr3600-pure.conf` 交付（不是 `/etc/sysctl.conf`，那是 conffile 会被 sysupgrade 保留）：

- BBR + fq（`tcp_congestion_control=bbr`、`default_qdisc=fq`）
- TCP 缓冲上限 16 MB
- 硬件流量卸载（HWNAT：`flow_offloading` + `flow_offloading_hw`）
- zram 压缩内存

## 构建（GitHub Actions）

1. fork 本仓库（或直接使用）
2. Actions → **Build TR3600-Unclamp (Cudy TR3600 v1)** → Run workflow
3. 约 1.5~3 小时，产物在 Release / Artifacts

关键日志（都出现才算走对）：

```
✅ MT7990 host-fill TXD 可正常套用
installed: 0300-mt7996-mt7990-host-fill-txd.patch
[tr3600-unclamp] chmod +x files/etc/uci-defaults/99-tr3600-network
✅ 必需包齐全
```

## 刷机

只刷 `openwrt-mediatek-filogic-cudy_tr3600-v1-squashfs-sysupgrade.bin`。

```bash
scp openwrt-mediatek-filogic-cudy_tr3600-v1-squashfs-sysupgrade.bin root@192.168.1.1:/tmp/fw.bin
ssh root@192.168.1.1 "sha256sum /tmp/fw.bin"      # 与 release 的 sha256sums 比对
ssh root@192.168.1.1 "sysupgrade -n /tmp/fw.bin"  # -n：不保留配置
```

⚠️ 刷前确认 `root` 分区大小 < 59.9 MB（本版目标约 40 MB）。

救砖：TFTP（电脑 192.168.1.88/24，路由 192.168.1.112，端口 3777，按住 reset 8~10 秒）。

## 目录

```
patches/            板级补丁 0001-0007 + mt76 补丁 0002 / 0300
files/              rootfs overlay（默认网段、USB 管理页、apk 源、sysctl）
vendor/             内置 LuCI 风扇插件
diy-pure-part1.sh   复制 files/、加第三方 feed
diy-pure-part2.sh   打补丁、装风扇插件、设置默认值
mt7987-cudy-tr3600-pure.config   构建配置
NOTICE.md           来源与许可说明
```

## 许可

见 [NOTICE.md](NOTICE.md)：OpenWrt 本体 GPL-2.0；mt76 补丁为 GPL 派生；构建脚本与 USB 页面来自未声明许可的上游仓库，个人使用无碍，公开发布前请保留署名与来源链接。