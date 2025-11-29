#!/bin/bash

# Miden Node Ubuntu 快速安装脚本
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Miden Node Ubuntu 一键安装脚本 ===${NC}"

# 检查是否为 Ubuntu
if ! grep -q "Ubuntu" /etc/os-release; then
    echo -e "${YELLOW}警告: 这个脚本专为 Ubuntu 系统设计${NC}"
    read -p "是否继续? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 显示系统信息
echo -e "${GREEN}系统信息:${NC}"
lsb_release -a
echo -e "架构: $(uname -m)"
echo

# 检查是否已安装
if command -v miden-node &> /dev/null; then
    echo -e "${YELLOW}检测到已安装的 miden-node，版本: $(miden-node --version)${NC}"
    read -p "是否重新安装? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# 更新系统包
echo -e "${GREEN}[1/6] 更新系统包...${NC}"
sudo apt update
sudo apt upgrade -y

# 安装依赖
echo -e "${GREEN}[2/6] 安装编译依赖...${NC}"
sudo apt install -y \
    curl \
    wget \
    build-essential \
    llvm \
    clang \
    bindgen \
    pkg-config \
    libssl-dev \
    libsqlite3-dev \
    git \
    cmake

# 安装 Rust
echo -e "${GREEN}[3/6] 安装 Rust...${NC}"
if ! command -v rustc &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
else
    echo -e "${YELLOW}Rust 已安装: $(rustc --version)${NC}"
fi

# 验证 Rust 安装
if ! command -v rustc &> /dev/null; then
    echo -e "${RED}错误: Rust 安装失败${NC}"
    exit 1
fi

# 安装 Miden Node
echo -e "${GREEN}[4/6] 编译安装 Miden Node...${NC}"
echo -e "${YELLOW}这可能需要一些时间，请耐心等待...${NC}"
cargo install miden-node --locked

# 验证安装
if ! command -v miden-node &> /dev/null; then
    echo -e "${RED}错误: Miden Node 安装失败${NC}"
    exit 1
fi

echo -e "${GREEN}Miden Node 安装成功! 版本: $(miden-node --version)${NC}"

# 创建数据目录
echo -e "${GREEN}[5/6] 设置数据目录...${NC}"
read -p "请输入数据目录路径 [默认: ./miden-data]: " data_dir
data_dir=${data_dir:-"./miden-data"}

mkdir -p "$data_dir"
mkdir -p "$data_dir/accounts"

echo -e "数据目录: $(realpath $data_dir)"

# 初始化节点
echo -e "${GREEN}[6/6] 初始化节点...${NC}"
read -p "是否使用自定义创世配置文件? (y/n) [默认: n]: " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "请输入创世配置文件路径: " genesis_config
    if [ -f "$genesis_config" ]; then
        miden-node bundled bootstrap \
            --data-directory "$data_dir" \
            --accounts-directory "$data_dir/accounts" \
            --genesis-config-file "$genesis_config"
    else
        echo -e "${RED}错误: 文件不存在: $genesis_config${NC}"
        exit 1
    fi
else
    miden-node bundled bootstrap \
        --data-directory "$data_dir" \
        --accounts-directory "$data_dir/accounts"
fi

# 创建启动脚本
echo -e "${GREEN}创建启动脚本...${NC}"
cat > "start-miden-node.sh" << EOF
#!/bin/bash
# Miden Node 启动脚本

echo "启动 Miden Node..."
miden-node bundled start \\
    --data-directory "$(realpath $data_dir)" \\
    --rpc.url "http://0.0.0.0:57291"

EOF

chmod +x start-miden-node.sh

# 创建 systemd 服务（可选）
echo -e "${GREEN}创建 systemd 服务...${NC}"
read -p "是否创建 systemd 服务? (y/n) [默认: n]: " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    SERVICE_FILE="/etc/systemd/system/miden-node.service"
    
    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Miden Node
After=network.target
Wants=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME
ExecStart=$(which miden-node) bundled start \\
    --data-directory "$(realpath $data_dir)" \\
    --rpc.url "http://0.0.0.0:57291"
Restart=always
RestartSec=3
LimitNOFILE=65536

# 安全设置
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$(realpath $data_dir)

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    echo -e "${GREEN}systemd 服务创建完成!${NC}"
    echo -e "管理命令:"
    echo -e "  启动: ${YELLOW}sudo systemctl start miden-node${NC}"
    echo -e "  停止: ${YELLOW}sudo systemctl stop miden-node${NC}"
    echo -e "  状态: ${YELLOW}sudo systemctl status miden-node${NC}"
    echo -e "  日志: ${YELLOW}sudo journalctl -u miden-node -f${NC}"
    echo -e "  开机自启: ${YELLOW}sudo systemctl enable miden-node${NC}"
fi

# 显示完成信息
echo
echo -e "${GREEN}=== 安装完成! ===${NC}"
echo
echo -e "${YELLOW}重要信息:${NC}"
echo -e "节点版本: $(miden-node --version)"
echo -e "数据目录: $(realpath $data_dir)"
echo -e "账户目录: $(realpath $data_dir)/accounts"
echo
echo -e "${YELLOW}启动方式:${NC}"
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "使用 systemd: ${GREEN}sudo systemctl start miden-node${NC}"
else
    echo -e "手动启动: ${GREEN}./start-miden-node.sh${NC}"
fi
echo
echo -e "${YELLOW}RPC 端点:${NC} http://0.0.0.0:57291"
echo
echo -e "${YELLOW}下一步操作:${NC}"
echo -e "1. 启动节点"
echo -e "2. 检查日志确保节点正常运行"
echo -e "3. 配置防火墙开放端口 57291 (如果需要)"
echo
echo -e "${GREEN}祝使用愉快!${NC}"
