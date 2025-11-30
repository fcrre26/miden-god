#!/bin/bash

# Miden节点一键安装脚本（Ubuntu优化版）
# 版本: 2.0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 变量
DATA_DIR="$HOME/miden-data"
ACCOUNTS_DIR="$HOME/miden-accounts"
CONFIG_DIR="$HOME/miden-config"
VERSION="0.12.5"
INSTALL_METHOD=""
NODE_INSTALLED=false
IS_UBUNTU=false
IS_DEBIAN=false

# 显示标题
show_header() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║               Miden节点一键安装脚本             ║"
    echo "║              Ubuntu优化版 v2.0                  ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # 显示系统信息
    if [ "$IS_UBUNTU" = true ]; then
        echo -e "${GREEN}✓ 检测到 Ubuntu 系统${NC}"
    elif [ "$IS_DEBIAN" = true ]; then
        echo -e "${GREEN}✓ 检测到 Debian 系统${NC}"
    else
        echo -e "${YELLOW}⚠ 非Ubuntu/Debian系统，部分功能可能受限${NC}"
    fi
}

# 检测系统
detect_system() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if [[ "$ID" == "ubuntu" ]]; then
            IS_UBUNTU=true
            echo -e "${GREEN}系统: Ubuntu $VERSION_ID${NC}"
        elif [[ "$ID" == "debian" ]]; then
            IS_DEBIAN=true
            echo -e "${GREEN}系统: Debian $VERSION_ID${NC}"
        else
            echo -e "${YELLOW}系统: $NAME${NC}"
        fi
    fi
}

# 检查系统要求
check_system() {
    echo -e "${YELLOW}[信息] 检查系统要求...${NC}"
    
    detect_system
    
    # 检查架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            echo -e "${GREEN}✓ 架构: AMD64 (x86_64)${NC}"
            ;;
        aarch64)
            echo -e "${GREEN}✓ 架构: ARM64${NC}"
            ;;
        *)
            echo -e "${RED}✗ 不支持的架构: $ARCH${NC}"
            echo -e "${YELLOW}仅支持 AMD64 和 ARM64 架构${NC}"
            exit 1
            ;;
    esac
    
    # 检查内存
    MEM_GB=$(free -g | awk 'NR==2{print $2}')
    if [ "$MEM_GB" -lt 2 ]; then
        echo -e "${YELLOW}⚠ 内存较低: ${MEM_GB}GB (推荐4GB以上)${NC}"
    else
        echo -e "${GREEN}✓ 内存: ${MEM_GB}GB${NC}"
    fi
    
    # 检查磁盘空间
    DISK_GB=$(df -BG . | awk 'NR==2{print $4}' | sed 's/G//')
    if [ "$DISK_GB" -lt 10 ]; then
        echo -e "${YELLOW}⚠ 磁盘空间紧张: ${DISK_GB}GB (推荐20GB以上)${NC}"
    else
        echo -e "${GREEN}✓ 磁盘空间: ${DISK_GB}GB${NC}"
    fi
    
    # 检查必要工具
    for tool in curl wget; do
        if command -v $tool &> /dev/null; then
            echo -e "${GREEN}✓ 已安装: $tool${NC}"
        else
            echo -e "${YELLOW}⚠ 未安装: $tool${NC}"
        fi
    done
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}[信息] 安装系统依赖...${NC}"
    
    if [ "$IS_UBUNTU" = true ] || [ "$IS_DEBIAN" = true ]; then
        sudo apt update
        sudo apt install -y \
            curl wget git build-essential \
            llvm clang pkg-config libssl-dev libsqlite3-dev cmake
        echo -e "${GREEN}✓ Ubuntu/Debian 依赖安装完成${NC}"
    else
        echo -e "${YELLOW}[警告] 无法自动识别系统类型，请手动安装依赖${NC}"
        echo "需要的依赖: llvm clang pkg-config libssl-dev libsqlite3-dev cmake"
        read -p "按回车键继续..."
    fi
}

