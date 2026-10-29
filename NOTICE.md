# 来源与许可（NOTICE）

本构建套件由多个上游拼装而成。**个人自用（只刷自己的设备）不涉及分发，无需处理。**
若要把本仓库或产出的镜像公开发布，请保留本文件，并遵守下面各项。

## 1. OpenWrt 本体
- 许可：GPL-2.0
- 源码：https://github.com/openwrt/openwrt （分支 openwrt-25.12）
- TR3600 板级支持：上游 PR #24596（尚未合并），构建时从
  https://github.com/soapmancn/openwrt 分支 agent/cudy-tr3600-v1-6.12 获取（钉在 046aec0d）
- 发布镜像时须能提供对应源码：本仓库公开即可满足（构建脚本 + 补丁齐全）。

## 2. mt76 补丁
- patches/0002-mt76-mt7996-sta-rec-before-vow.patch
  来自上游 commit da2c90d2，backport 至 mt76 39c960c3。
- patches/0300-mt7996-mt7990-host-fill-txd.patch
  原作者 kyoto44（openwrt/mt76 issue #1043），由 visualphoenix/beryl7 打包发布。
  该补丁修改的是 GPL-2.0 的 mt76 源码，因此按 GPL-2.0 分发；请保留作者署名。

## 3. 构建脚本与板级补丁
- 来源：https://github.com/khagav/TR3600-OpenWrt-Actions
  （该仓库**未声明 LICENSE**，默认视为保留所有权利）
- 本套件在其基础上做了修改：加入 0300 补丁、ttyd、USB 页面、版本标识、默认网段。
- 公开发布前建议：保留作者署名与原仓库链接；最好先向作者确认可否复用。

## 4. USB 管理页面
- files/usr/libexec/rpcd/tr3600.usb、files/usr/share/luci/... 与 files/www/...
  来自 https://github.com/EDBWDY/cudy-tr3600-openwrt 的 luci-app-tr3600-usb 包
  （该仓库**未声明 LICENSE**）
- 仅建议个人使用；公开发布前应取得作者许可或自行重写。

## 5. 固件与二进制
- MediaTek mt7990 固件随 OpenWrt 的 linux-firmware 包分发，遵循其原始许可，
  不得单独抽取商用。
- 本套件不包含 OpenClash / mihomo / AdGuard 等第三方二进制。

## 6. 本套件新增部分
- TR3600-Unclamp 的集成改动（0300 补丁接入、ttyd、USB 菜单、默认 IP、版本标识）
  可按 GPL-2.0 使用与再分发，但需保留上述所有上游署名。
