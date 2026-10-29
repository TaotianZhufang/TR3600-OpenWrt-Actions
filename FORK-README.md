# TR3600-Unclamp 1.0（Cudy TR3600 v1 自定义固件）

本仓库是 khagav/TR3600-OpenWrt-Actions 的快照，额外加入：

- patches/0300-mt7996-mt7990-host-fill-txd.patch
  修复 MT7990 的 SDO TX 路径：AP→客户端速率被钳制在 6 Mbps、下行掉到 ~80Mbps 的问题。
- diy-pure-part2.sh 会自动把它放到 package/kernel/mt76/patches/
- workflow 在编译前会对它做 dry-run 预检（打不上立即失败）

## 使用

1. 在 GitHub 新建一个仓库（public/private 均可）
2. 把本目录所有文件（含 .github 隐藏目录）上传到仓库根目录
3. Actions 标签 → Build Cudy TR3600 OpenWrt Pure → Run workflow
4. 等待约 1.5~3 小时
5. 在运行结果底部下载 artifact（sysupgrade 镜像）
6. 刷机：从当前 OpenWrt 直接 sysupgrade -n，或经 Cudy 过渡固件

## 注意

- 本套件**内置**离线诊断工具：usbutils(lsusb)、pciutils(lspci)、ethtool、iperf3、tcpdump
- 不含 OpenClash / iStore（ttyd 已在本仓库的 Unclamp 版内置）
- 默认 IP 192.168.1.1/24（DHCP 池 192.168.1.100-249），密码 password
- 刷机有风险，确保有 TFTP 救砖手段（PC 192.168.1.88 / 路由 192.168.1.112 / 端口 3777）

## 名称

TR3600-Unclamp 1.0 -- "Unclamp / 解钳" 指修掉了 MT7990 把 AP 发送速率钳制在 6 Mbit/s 的问题。

刷入后 cat /etc/openwrt_release 应显示：

    DISTRIB_DESCRIPTION='TR3600-Unclamp 1.0 r0-046aec0'
