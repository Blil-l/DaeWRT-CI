#!/bin/bash
# 确保脚本在 wrt 目录下执行，获取绝对路径以增加健壮性
WRT_DIR="${WRT_DIR:-.}"
PKG_PATH="$WRT_DIR/package/"

echo "🔧 Starting Handles.sh customization..."

# ==========================================
# 1. 预置 HomeProxy 数据
# ==========================================
if [ -d "$PKG_PATH/homeproxy" ]; then
    echo "📥 Updating HomeProxy rules..."
    HP_RULE="surge_rules_temp"
    HP_PATH="$PKG_PATH/homeproxy/root/etc/homeproxy"
    rm -rf "$HP_PATH/resources/"*
    
    if git clone -q --depth=1 --single-branch --branch "release" "https://github.com/Loyalsoldier/surge-rules.git" "$HP_RULE"; then
        cd "$HP_RULE" || exit 1
        RES_VER=$(git log -1 --pretty=format:'%s' | grep -o "[0-9]*")
        echo "$RES_VER" | tee china_ip4.ver china_ip6.ver china_list.ver gfw_list.ver
        awk -F, '/^IP-CIDR,/{print $2 > "china_ip4.txt"} /^IP-CIDR6,/{print $2 > "china_ip6.txt"}' cncidr.txt
        sed 's/^\.//g' direct.txt > china_list.txt
        sed 's/^\.//g' gfw.txt > gfw_list.txt
        mv -f ./{china_*,gfw_list}.{ver,txt} "../$HP_PATH/resources/"
        cd .. && rm -rf "$HP_RULE"
        echo "✅ HomeProxy rules updated!"
    else
        echo "⚠️ Failed to clone surge-rules, skipping."
    fi
fi

# ==========================================
# 2. 修改 Argon 主题字体和颜色
# ==========================================
ARGON_DIR=$(find "$PKG_PATH" -maxdepth 2 -type d -name "luci-theme-argon" | head -n 1)
if [ -n "$ARGON_DIR" ] && [ -d "$ARGON_DIR" ]; then
    echo "🎨 Customizing Argon theme..."
    CONFIG_FILE="$ARGON_DIR/luci-app-argon-config/root/etc/config/argon"
    if [ -f "$CONFIG_FILE" ]; then
        sed -i "s/primary '.*'/primary '#31a1a1'/; s/'0.2'/'0.5'/; s/'none'/'bing'/; s/'600'/'normal'/" "$CONFIG_FILE"
        echo "✅ Argon theme customized!"
    fi
fi

# ==========================================
# 3. 修改 Aurora 菜单样式
# ==========================================
AURORA_DIR=$(find "$PKG_PATH" -maxdepth 2 -type d -name "luci-app-aurora-config" | head -n 1)
if [ -n "$AURORA_DIR" ] && [ -d "$AURORA_DIR" ]; then
    echo "🎨 Customizing Aurora theme..."
    find "$AURORA_DIR/root/" -type f -name "*aurora*" -exec sed -i "s/nav_submenu_type '.*'/nav_submenu_type 'boxed-dropdown'/g" {} \;
    echo "✅ Aurora theme customized!"
fi

# ==========================================
# 4. 修改 qca-nss-drv 启动顺序 (修正路径: ../feeds -> ./feeds)
# ==========================================
NSS_DRV="./feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
if [ -f "$NSS_DRV" ]; then
    echo "⚙️ Adjusting qca-nss-drv startup order..."
    sed -i 's/START=.*/START=85/g' "$NSS_DRV"
    echo "✅ qca-nss-drv startup order fixed!"
fi

# ==========================================
# 5. 修改 qca-nss-pbuf 启动顺序
# ==========================================
NSS_PBUF="./kernel/mac80211/files/qca-nss-pbuf.init"
if [ -f "$NSS_PBUF" ]; then
    echo "⚙️ Adjusting qca-nss-pbuf startup order..."
    sed -i 's/START=.*/START=86/g' "$NSS_PBUF"
    echo "✅ qca-nss-pbuf startup order fixed!"