# 安装Rust
install_rust() {
    echo -e "${YELLOW}[信息] 安装Rust...${NC}"
    
    if command -v rustc &> /dev/null; then
        echo -e "${GREEN}✓ Rust已安装: $(rustc --version)${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}安装Rust工具链...${NC}"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    
    if command -v rustc &> /dev/null; then
        echo -e "${GREEN}✓ Rust安装成功: $(rustc --version)${NC}"
    else
        echo -e "${RED}✗ Rust安装失败${NC}"
        exit 1
    fi
}

# 通过Cargo安装节点（推荐开发环境）
install_via_cargo() {
    echo -e "${CYAN}[方法] 使用Cargo安装 (推荐开发测试)${NC}"
    echo -e "${YELLOW}优点: 版本最新，适合开发${NC}"
    echo -e "${YELLOW}缺点: 编译时间较长(10-30分钟)${NC}"
    echo
    
    read -p "确定使用Cargo安装? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "安装已取消"
        return 1
    fi
    
    install_rust
    
    echo -e "${YELLOW}[信息] 编译安装Miden节点，请耐心等待...${NC}"
    echo -e "${YELLOW}这可能需要10-30分钟，取决于您的系统性能${NC}"
    
    source "$HOME/.cargo/env"
    cargo install miden-node --locked
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Miden节点安装成功${NC}"
        NODE_INSTALLED=true
        INSTALL_METHOD="cargo"
        
        # 验证安装
        if command -v miden-node &> /dev/null; then
            echo -e "${GREEN}✓ 节点命令可用${NC}"
        else
            echo -e "${YELLOW}⚠ 请运行: source ~/.cargo/env 或重新登录${NC}"
        fi
    else
        echo -e "${RED}✗ Miden节点安装失败${NC}"
        return 1
    fi
}

# 通过Debian包安装节点（推荐生产环境）
install_via_debian() {
    echo -e "${CYAN}[方法] 使用Debian包安装 (推荐生产环境)${NC}"
    echo -e "${YELLOW}优点: 安装快速，包含系统服务${NC}"
    echo -e "${YELLOW}缺点: 版本可能不是最新${NC}"
    echo
    
    if [ "$IS_UBUNTU" = false ] && [ "$IS_DEBIAN" = false ]; then
        echo -e "${RED}✗ 当前系统不支持Debian包安装${NC}"
        echo -e "${YELLOW}仅Ubuntu/Debian系统支持此安装方式${NC}"
        return 1
    fi
    
    read -p "确定使用Debian包安装? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "安装已取消"
        return 1
    fi
    
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            DEB_ARCH="amd64"
            ;;
        aarch64)
            DEB_ARCH="arm64"
            ;;
        *)
            echo -e "${RED}✗ 不支持的架构: $ARCH${NC}"
            return 1
            ;;
    esac
    
    PACKAGE_NAME="miden-node-v${VERSION}-${DEB_ARCH}.deb"
    CHECKSUM_NAME="${PACKAGE_NAME}.checksum"
    
    echo -e "${YELLOW}[信息] 下载Miden节点包...${NC}"
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # 下载包和校验和
    echo -e "${YELLOW}下载包文件...${NC}"
    wget -q "https://github.com/0xMiden/miden-node/releases/download/v${VERSION}/${PACKAGE_NAME}" || {
        echo -e "${RED}✗ 下载包文件失败${NC}"
        return 1
    }
    
    echo -e "${YELLOW}下载校验和文件...${NC}"
    wget -q "https://github.com/0xMiden/miden-node/releases/download/v${VERSION}/${CHECKSUM_NAME}" || {
        echo -e "${RED}✗ 下载校验和文件失败${NC}"
        return 1
    }
    
    # 验证校验和
    echo -e "${YELLOW}[信息] 验证包完整性...${NC}"
    if sha256sum --check "$CHECKSUM_NAME"; then
        echo -e "${GREEN}✓ 校验和验证成功${NC}"
        
        # 安装包
        echo -e "${YELLOW}安装Debian包...${NC}"
        sudo dpkg -i "$PACKAGE_NAME"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Miden节点安装成功${NC}"
            NODE_INSTALLED=true
            INSTALL_METHOD="debian"
            
            # 检查服务状态
            if systemctl is-active --quiet miden-node; then
                echo -e "${GREEN}✓ 节点服务正在运行${NC}"
            else
                echo -e "${YELLOW}⚠ 节点服务未运行，需要先引导节点${NC}"
            fi
        else
            echo -e "${RED}✗ 包安装失败${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ 校验和验证失败${NC}"
        return 1
    fi
    
    # 清理临时文件
    cd -
    rm -rf "$TEMP_DIR"
}

