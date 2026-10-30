# Cudy TR3600 v1 OpenWrt

本仓库基于 khagav/TR3600-OpenWrt-Actions 修改，主要差异：

- 加入 `patches/0300`（MT7990 SDO TX 修复，解决下行约 80 Mbps），part2 自动放进 `package/kernel/mt76/patches/`，编译前 dry-run；
- 内置风扇插件与 Argon 主题（`vendor/`），不依赖第三方仓库；
- 内置 USB 管理页、ttyd、lsusb/lspci/ethtool/iperf3/tcpdump；
- 默认 LAN 192.168.1.1/24，DHCP 100–249，root 无密码；
- 在线升级拦截（`/usr/sbin/apk` 与 LuCI 后端）。

构建：Actions → **Build Cudy TR3600 v1 (OpenWrt)**。刷机与注意事项见 README.md。
