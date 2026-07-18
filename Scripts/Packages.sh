#!/bin/bash
# 安装和更新软件包
UPDATE_PACKAGE() {
    local PKG_NAME=$1
    local PKG_REPO=$2
    local PKG_BRANCH=$3
    local PKG_SPECIAL=$4
    local PKG_LIST=("$PKG_NAME" $5)  # 第5个参数为自定义名称列表
    local REPO_NAME=${PKG_REPO#*/}
    echo " "
    
    # 删除本地可能存在的不同名称的软件包 (修正路径: ./feeds)
    for NAME in "${PKG_LIST[@]}"; do
        echo "Search directory: $NAME"
        # 使用更精确的匹配模式，防止误伤
        local FOUND_DIRS=$(find ./feeds/luci/ ./feeds/packages/ -maxdepth 3 -type d \( -name "$NAME" -o -name "luci-app-$NAME" -o -name "*-$NAME" \) 2>/dev/null)
        if [ -n "$FOUND_DIRS" ]; then
            while read -r DIR; do
                rm -rf "$DIR"
                echo "Delete directory: $DIR"
            done <<< "$FOUND_DIRS"
        else
            echo "Not found directory: $NAME"
        fi
    done
    
    # 克隆 GitHub 仓库
    git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git"
    
    # 处理克隆的仓库
    if [[ "$PKG_SPECIAL" == "pkg" ]]; then
        local TARGET_DIR=$(find ./"$REPO_NAME" -maxdepth 2 -type d -iname "*$PKG_NAME*" | head -n 1)
        if [ -n "$TARGET_DIR" ]; then
            mkdir -p ./package
            mv -f "$TARGET_DIR" "./package/$PKG_NAME"
            echo "✅ Moved $PKG_NAME to ./package/"
        fi
        rm -rf ./"$REPO_NAME"/
    elif [[ "$PKG_SPECIAL" == "name" ]]; then
        mkdir -p ./package
        mv -f "$REPO_NAME" "./package/$PKG_NAME"
    else
        # 默认行为：移动到 package 目录以确保被编译系统识别
        mkdir -p ./package
        mv -f "$REPO_NAME" "./package/$PKG_NAME" 2>/dev/null || true
    fi
}

# ==========================================
# 1. 调用 UPDATE_PACKAGE 拉取自定义插件
# ==========================================
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"
UPDATE_PACKAGE "kucat" "sirpdboy/luci-theme-kucat" "master"
UPDATE_PACKAGE "kucat-config" "sirpdboy/luci-app-kucat-config" "master"
UPDATE_PACKAGE "homeproxy" "VIKINGYFY/homeproxy" "main"
UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "ddns-go" "sirpdboy/luci-app-ddns-go" "main"
UPDATE_PACKAGE "diskman" "lisaac/luci-app-diskman" "master"
UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"
UPDATE_PACKAGE "fancontrol" "rockjake/luci-app-fancontrol" "main"
UPDATE_PACKAGE "gecoosac" "openwrt-fork/openwrt-gecoosac" "main"
UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
UPDATE_PACKAGE "openlist2" "sbwml/luci-app-openlist2" "main"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "luci-app-timewol luci-app-wolplus"
UPDATE_PACKAGE "vnt" "lmq8267/luci-app-vnt" "main"
UPDATE_PACKAGE "dockerman" "lisaac/luci-app-dockerman" "master"
UPDATE_PACKAGE "luci-app-daed" "QiuSimons/luci-app-daed" "kix"
UPDATE_PACKAGE "luci-app-pushbot" "zzsj0928/luci-app-pushbot" "master"
UPDATE_PACKAGE "luci-app-lucky" "sirpdboy/luci-app-lucky" "main"

# ==========================================
# 2. 强制补全 luci-app-dockerman 的底层依赖
# ==========================================
echo "🔧 Checking/Cloning luci-lib-docker dependency..."
if [ -d "./package" ]; then
    TARGET_DIR="./package/luci-lib-docker"
else
    TARGET_DIR="./luci-lib-docker"
fi
if [ ! -d "$TARGET_DIR" ]; then
    echo "📥 Cloning luci-lib-docker from lisaac/luci-lib-docker..."
    git clone --depth=1 --single-branch --branch master "https://github.com/lisaac/luci-lib-docker.git" "$TARGET_DIR"
    echo "✅ luci-lib-docker cloned successfully to $TARGET_DIR"
else
    echo "✅ luci-lib-docker already exists, skipping clone."
fi

# ==========================================
# 3. 清理官方默认插件 (修正路径: ./feeds)
# ==========================================
echo "🧹 Cleaning up default official packages..."
rm -rf ./feeds/luci/applications/luci-app-{passwall*,mosdns,dockerman,dae*,bypass*}
rm -rf ./feeds/packages/net/{v2ray-geodata,dae*}

# 复制外部 package 到当前目录 (增加判空保护)
if [ -n "$GITHUB_WORKSPACE" ] && [ -d "$GITHUB_WORKSPACE/package" ]; then
    echo "📦 Copying external packages from GitHub Workspace..."
    cp -r "$GITHUB_WORKSPACE"/package/* ./
else
    echo "⚠️ GITHUB_WORKSPACE/package not found, skipping copy."
fi

# ==========================================
# 4. 专项补丁修复
# ==========================================
echo "🔧 Applying specific package patches..."
# 修复 daed
if [ -f "luci-app-daed/daed/Makefile" ]; then
    sed -i 's/pnpm install ; \\/pnpm install --no-frozen-lockfile ; \\/g' luci-app-daed/daed/Makefile
    sed -i 's|github.com/daeuniverse/quic-go|github.com/olicesx/quic-go|g' luci-app-daed/daed/Makefile
fi
if [ -f "luci-app-daed/luci-app-daed/root/etc/init.d/luci_daed" ]; then
    sed -i 's|/run/i\\  procd_set_param|/procd_set_param command/i \\\tprocd_set_param|g' luci-app-daed/luci-app-daed/root/etc/init.d/luci_daed
fi

# ==========================================
# 5. 终极保障：动态移除 dockerman 版本号的 'v' 前缀 (修复硬编码问题)
# ==========================================
echo "🔧 Enforcing PKG_VERSION fix for dockerman (removing 'v' prefix)..."
find . -type f -name "Makefile" -exec grep -l "PKG_VERSION:=v[0-9]" {} \; 2>/dev/null | while read -r file; do
    echo "🔧 Found and fixing version prefix in: $file"
    sed -i 's/^PKG_VERSION:=v\(.*\)/PKG_VERSION:=\1/' "$file"
done

echo "✅ Packages.sh execution completed successfully!"