fi

# ==========================================
# 6. 修复 Tailscale 配置文件冲突 (修正路径)
# ==========================================
TS_FILE=$(find ./feeds/packages/ -maxdepth 3 -type f -wholename "*/tailscale/Makefile" 2>/dev/null | head -n 1)
if [ -n "$TS_FILE" ] && [ -f "$TS_FILE" ]; then
    echo "🔧 Fixing Tailscale Makefile..."
    sed -i '/\/files/d' "$TS_FILE"
    echo "✅ Tailscale fixed!"
fi

# ==========================================
# 7. 修复 Rust 编译失败 (修正路径)
# ==========================================
RUST_FILE=$(find ./feeds/packages/ -maxdepth 3 -type f -wholename "*/rust/Makefile" 2>/dev/null | head -n 1)
if [ -n "$RUST_FILE" ] && [ -f "$RUST_FILE" ]; then
    echo "🔧 Fixing Rust Makefile..."
    sed -i 's/ci-llvm=true/ci-llvm=false/g' "$RUST_FILE"
    echo "✅ Rust fixed!"
fi

# ==========================================
# 8. 修复 DiskMan 编译失败
# ==========================================
DM_FILE=$(find "$PKG_PATH" -maxdepth 4 -type f -wholename "*/luci-app-diskman/Makefile" 2>/dev/null | head -n 1)
if [ -n "$DM_FILE" ] && [ -f "$DM_FILE" ]; then
    echo "🔧 Fixing DiskMan Makefile..."
    sed -i '/ntfs-3g-utils /d' "$DM_FILE"
    echo "✅ DiskMan fixed!"
fi

# ==========================================
# 9. 临时禁用系统插件菜单权限 (可还原)
# ==========================================
echo "🔒 Disabling system plugin menu permissions..."
JSON_FILE=$(find ./feeds/luci/modules/luci-mod-system -name "luci-mod-system.json" -path "*/acl.d/*" 2>/dev/null | head -n 1)

if [ -n "$JSON_FILE" ] && [ -f "$JSON_FILE" ]; then
    echo "找到源码文件: $JSON_FILE"
    
    python3 << 'PYEOF'
import json
import sys
import os

json_file = os.environ.get('JSON_FILE')
original_key = "luci-mod-system-plugins"
disabled_key = "_disabled_luci-mod-system-plugins"

try:
    with open(json_file, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    # 如果存在原始键，则重命名为禁用键
    if original_key in data:
        data[disabled_key] = data.pop(original_key)
        with open(json_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write('\n')
        print(f'✅ 已重命名 [{original_key}] 为 [{disabled_key}]，插件菜单已隐藏。')
    elif disabled_key in data:
        print(f'ℹ️ 插件菜单已经是禁用状态，无需重复操作。')
    else:
        print(f'ℹ️ 未找到相关权限块。')
        
except Exception as e:
    print(f'❌ 处理失败: {e}')
    sys.exit(1)
PYEOF
else
    echo "️ 未找到 luci-mod-system.json 源码文件，请检查路径"
fi

# ==========================================
# 10. 终极保障：动态移除 dockerman 版本号的 'v' 前缀 (修复硬编码问题)
# ==========================================
echo "🔧 Enforcing PKG_VERSION fix for dockerman (removing 'v' prefix)..."
# 使用正则 v[0-9] 匹配任何以 v 开头的数字版本号，未来升级自动兼容
find . -type f -name "Makefile" -exec grep -l "PKG_VERSION:=v[0-9]" {} \; 2>/dev/null | while read -r file; do
    echo "🔧 Found and fixing version prefix in: $file"
    sed -i 's/^PKG_VERSION:=v\(.*\)/PKG_VERSION:=\1/' "$file"
done

echo "✅ Handles.sh execution completed successfully!"
