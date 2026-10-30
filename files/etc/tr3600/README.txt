Cudy TR3600 v1 — OpenWrt

内核 6.12.94、mt76 39c960c3 与板级补丁是同一批编译的配套，不要在线升级：
  - apk upgrade / LuCI 软件包页升级：kmod 与内核 ABI 不匹配，模块加载失败；
  - mt76 被替换：MT7990 下行修复失效，速度回到约 80 Mbps。

已内置保护：
  - /usr/sbin/apk：拦截 upgrade / fix 与系统包安装；
  - /usr/libexec/package-manager-call：拦截 LuCI 软件包页的升级与系统包安装；
  - 解锁：touch /etc/apk-allow-unsafe。

安全升级方式：整包重新编译，再 sysupgrade 刷整包。
