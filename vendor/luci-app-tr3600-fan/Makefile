# SPDX-License-Identifier: Apache-2.0

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-tr3600-fan
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

LUCI_TITLE:=Cudy TR3600 fan control
LUCI_DEPENDS:=+luci-base +kmod-hwmon-pwmfan +uci
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
