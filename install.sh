#!/bin/bash
set -e

CONTAINER_NAME="danmu-api"
IMAGE="logvar/danmu-api:latest"
DEFAULT_TOKEN="87654321"
DEFAULT_PORT="9321"
DEFAULT_CACHE="/opt/danmu/cache"

# ========== 系统识别 ==========
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_LIKE="$ID_LIKE"
        OS_CODENAME="${VERSION_CODENAME:-}"
        OS_VERSION_ID="${VERSION_ID:-}"
    else
        echo "无法识别系统（/etc/os-release 不存在）"
        exit 1
    fi

    case "$OS_ID" in
        debian|ubuntu) OS_FAMILY="debian" ;;
        centos|rhel|rocky|almalinux|fedora) OS_FAMILY="rhel" ;;
        *)
            case "$OS_LIKE" in
                *debian*|*ubuntu*) OS_FAMILY="debian" ;;
                *rhel*|*centos*|*fedora*) OS_FAMILY="rhel" ;;
                *) echo "不支持的系统：$OS_ID"; exit 1 ;;
            esac
            ;;
    esac
    echo ">>> 检测到系统：$OS_ID ($OS_FAMILY 系)"
}

# ========== Debian/Ubuntu 换源 ==========
setup_apt_source() {
    echo ">>> 配置 APT 国内源（阿里云）..."
    [ -f /etc/apt/sources.list ] && cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%s)
    if [ "$OS_ID" = "ubuntu" ]; then
        cat > /etc/apt/sources.list <<EOF
deb https://mirrors.aliyun.com/ubuntu/ ${OS_CODENAME} main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ ${OS_CODENAME}-updates main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ ${OS_CODENAME}-security main restricted universe multiverse
EOF
    else
        cat > /etc/apt/sources.list <<EOF
deb https://mirrors.aliyun.com/debian/ ${OS_CODENAME} main contrib non-free non-free-firmware
deb https://mirrors.aliyun.com/debian/ ${OS_CODENAME}-updates main contrib non-free non-free-firmware
deb https://mirrors.aliyun.com/debian-security ${OS_CODENAME}-security main contrib non-free non-free-firmware
EOF
    fi
    apt-get update
}

# ========== RHEL 系换源 ==========
setup_yum_source() {
    echo ">>> 配置 YUM/DNF 国内源..."
    if [ "$OS_ID" = "centos" ] && [ "${OS_VERSION_ID%%.*}" = "7" ]; then
        mkdir -p /etc/yum.repos.d/bak
        mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/ 2>/dev/null || true
        cat > /etc/yum.repos.d/CentOS-Base.repo <<'EOF'
[base]
name=CentOS-7 - Base - mirrors.aliyun.com
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/os/$basearch/
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/centos-vault/7.9.2009/os/$basearch/RPM-GPG-KEY-CentOS-7
[updates]
name=CentOS-7 - Updates - mirrors.aliyun.com
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/updates/$basearch/
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/centos-vault/7.9.2009/os/$basearch/RPM-GPG-KEY-CentOS-7
[extras]
name=CentOS-7 - Extras - mirrors.aliyun.com
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/extras/$basearch/
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/centos-vault/7.9.2009/os/$basearch/RPM-GPG-KEY-CentOS-7
EOF
        yum clean all && yum makecache
    else
        echo ">>> 现代 RHEL 系系统源保持默认，无需替换。"
    fi
}

# ========== 安装 Docker ==========
install_docker() {
    if command -v docker &>/dev/null; then
        echo ">>> Docker 已安装，跳过。"
        return 0
    fi
    echo ">>> 安装 Docker..."
    if [ "$OS_FAMILY" = "debian" ]; then
        apt-get install -y apt-transport-https ca-certificates curl gnupg
        curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/${OS_ID}/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/${OS_ID} ${OS_CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io
    else
        yum install -y yum-utils
        yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io
    fi
    systemctl start docker
    systemctl enable docker
    echo "Docker 安装完成。"
}

# ========== 镜像加速 ==========
setup_mirror() {
    mkdir -p /etc/docker
    if [ ! -f /etc/docker/daemon.json ]; then
        tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ]
}
EOF
        systemctl daemon-reload
        systemctl restart docker
    fi
}

