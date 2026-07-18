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
    
    # 删除本地可能存在的不同名称的软件包 (修正路径: ../feeds -> ./feeds)
    for NAME in "${PKG_LIST[@]}"; do
        echo "Search directory: $NAME"
        local FOUND_DIRS=$(find ./feeds/luci/ ./feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)
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
        find ./"$REPO_NAME"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
        rm -rf ./"$REPO_NAME"/
    elif [[ "$PKG_SPECIAL" == "name" ]]; then
        mv -f "$REPO_NAME" "$PKG_NAME"
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
# 3. 更新软件包版本 (修正路径: ../feeds -> ./feeds)
# ==========================================
UPDATE_VERSION() {
    local PKG_NAME=$1
    local PKG_MARK=${2:-false}
    local PKG_FILES=$(find ./ ./feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile" 2>/dev/null)
    
    if [ -z "$PKG_FILES" ]; then
        echo "$PKG_NAME not found!"
        return
    fi
    
    echo -e "\n$PKG_NAME version update has started!"
    for PKG_FILE in $PKG_FILES; do
        local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" "$PKG_FILE" || echo "")
        if [ -z "$PKG_REPO" ]; then continue; fi
        
        local PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")
        local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
        local OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
        local OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
        local OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")
        
        local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")
        local NEW_VER=$(echo "$PKG_TAG" | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
        local NEW_URL=$(echo "$PKG_URL" | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
        local NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)
        
        echo "old version: $OLD_VER $OLD_HASH"
        echo "new version: $NEW_VER $NEW_HASH"
        
        if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
            sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
            sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
            echo "$PKG_FILE version has been updated!"
        else
            echo "$PKG_FILE version is already the latest!"
        fi
    done
}

# ==========================================
# 4. 清理官方默认插件 (修正路径: ../feeds -> ./feeds)
# ==========================================
echo "🧹 Cleaning up default official packages..."
rm -rf ./feeds/luci/applications/luci-app-{passwall*,mosdns,dockerman,dae*,bypass*}
rm -rf ./feeds/packages/net/{v2ray-geodata,dae*}

# 复制外部 package 到当前目录
cp -r "$GITHUB_WORKSPACE"/package/* ./

# ==========================================
# 5. 专项补丁修复
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
# 6. 终极保障：强制移除 dockerman 版本号的 'v' 前缀
# ==========================================
echo "🔧 Enforcing PKG_VERSION fix for dockerman (removing 'v' prefix)..."
# 使用更宽泛且精准的查找，确保无论它被放在哪里都能被修改
find . -type f -name "Makefile" -exec grep -l "PKG_VERSION:=v0.5.26" {} \; 2>/dev/null | while read -r file; do
    echo "🔧 Found and fixing in: $file"
    sed -i 's/^PKG_VERSION:=v/PKG_VERSION:=/' "$file"
done

echo "✅ Packages.sh execution completed successfully!"
