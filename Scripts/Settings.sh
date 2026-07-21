#!/bin/bash
. $(dirname "$(realpath "$0")")/function.sh
#移除luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ DaeWRT-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
	#修改WIFI地区
	sed -i "s/country='.*'/country='CN'/g" $WIFI_UC
	#修改WIFI加密
	sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

vlmcsd_patches="./feeds/packages/net/vlmcsd/patches/"
mkdir -p $vlmcsd_patches && cp -f ../patches/001-fix_compile_with_ccache.patch $vlmcsd_patches

sed -i 's/mirrors.vsean.net\/openwrt/mirror.nju.edu.cn\/immortalwrt/g' ./package/emortal/default-settings/files/99-default-settings-chinese

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
#echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#取消nss相关feed
	echo "CONFIG_FEED_nss_packages=n" >> ./.config
	echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
	#开启sqm-nss插件
	# echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
	# echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
	#设置NSS版本
	echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
	if [[ "${WRT_CONFIG,,}" == *"ipq50"* ]]; then
		echo "CONFIG_NSS_FIRMWARE_VERSION_12_2=y" >> ./.config
	else
		echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
	fi
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
	#其他调整
	echo "CONFIG_PACKAGE_kmod-usb-serial-qualcomm=y" >> ./.config
fi
#亚瑟修复USB2.0日志报错问题
#wget -qO - https://github.com/davidtall/immortalwrt/commit/ce39feb4.patch | patch -p1
#cat ./target/linux/qualcommax/dts/ipq6000-re-ss-01.dts

# =============================================================================
# 新增模块一：优化三 - 强制关闭 CONFIG_DEVEL（减少体积，加快编译）
# =============================================================================
log_info() { echo -e "\033[0;32m[INFO]\033[0m  $1"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m  $1"; }

if grep -q "^CONFIG_DEVEL=y" ./.config; then
    sed -i 's/^CONFIG_DEVEL=y/# CONFIG_DEVEL is not set/' ./.config
    log_info "CONFIG_DEVEL has been disabled (removed from .config)."
else
    log_info "CONFIG_DEVEL is already disabled or not set."
fi

# =============================================================================
# 新增模块二：优化五 - 诊断 CONFIG_PACKAGE_coremark 依赖来源
# =============================================================================
log_info "=== Diagnosing CONFIG_PACKAGE_coremark ==="

# 方法1：使用 OpenWrt 的 dumpconfig 工具分析依赖
DUMP_OUTPUT=$(make -C . DUMP_CONFIG=1 2>/dev/null | grep -E "PACKAGE_coremark" || true)
if [ -n "$DUMP_OUTPUT" ]; then
    log_info "Dumpconfig reveals coremark-related entries:"
    echo "------------------------------------------------------------"
    echo "$DUMP_OUTPUT"
    echo "------------------------------------------------------------"
else
    log_warn "No coremark-related entries found in dumpconfig output."
fi

# 方法2：在 package/ 和 feeds/ 中搜索依赖关系
SEARCH_RESULT=$(grep -r -l "DEPENDS.*coremark" package/ feeds/ 2>/dev/null || true)
if [ -n "$SEARCH_RESULT" ]; then
    log_warn "Explicit DEPENDS on coremark found in:"
    echo "------------------------------------------------------------"
    for file in $SEARCH_RESULT; do
        grep -H "DEPENDS.*coremark" "$file" 2>/dev/null || true
    done
    echo "------------------------------------------------------------"
    log_info "If any of these packages are not essential, set them to '=n' in Config."
else
    log_info "No explicit DEPENDS on coremark found in package/ or feeds/."
fi

# 方法3：检查 .config 中 coremark 的当前状态
if grep -q "^CONFIG_PACKAGE_coremark=y" ./.config; then
    log_warn "coremark is currently selected as '=y' in .config."
    # 可选：强制移除 coremark（默认注释，如需启用请取消注释）
    # 警告：编译失败时的错误日志会明确指示是哪个包需要它，有助于最终决策
    #
    # if [ -z "$SEARCH_RESULT" ]; then
    #     log_warn "No explicit dependency found. Attempting to remove coremark..."
    #     sed -i 's/^CONFIG_PACKAGE_coremark=y/# CONFIG_PACKAGE_coremark is not set/' ./.config
    #     log_info "coremark has been removed from .config."
    # else
    #     log_warn "Explicit dependency exists. Skipping forced removal."
    # fi
else
    log_info "coremark is NOT selected as '=y' in .config (good!)."
fi

log_info "=== Config tuning completed successfully ==="