# ========== 安装 danmu-api ==========
do_install() {
    detect_os
    read -p "普通 TOKEN [默认 $DEFAULT_TOKEN]: " INPUT_TOKEN
    TOKEN_VALUE=${INPUT_TOKEN:-$DEFAULT_TOKEN}
    read -p "管理员 ADMIN_TOKEN [必填]: " ADMIN_TOKEN_VALUE
    [ -z "$ADMIN_TOKEN_VALUE" ] && { echo "ADMIN_TOKEN 不能为空"; return 1; }
    read -p "映射端口 [默认 $DEFAULT_PORT]: " INPUT_PORT
    PORT_VALUE=${INPUT_PORT:-$DEFAULT_PORT}
    read -p "缓存目录 [默认 $DEFAULT_CACHE]: " INPUT_CACHE
    CACHE_DIR=${INPUT_CACHE:-$DEFAULT_CACHE}

    if [ "$OS_FAMILY" = "debian" ]; then
        setup_apt_source
    else
        setup_yum_source
    fi
    install_docker
    setup_mirror

    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    mkdir -p "$CACHE_DIR"
    docker run -d \
      --name "$CONTAINER_NAME" \
      --restart unless-stopped \
      -p "${PORT_VALUE}:9321" \
      -e TOKEN="$TOKEN_VALUE" \
      -e ADMIN_TOKEN="$ADMIN_TOKEN_VALUE" \
      -v "$CACHE_DIR:/app/.cache" \
      "$IMAGE"

    IP=$(hostname -I | awk '{print $1}')
    echo ""
    echo "=========================================="
    echo "安装完成！"
    echo "API 地址：http://${IP}:${PORT_VALUE}/${TOKEN_VALUE}"
    echo "管理后台：http://${IP}:${PORT_VALUE}/${ADMIN_TOKEN_VALUE}"
    echo "缓存目录：${CACHE_DIR}"
    echo "=========================================="
    echo "请确认防火墙/安全组已放行 ${PORT_VALUE} 端口。"
}

# ========== 卸载（逐项询问，按选择执行，不中断） ==========
do_uninstall() {
    detect_os
    echo ""
    echo "===== 卸载 danmu-api（逐项选择，y=卸载 / n=保留）====="

    # 1. 删除容器
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        read -p "删除容器 $CONTAINER_NAME ？(y/N): " ANS
        if [[ "$ANS" =~ ^[Yy]$ ]]; then
            docker rm -f "$CONTAINER_NAME" && echo "[完成] 容器已删除。"
        else
            echo "[保留] 容器未删除。"
        fi
    else
        echo "[跳过] 未找到容器 $CONTAINER_NAME。"
    fi

    # 2. 删除缓存目录
    if [ -d "$DEFAULT_CACHE" ]; then
        read -p "删除缓存目录 $DEFAULT_CACHE ？(y/N): " ANS
        if [[ "$ANS" =~ ^[Yy]$ ]]; then
            rm -rf "$DEFAULT_CACHE" && echo "[完成] 缓存目录已删除。"
        else
            echo "[保留] 缓存目录未删除。"
        fi
    else
        echo "[跳过] 缓存目录不存在。"
    fi

    # 3. 删除镜像
    if docker image inspect "$IMAGE" &>/dev/null; then
        read -p "删除镜像 $IMAGE ？(y/N): " ANS
        if [[ "$ANS" =~ ^[Yy]$ ]]; then
            docker rmi "$IMAGE" 2>/dev/null && echo "[完成] 镜像已删除。" || echo "[跳过] 镜像删除失败（可能被其他容器引用）。"
        else
            echo "[保留] 镜像未删除。"
        fi
    else
        echo "[跳过] 镜像不存在。"
    fi

    # 4. 卸载 Docker
    if command -v docker &>/dev/null; then
        read -p "卸载 Docker 及镜像加速配置？(y/N): " ANS
        if [[ "$ANS" =~ ^[Yy]$ ]]; then
            systemctl stop docker 2>/dev/null || true
            if [ "$OS_FAMILY" = "debian" ]; then
                apt-get remove -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1 || true
                apt-get autoremove -y >/dev/null 2>&1 || true
                rm -f /etc/apt/sources.list.d/docker.list
            else
                yum remove -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1 || true
                rm -f /etc/yum.repos.d/docker-ce.repo
            fi
            rm -f /etc/docker/daemon.json
            echo "[完成] Docker 已卸载。"
        else
            echo "[保留] Docker 未卸载。"
        fi
    else
        echo "[跳过] Docker 未安装。"
    fi

    # 5. 还原系统软件源
    read -p "还原系统软件源？(y/N): " ANS
    if [[ "$ANS" =~ ^[Yy]$ ]]; then
        if [ "$OS_FAMILY" = "debian" ] && ls /etc/apt/sources.list.bak.* &>/dev/null; then
            LATEST_BAK=$(ls -t /etc/apt/sources.list.bak.* | head -1)
            cp "$LATEST_BAK" /etc/apt/sources.list
            apt-get update >/dev/null 2>&1 || true
            echo "[完成] APT 源已还原自 $LATEST_BAK。"
        elif [ "$OS_FAMILY" = "rhel" ] && [ -d /etc/yum.repos.d/bak ]; then
            mv /etc/yum.repos.d/bak/*.repo /etc/yum.repos.d/ 2>/dev/null || true
            echo "[完成] YUM 源已还原。"
        else
            echo "[跳过] 未找到系统源备份。"
        fi
    else
        echo "[保留] 系统软件源未还原。"
    fi

    echo "卸载流程结束。"
}

# ========== 菜单 ==========
echo "=============================="
echo "   danmu-api 管理脚本"
echo "=============================="
echo "1) 安装 / 重新部署"
echo "2) 卸载"
echo "3) 退出"
read -p "请选择 [1-3]: " CHOICE

case "$CHOICE" in
    1) do_install ;;
    2) do_uninstall ;;
    3) exit 0 ;;
    *) echo "无效选项" ;;
esac
