TR3600-Unclamp 1.0

本固件的内核 6.12.94 / mt76 39c960c3 / 板级补丁是同一批编译的配套。
在线升级（apk upgrade、LuCI 软件包页升级）会破坏该配套：
  - kmod 与内核 ABI 不匹配 -> 模块加载失败（invalid module format）
  - mt76 被替换 -> MT7990 host-fill 修复失效，下行回落到约 80 Mbps

已内置保护：
  - /usr/sbin/apk 包装器：拦截 apk upgrade / fix 与系统包（kmod-*/kernel/base-files/mt76*/wpad*）安装
  - /usr/libexec/package-manager-call：拦截 LuCI 软件包页的升级与系统包安装
  - 注意：若自行安装第三方商店（如 iStore），其「全部更新」同样会破坏配套，请勿点击

确需执行时：touch /etc/apk-allow-unsafe （谨慎，自担风险）

安全升级方式：整包重新编译 -> sysupgrade 刷整包固件。