# 创建配置目录
create_directories() {
    echo -e "${YELLOW}[信息] 创建必要的目录...${NC}"
    
    mkdir -p "$DATA_DIR"
    mkdir -p "$ACCOUNTS_DIR"
    mkdir -p "$CONFIG_DIR"
    
    echo -e "${GREEN}✓ 目录创建完成${NC}"
    echo -e "  数据目录: $DATA_DIR"
    echo -e "  账户目录: $ACCOUNTS_DIR"
    echo -e "  配置目录: $CONFIG_DIR"
}

# 创建Genesis配置文件
create_genesis_config() {
    cat > "$CONFIG_DIR/genesis.toml" << EOF
# Genesis配置文件
# 生成时间: $(date)
timestamp = $(date +%s)
version   = 1

[native_faucet]
symbol     = "MIDEN"
decimals   = 6
max_supply = 100_000_000_000_000_000

[fee_parameters]
verification_base_fee = 0

# 示例测试代币
[[fungible_faucet]]
symbol       = "TEST"
decimals     = 6
max_supply   = 1_000_000_000_000_000
storage_mode = "public"

# 示例钱包
[[wallet]]
assets       = [{ amount = 100_000_000, symbol = "TEST" }]
storage_mode = "private"
EOF
    
    echo -e "${GREEN}✓ Genesis配置文件已创建: $CONFIG_DIR/genesis.toml${NC}"
    echo -e "${YELLOW}您可以根据需要编辑此文件${NC}"
}

