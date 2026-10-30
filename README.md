# Cudy TR3600 v1 OpenWrt

Cudy TR3600 v1（MT7987B + MT7990）的 OpenWrt 25.12 自编译固件，GitHub Actions 构建。

## 版本

| 项 | 值 |
|---|---|
| 系统 | OpenWrt 25.12-SNAPSHOT（r0-046aec0） |
| 内核 | 6.12.94 |
| mt76 | 39c960c3 |
| 默认 LAN | 192.168.1.1/24，DHCP 100–249 |
| root 密码 | 无，首次登录后设置 |

## 修复

- **MT7990 下行**：SDO TX 路径在 MT7990 上损坏，AP→客户端被压在 6 Mbit/s（约 80 Mbps）。改为由 host 填充 TXD 绕过，实测 160 MHz 下行约 1.0 Gbps、上行约 1.6 Gbps。
- **wifi reload 后连不上**：mt76 改为先发 STA_REC、再发 VoW/DRR。
- **板级**：风扇 PWM0、LED 白/红、2.4G/5G MAC 布局、风扇曲线 68/78/88 °C。

## 包含

Argon 3.1.1 主题；USB 存储/网卡/Android 共享/5G 模块/串口；
ZeroTier、Tailscale、WireGuard、OpenVPN、mosdns、ddns-go、DDNS、aria2、Samba4、WebDAV；
ttyd、USB 管理页、HomeBox 测速、nlbwmon、vnstat2、wifihistory、UPnP、WOL、usteer、TravelMate、minieap、usbmuxd、smartmontools、iperf3、tcpdump。

未内置：PassWall2/Xray、OpenClash、iStore、smartdns。

## 刷机

```sh
scp openwrt-mediatek-filogic-cudy_tr3600-v1-squashfs-sysupgrade.bin root@192.168.1.1:/tmp/fw.bin
ssh root@192.168.1.1 'sysupgrade -n /tmp/fw.bin'
```

或在 LuCI → 系统 → 备份/刷写固件里刷，取消「保留配置」。

首次启动：设 root 密码；5G 不启动时设国家码：

```sh
uci set wireless.@wifi-device[1].country='CN'
uci commit wireless && wifi reload
```

MT7990 只有一个 wiphy：2.4G 是 `phy0.0-ap0`，5G 是 `phy0.1-ap0`；`ls /sys/class/ieee80211` 只有 `phy0` 是正常的。

## USB 网络共享

1. 手机开启 USB 网络共享，确认 `ip -br link` 里有 `usb0`（或 `eth2`）；iPhone 已带 usbmuxd，插上后点信任即可；
2. LuCI → 系统 → USB 管理 → 选设备 → 启用。默认 metric 200，有线 WAN 优先；
3. 页面不可用时用命令行：

```sh
ubus call tr3600.usb status
ubus call tr3600.usb configure '{"device":"usb0","metric":"200"}'
```

`usbwan` 绑定的是接口名，换设备或加 USB 分线器时可能被占用，先到「网络 → 接口」里解绑。

## 设备管理

- **MAC-IP 绑定**：网络 → DHCP/DNS → 静态租约。
- **流量统计**：状态 → 流量统计（nlbwmon）；状态 → Wi-Fi 历史（wifihistory）。
- **限速**：官方没有按设备限速的图形页，本固件也不带 qos-scripts（全局策略、依赖 iptables，和 HWNAT 冲突）。需要按 IP 限速时用 tc 规则，或告诉我单独加。
- **UPnP / WOL / 定时 Wi-Fi / 唤醒**：服务与网络菜单里的对应页面。

## 关闭 IPv6

LuCI：网络 → 接口 → LAN → 编辑 → DHCP 服务器 → IPv6 设置，把 RA、DHCPv6、NDP 都设为 disabled；再把 WAN6 接口停用、全局网络选项里的 ULA 前缀清空。

命令行：`tr3600-ipv6 off`，恢复用 `tr3600-ipv6 on`。

## 漫游 / 认证

- 漫游：usteer 随 802.11k/v 工作，网络 → 无线 → 漫游。
- 酒店/机场：服务 → TravelMate，扫描并保存认证页。
- 校园网：服务 → **校园网认证**，填学号/密码/网卡（默认 eth0）、选认证方式（默认 rjv3）、按需选自动重启（30 分钟～每天），点「启用服务」。配置写入 `/etc/minieap.conf`；自动重启写入 `/etc/crontabs/root`（行尾标记 `# minieap-autorestart`），停用服务时一并移除。

## 测速

服务 → **HomeBox 测速**（端口 3300），或路由器 `iperf3 -s -D` 后用客户端跑 `iperf3 -c 192.168.1.1 -R`。

## 不要在线升级

内核、mt76、板级补丁同批编译。`apk upgrade`、LuCI 软件包页升级会导致 kmod ABI 不匹配，或替换 mt76 后丢失 MT7990 下行修复。

升级方式：重新编译，`sysupgrade -n` 刷整包。`/usr/sbin/apk` 与 LuCI 软件包页的升级入口已拦截，解锁用 `touch /etc/apk-allow-unsafe`。

## 构建

Actions → **Build Cudy TR3600 v1 (OpenWrt)** → Run workflow，约 1.5–3 小时。产物默认 pre-release，实测通过后取消 Pre-release 勾选转正式版。

可复现：Release 的「源码」一行记录 openwrt / kenzok8 / small 的 commit；重跑时把三个 SHA 填进 `REPO_COMMIT_FULL` / `KENZOK8_SHA` / `SMALL_SHA`，并把 `STRICT_SOURCE` 设为 `true`。

## 目录

```
patches/                         板级补丁 0001-0007，mt76 补丁 0002/0300
files/                           rootfs overlay（网络、USB 页、HomeBox、minieap、apk 源、sysctl）
vendor/                          风扇插件、Argon 主题
diy-pure-part1.sh / part2.sh     构建脚本
mt7987-cudy-tr3600-pure.config   构建配置
```

## 许可

见 [NOTICE.md](NOTICE.md)。