# 引导节点
bootstrap_node() {
    echo -e "${YELLOW}[信息] 引导Miden节点...${NC}"
    
    if [ ! -d "$DATA_DIR" ]; then
        create_directories
    fi
    
    # 检查是否已引导
    if [ -d "$DATA_DIR/db" ]; then
        echo -e "${YELLOW}⚠ 检测到已有节点数据${NC}"
        read -p "是否重新引导? (这将删除现有数据) (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            echo "引导已取消"
            return 0
        fi
        rm -rf "$DATA_DIR"/*
    fi
    
    echo -e "${YELLOW}[信息] 选择引导方式:${NC}"
    echo "1) 使用默认配置引导 (推荐新手)"
    echo "2) 使用自定义genesis.toml文件引导"
    read -p "请选择 [1-2]: " bootstrap_choice
    
    case $bootstrap_choice in
        1)
            echo -e "${YELLOW}使用默认配置引导...${NC}"
            miden-node bundled bootstrap \
                --data-directory "$DATA_DIR" \
                --accounts-directory "$ACCOUNTS_DIR"
            ;;
        2)
            if [ ! -f "$CONFIG_DIR/genesis.toml" ]; then
                create_genesis_config
            fi
            echo -e "${YELLOW}使用自定义配置引导...${NC}"
            miden-node bundled bootstrap \
                --data-directory "$DATA_DIR" \
                --accounts-directory "$ACCOUNTS_DIR" \
                --genesis-config-file "$CONFIG_DIR/genesis.toml"
            ;;
        *)
            echo -e "${YELLOW}使用默认配置引导...${NC}"
            miden-node bundled bootstrap \
                --data-directory "$DATA_DIR" \
                --accounts-directory "$ACCOUNTS_DIR"
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 节点引导成功${NC}"
        
        # 检查生成的账户文件
        if [ -f "$ACCOUNTS_DIR/account.mac" ]; then
            echo -e "${GREEN}✓ 水龙头账户文件已创建${NC}"
            echo -e "${RED}⚠ 重要: 请妥善保管 $ACCOUNTS_DIR/account.mac 文件${NC}"
            echo -e "${RED}   此文件包含水龙头账户的私钥!${NC}"
        fi
    else
        echo -e "${RED}✗ 节点引导失败${NC}"
        return 1
    fi
}

# 启动节点
start_node() {
    echo -e "${YELLOW}[信息] 启动Miden节点...${NC}"
    
    # 检查是否已引导
    if [ ! -d "$DATA_DIR/db" ]; then
        echo -e "${RED}✗ 节点尚未引导，请先运行引导${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}[信息] 选择启动选项:${NC}"
    echo "1) 基本启动"
    echo "2) 启用OpenTelemetry监控"
    echo "3) 自定义RPC地址"
    echo "4) 后台运行"
    read -p "请选择 [1-4]: " start_choice
    
    case $start_choice in
        1)
            echo -e "${YELLOW}启动节点...${NC}"
            miden-node bundled start \
                --data-directory "$DATA_DIR" \
                --rpc.url "http://0.0.0.0:57291"
            ;;
        2)
            echo -e "${YELLOW}启动节点(启用监控)...${NC}"
            miden-node bundled start \
                --data-directory "$DATA_DIR" \
                --rpc.url "http://0.0.0.0:57291" \
                --enable-otel
            ;;
        3)
            read -p "输入RPC地址 [默认: http://0.0.0.0:57291]: " rpc_url
            rpc_url=${rpc_url:-"http://0.0.0.0:57291"}
            echo -e "${YELLOW}启动节点...${NC}"
            miden-node bundled start \
                --data-directory "$DATA_DIR" \
                --rpc.url "$rpc_url"
            ;;
        4)
            echo -e "${YELLOW}在后台启动节点...${NC}"
            nohup miden-node bundled start \
                --data-directory "$DATA_DIR" \
                --rpc.url "http://0.0.0.0:57291" > "$HOME/miden-node.log" 2>&1 &
            echo -e "${GREEN}✓ 节点已在后台启动${NC}"
            echo -e "${YELLOW}日志文件: $HOME/miden-node.log${NC}"
            ;;
        *)
            echo -e "${YELLOW}启动节点...${NC}"
            miden-node bundled start \
                --data-directory "$DATA_DIR" \
                --rpc.url "http://0.0.0.0:57291"
            ;;
    esac
}

# 检查节点状态
check_node_status() {
    echo -e "${YELLOW}[信息] 检查节点状态...${NC}"
    
    if command -v miden-node &> /dev/null; then
        echo -e "${GREEN}✓ Miden节点已安装${NC}"
        NODE_INSTALLED=true
    else
        echo -e "${RED}✗ Miden节点未安装${NC}"
        NODE_INSTALLED=false
    fi
    
    if [ -d "$DATA_DIR/db" ]; then
        echo -e "${GREEN}✓ 节点数据目录存在${NC}"
    else
        echo -e "${YELLOW}⚠ 节点数据目录不存在${NC}"
    fi
    
    if [ -f "$ACCOUNTS_DIR/account.mac" ]; then
        echo -e "${GREEN}✓ 水龙头账户文件存在${NC}"
    else
        echo -e "${YELLOW}⚠ 水龙头账户文件不存在${NC}"
    fi
    
    # 检查进程是否运行
    if pgrep -f "miden-node" > /dev/null; then
        echo -e "${GREEN}✓ 节点进程正在运行${NC}"
    else
        echo -e "${YELLOW}⚠ 节点进程未运行${NC}"
    fi
}

# 显示安装推荐
show_recommendation() {
    echo -e "${CYAN}=== 安装方式推荐 ===${NC}"
    echo
    if [ "$IS_UBUNTU" = true ] || [ "$IS_DEBIAN" = true ]; then
        echo -e "${GREEN}Debian包安装 (推荐生产环境):${NC}"
        echo "  ✓ 安装快速简单"
        echo "  ✓ 包含systemd服务"
        echo "  ✓ 自动更新管理"
        echo
        echo -e "${YELLOW}Cargo安装 (推荐开发环境):${NC}"
        echo "  ✓ 版本最新"
        echo "  ✓ 适合开发测试"
        echo "  ✓ 可定制性强"
    else
        echo -e "${YELLOW}Cargo安装 (唯一选择):${NC}"
        echo "  ✓ 跨平台支持"
        echo "  ✓ 版本最新"
    fi
    echo
}

# 主菜单
main_menu() {
    while true; do
        show_header
        check_node_status
        echo
        
        show_recommendation
        
        echo -e "${BLUE}请选择操作:${NC}"
        echo "1) 安装系统依赖"
        
        if [ "$IS_UBUNTU" = true ] || [ "$IS_DEBIAN" = true ]; then
            echo "2) 安装Miden节点 (Debian包 - 推荐生产)"
            echo "3) 安装Miden节点 (Cargo - 推荐开发)"
        else
            echo "2) 安装Miden节点 (Cargo)"
        fi
        
        echo "4) 引导节点"
        echo "5) 启动节点"
        echo "6) 创建Genesis配置"
        echo "7) 检查节点状态"
        echo "8) 显示系统信息"
        echo "9) 清理安装"
        echo "0) 退出"
        
        read -p "请输入选择 [0-9]: " choice
        
        case $choice in
            1) install_dependencies ;;
            2)
                if [ "$IS_UBUNTU" = true ] || [ "$IS_DEBIAN" = true ]; then
                    install_via_debian
                else
                    install_via_cargo
                fi
                ;;
            3) 
                if [ "$IS_UBUNTU" = true ] || [ "$IS_DEBIAN" = true ]; then
                    install_via_cargo
                else
                    echo -e "${RED}无效选择${NC}"
                fi
                ;;
            4) bootstrap_node ;;
            5) start_node ;;
            6) create_genesis_config ;;
            7) check_node_status ;;
            8) show_system_info ;;
            9) cleanup_installation ;;
            0) 
                echo -e "${GREEN}感谢使用Miden节点安装脚本！${NC}"
                exit 0
                ;;
            *) 
                echo -e "${RED}无效选择，请重新输入${NC}"
                ;;
        esac
        
        echo
        read -p "按回车键继续..."
    done
}

# 显示系统信息
show_system_info() {
    echo -e "${CYAN}=== 系统信息 ===${NC}"
    echo "操作系统: $(uname -s)"
    echo "架构: $(uname -m)"
    echo "主机名: $(hostname)"
    echo "用户: $(whoami)"
    echo -e "${CYAN}=== 节点信息 ===${NC}"
    echo "安装方法: ${INSTALL_METHOD:-未安装}"
    echo "数据目录: $DATA_DIR"
    echo "账户目录: $ACCOUNTS_DIR"
    echo "配置目录: $CONFIG_DIR"
    
    if command -v miden-node &> /dev/null; then
        echo "节点版本: $(miden-node --version 2>/dev/null || echo "未知")"
    fi
}

# 清理安装
cleanup_installation() {
    echo -e "${RED}[警告] 这将删除所有节点数据和配置${NC}"
    read -p "确定要继续吗? (y/N): " confirm
    
    if [[ $confirm == [yY] ]]; then
        echo -e "${YELLOW}[信息] 清理安装...${NC}"
        
        # 停止节点进程
        pkill -f "miden-node" 2>/dev/null
        
        # 删除目录
        rm -rf "$DATA_DIR"
        rm -rf "$ACCOUNTS_DIR"
        rm -rf "$CONFIG_DIR"
        
        # 删除安装的包
        if [ "$INSTALL_METHOD" == "debian" ]; then
            sudo dpkg -r miden-node 2>/dev/null
        fi
        
        # 删除日志文件
        rm -f "$HOME/miden-node.log"
        
        echo -e "${GREEN}✓ 清理完成${NC}"
    else
        echo -e "${YELLOW}取消清理操作${NC}"
    fi
}

# 初始化检查
initialize() {
    show_header
    check_system
    echo
    read -p "按回车键开始安装..."
}

# 主函数
main() {
    initialize
    main_menu
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
