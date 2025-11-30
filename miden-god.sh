#!/bin/bash
# miden-god-dynamic-proxy.sh —— 动态代理专版 最新版（集成智能路由） - 已更新 CLI 命令
set -e

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[34m'; NC='\033[0m'
ACCOUNTS_DIR="miden_wallets"
LOG_DIR="miden_logs"
LOG_FILE="$LOG_DIR/ultimate.log"
PID_FILE="miden-god.pid"
PYTHON_BRUSH="miden_brush.py"
PROXY_ROUTER_CONF="/tmp/proxychains-god.conf"

mkdir -p "$ACCOUNTS_DIR" "$LOG_DIR"
chmod 755 "$ACCOUNTS_DIR" "$LOG_DIR"
touch "$LOG_FILE" 2>/dev/null || true
chmod 644 "$LOG_FILE" 2>/dev/null || true

banner() {
  clear
  echo -e "${BLUE}
  ███╗   █╗██╗██████╗ ███████╗███╗   ██╗     ██████╗  ██████╗ ██████╗ 
  ████╗  ██║██║██╔══██╗██╔════╝████╗  ██║    ██╔════╝ ██╔═══██╗██╔══██╗
  ██╔██╗ ██║██║██║  ██║█████╗  ██╔██╗ ██║    ██║  ███╗██║   ██║██║  ██║
  ██║╚██╗██║██║██║  ██║██╔══╝  ██║╚██╗██║    ██║   ██║██║   ██║██║  ██║
  ██║ ╚████║██║██████╔╝███████╗██║ ╚████║    ╚██████╔╝╚██████╔╝██████╔╝
  ╚═╝  ╚═══╝╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝     ╚═════╝  ╚═════╝ ╚═════╝ 
          动态代理专版 最新版 —— 集成智能路由 (CLI 0.13)
${NC}"
}

# 获取简洁的 Miden 版本信息
get_miden_version() {
    if command -v miden-client &>/dev/null; then
        version=$(miden-client --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
        if [[ -n "$version" ]]; then
            echo "$version"
        else
            echo "已安装"
        fi
    elif command -v miden &>/dev/null; then
        version=$(miden --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
        if [[ -n "$version" ]]; then
            echo "$version (旧版)"
        else
            echo "已安装 (旧版)"
        fi
    else
        echo "未安装"
    fi
}

# 获取代理信息
get_proxy_info() {
    if [[ -f "dynamic_proxy.conf" ]]; then
        proxy_line=$(grep -v '^#' dynamic_proxy.conf | head -1)
        if [[ "$proxy_line" == http* ]]; then
            temp="${proxy_line#http://}"
            ip_port="${temp#*@}"
            IFS=':' read -r ip port <<< "$ip_port"
            if [[ -n "$ip" && -n "$port" ]]; then
                echo "$ip:$port"
            else
                echo "配置错误"
            fi
        else
            IFS=':' read -r ip port user pass <<< "$proxy_line"
            if [[ -n "$ip" && -n "$port" ]]; then
                echo "$ip:$port"
            else
                echo "配置错误"
            fi
        fi
    else
        echo "未配置"
    fi
}

# 获取钱包数量
get_wallet_count() {
    if [[ -f "$ACCOUNTS_DIR/batch_accounts.txt" ]]; then
        count=$(wc -l < "$ACCOUNTS_DIR/batch_accounts.txt" 2>/dev/null || echo 0)
        echo "$count"
    else
        echo "0"
    fi
}

# 检查节点状态
check_node_status() {
    if pgrep -f "miden-node" >/dev/null; then
        echo "运行中"
    else
        echo "未运行"
    fi
}

# 检查代理路由状态
check_proxy_router_status() {
    if [[ -f "$PROXY_ROUTER_CONF" ]]; then
        if grep -qE "^http\s+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s+[0-9]+\s+[^\s]+\s+[^\s]+" "$PROXY_ROUTER_CONF" 2>/dev/null; then
            proxy_ip=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$PROXY_ROUTER_CONF" | head -1 2>/dev/null || echo "未知")
            echo "已配置 ($proxy_ip)"
        else
            echo "配置错误"
        fi
    else
        echo "未配置"
    fi
}

# ========== 智能代理路由功能 ==========

# 配置智能代理路由
setup_proxy_router() {
    echo -e "${BLUE}=== 智能代理路由配置 ===${NC}"
    echo
    echo -e "${YELLOW}此功能将配置：${NC}"
    echo "✅ 节点服务 -> 直连模式（保持稳定）"
    echo "✅ GOD脚本 -> 代理模式（动态IP）"
    echo
    
    if [[ ! -f "dynamic_proxy.conf" ]]; then
        echo -e "${RED}请先配置代理信息（选项2）${NC}"
        return 1
    fi
    
    # 获取代理配置
    proxy_line=$(grep -v '^#' dynamic_proxy.conf | head -1)
    
    # 解析代理字符串
    if [[ "$proxy_line" == http* ]]; then
        temp="${proxy_line#http://}"
        user_pass="${temp%@*}"
        ip_port="${temp#*@}"
        IFS=':' read -r user pass <<< "$user_pass"
        IFS=':' read -r ip port <<< "$ip_port"
        protocol="http"
    else
        IFS=':' read -r ip port user pass <<< "$proxy_line"
        protocol="http"
    fi
    
    if [[ -z "$ip" || -z "$port" || -z "$user" || -z "$pass" ]]; then
        echo -e "${RED}✗ 代理配置格式错误${NC}"
        return 1
    fi
    
    # 验证IP格式
    if ! [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}✗ IP地址格式错误: $ip${NC}"
        return 1
    fi
    
    # 验证端口格式
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}✗ 端口格式错误: $port${NC}"
        return 1
    fi
    
    # 创建代理路由配置
    cat > "$PROXY_ROUTER_CONF" <<EOF
strict_chain
proxy_dns
remote_dns_subnet 224
tcp_read_time_out 15000
tcp_connect_time_out 8000
localnet 127.0.0.0/255.0.0.0

[ProxyList]
$protocol $ip $port $user $pass
EOF

    echo -e "${GREEN}✅ 智能代理路由配置完成！${NC}"
    echo
    echo -e "${BLUE}路由配置：${NC}"
    echo "🔗 节点服务: 直连模式 (保持P2P稳定)"
    echo "🔄 GOD脚本: 代理模式 ($ip:$port)"
    echo
    echo -e "${YELLOW}现在GOD脚本将通过代理运行，节点服务保持直连${NC}"
}

# 测试代理路由
test_proxy_router() {
    echo -e "${YELLOW}测试代理路由...${NC}"
    
    if [[ ! -f "$PROXY_ROUTER_CONF" ]]; then
        echo -e "${RED}请先配置代理路由（选项10）${NC}"
        return 1
    fi
    
    # 检查代理配置格式
    if ! grep -qE "^http\s+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s+[0-9]+\s+[^\s]+\s+[^\s]+" "$PROXY_ROUTER_CONF"; then
        echo -e "${RED}❌ 代理路由配置格式错误${NC}"
        return 1
    fi
    
    echo -e "${GREEN}通过代理路由测试连接...${NC}"
    
    if timeout 10 proxychains -q -f "$PROXY_ROUTER_CONF" curl -s ipinfo.io/ip >/tmp/proxy_router_test.txt 2>/dev/null; then
        local ip=$(cat /tmp/proxy_router_test.txt)
        echo -e "${GREEN}✅ 代理路由连接成功！${NC}"
        echo -e "${BLUE}当前出口IP: $ip${NC}"
    else
        echo -e "${YELLOW}⚠️ 代理路由测试超时${NC}"
        echo -e "${YELLOW}但配置已生效，GOD脚本将通过代理运行${NC}"
    fi
    
    rm -f /tmp/proxy_router_test.txt
}

# 启动节点服务（直连模式）
start_node_direct() {
    echo -e "${YELLOW}启动节点服务（直连模式）...${NC}"
    
    # 停止现有节点
    pkill -f "miden-node" 2>/dev/null || true
    sleep 2
    
    # 确保节点使用直连模式
    if [[ -f "/etc/proxychains.conf" ]]; then
        sudo mv /etc/proxychains.conf /etc/proxychains.conf.bak.node 2>/dev/null || true
        echo -e "${YELLOW}已确保节点使用直连模式${NC}"
    fi
    
    # 启动节点
    nohup miden-node bundled start --data-directory ~/miden-data --rpc.url http://0.0.0.0:57291 > ~/miden-node.log 2>&1 &
    local node_pid=$!
    
    echo -e "${YELLOW}等待节点启动...${NC}"
    for i in {1..30}; do
        if grpcurl -plaintext -d '{}' localhost:57291 rpc.Api/Status >/dev/null 2>&1; then
            echo -e "${GREEN}✅ 节点启动成功 (PID: $node_pid)${NC}"
            echo -e "${BLUE}节点运行模式: 直连${NC}"
            return 0
        fi
        sleep 1
    done
    
    echo -e "${RED}❌ 节点启动失败，请检查日志: ~/miden-node.log${NC}"
    return 1
}

# 显示路由状态
show_router_status() {
    echo -e "${BLUE}=== 智能路由状态 ===${NC}"
    echo -e "节点服务: $(check_node_status)"
    echo -e "代理路由: $(check_proxy_router_status)"
    echo -e "GOD脚本: $(if [[ -f "$PID_FILE" ]]; then echo "运行中"; else echo "未运行"; fi)"
    
    if pgrep -f "miden-node" >/dev/null; then
        echo
        echo -e "${GREEN}✅ 节点运行正常，P2P使用直连IP${NC}"
    fi
    
    if [[ -f "$PROXY_ROUTER_CONF" ]]; then
        if grep -qE "^http\s+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s+[0-9]+\s+[^\s]+\s+[^\s]+" "$PROXY_ROUTER_CONF"; then
            echo -e "${GREEN}✅ GOD脚本将通过代理IP运行${NC}"
        else
            echo -e "${RED}❌ 代理路由配置错误${NC}"
        fi
    fi
}

# ========== 更新后的 CLI 命令功能 ==========

# 1) 一键安装所有依赖
install_deps() {
  echo -e "${YELLOW}正在安装所有依赖...${NC}"
  
  # 安装系统构建工具
  if command -v apt &>/dev/null; then
    sudo apt update -qq
    sudo apt install -y build-essential pkg-config libssl-dev curl wget python3-pip unzip proxychains4 libsqlite3-dev git grpcurl
  elif command -v yum &>/dev/null; then
    sudo yum groupinstall -y "Development Tools"
    sudo yum install -y pkgconfig openssl-devel curl wget python3-pip unzip proxychains-ng sqlite-devel git grpcurl
  fi
  
  # 安装 Rust
  if ! command -v rustc &>/dev/null; then
    echo -e "${YELLOW}安装 Rust...${NC}"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
  else
    echo -e "${GREEN}Rust 已安装${NC}"
  fi
  
  # 设置环境变量
  export PATH="$HOME/.cargo/bin:$PATH"
  echo "export PATH=\"\$HOME/.cargo/bin:\$PATH\"" >> ~/.bashrc
  
  # 安装 Miden 最新版本
  if ! command -v miden-client &>/dev/null; then
    echo -e "${YELLOW}安装 Miden 客户端最新版本...${NC}"
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # 克隆最新代码
    echo -e "${YELLOW}克隆 Miden 客户端仓库...${NC}"
    git clone https://github.com/0xMiden/miden-client.git
    cd miden-client
    
    # 构建项目
    echo -e "${YELLOW}构建 Miden 工作区...${NC}"
    cargo build --release --locked
    
    # 优先安装 miden-client，如果不存在则创建符号链接
    if [ -f "target/release/miden-client" ]; then
        sudo cp target/release/miden-client /usr/local/bin/miden-client
        # 创建 miden 的符号链接以保持兼容性
        sudo ln -sf /usr/local/bin/miden-client /usr/local/bin/miden
        echo -e "${GREEN}✅ Miden 客户端安装成功${NC}"
    elif [ -f "target/release/miden" ]; then
        sudo cp target/release/miden /usr/local/bin/miden-client
        sudo ln -sf /usr/local/bin/miden-client /usr/local/bin/miden
        echo -e "${GREEN}✅ Miden 客户端安装成功${NC}"
    else
        # 尝试安装第一个找到的可执行文件
        first_bin=$(find target/release/ -maxdepth 1 -type f -executable | head -1)
        if [ -n "$first_bin" ]; then
            sudo cp "$first_bin" /usr/local/bin/miden-client
            sudo ln -sf /usr/local/bin/miden-client /usr/local/bin/miden
            echo -e "${GREEN}✅ Miden 客户端安装成功 (使用 $(basename $first_bin))${NC}"
        else
            echo -e "${RED}❌ 错误：构建成功但未找到可执行文件${NC}"
            echo -e "${YELLOW}构建目录内容:${NC}"
            find target/release/ -maxdepth 2 -type f
            exit 1
        fi
    fi
    
    # 清理临时文件
    cd /
    rm -rf "$TEMP_DIR"
    
    # 下载必要的包文件
    echo -e "${YELLOW}下载必要的包文件...${NC}"
    mkdir -p ~/.miden/packages
    
    # 尝试下载包文件，如果失败则继续（客户端会在首次运行时自动生成）
    if wget -q "https://github.com/0xMiden/miden-client/releases/latest/download/basic-wallet.masp" -O ~/.miden/packages/basic-wallet.masp 2>/dev/null; then
        echo -e "${GREEN}✅ 下载 basic-wallet.masp 成功${NC}"
    else
        echo -e "${YELLOW}⚠️ 无法下载 basic-wallet.masp，将在首次运行时自动生成${NC}"
    fi
    
    if wget -q "https://github.com/0xMiden/miden-client/releases/latest/download/basic-account.masp" -O ~/.miden/packages/basic-account.masp 2>/dev/null; then
        echo -e "${GREEN}✅ 下载 basic-account.masp 成功${NC}"
    else
        echo -e "${YELLOW}⚠️ 无法下载 basic-account.masp，将在首次运行时自动生成${NC}"
    fi
    
    # 验证安装
    if command -v miden-client &>/dev/null; then
        echo -e "${GREEN}✅ 验证: miden-client 命令可用${NC}"
    else
        echo -e "${RED}❌ 验证失败: miden-client 命令不可用${NC}"
        exit 1
    fi
    
  else
    echo -e "${GREEN}Miden 客户端已安装${NC}"
  fi
  
  # 安装 Python 依赖
  echo -e "${YELLOW}安装 Python 依赖...${NC}"
  pip3 install --quiet selenium
  
  # 初始化客户端 - 连接到本地节点
  echo -e "${YELLOW}初始化 Miden 客户端...${NC}"
  miden-client init --network http://localhost:57291 2>/dev/null || true
  
  echo -e "${GREEN}所有依赖安装完成！${NC}"
  echo -e "${YELLOW}请运行: source ~/.bashrc${NC}"
}

# 2) 配置动态代理
setup_dynamic_proxy() {
  clear
  echo -e "${BLUE}=== 动态代理配置 ===${NC}"
  echo
  
  # 显示当前配置
  if [[ -f "dynamic_proxy.conf" ]]; then
    current_proxy=$(grep -v '^#' dynamic_proxy.conf | head -1)
    echo -e "${GREEN}当前配置:${NC}"
    echo "$current_proxy"
    echo
  fi
  
  echo -e "${YELLOW}请输入完整的代理信息:${NC}"
  echo
  echo -e "${GREEN}格式示例:${NC}"
  echo "http://用户名:密码@IP:端口"
  echo "或"
  echo "IP:端口:用户名:密码"
  echo
  echo -e "${BLUE}实际示例:${NC}"
  echo "74.81.81.81:823:username:password"
  echo "或"
  echo "http://username:password@74.81.81.81:823"
  echo
  
  read -p "请输入代理信息: " proxy_input
  
  if [[ -z "$proxy_input" ]]; then
    echo -e "${RED}代理信息不能为空！${NC}"
    return 1
  fi
  
  # 自动识别格式并转换为标准格式
  if [[ "$proxy_input" == http* ]]; then
    # 格式: http://user:pass@ip:port
    proxy_str="$proxy_input"
  else
    # 格式: ip:port:user:pass
    IFS=':' read -r ip port user pass <<< "$proxy_input"
    proxy_str="http://$user:$pass@$ip:$port"
  fi
  
  # 确认信息
  echo
  echo -e "${YELLOW}请确认代理信息:${NC}"
  echo "$proxy_str"
  echo
  
  read -p "是否保存此配置？(y/N): " confirm
  if [[ $confirm != "y" && $confirm != "Y" ]]; then
    echo -e "${YELLOW}已取消配置${NC}"
    return 0
  fi
  
  # 保存配置
  cat > dynamic_proxy.conf <<EOF
# 动态代理配置
$proxy_str
EOF
  
  echo -e "${GREEN}✓ 代理配置已保存到 dynamic_proxy.conf${NC}"
  
  # 应用到系统
  apply_proxy_config
}

# 应用到系统
apply_proxy_config() {
  if [[ ! -f "dynamic_proxy.conf" ]]; then
    echo -e "${RED}✗ 代理配置文件不存在${NC}"
    return 1
  fi
  
  proxy_line=$(grep -v '^#' dynamic_proxy.conf | head -1)
  
  # 解析代理字符串
  if [[ "$proxy_line" == http* ]]; then
    # 格式: http://user:pass@ip:port
    protocol="http"
    # 提取IP、端口、用户名、密码
    temp="${proxy_line#http://}"
    user_pass="${temp%@*}"
    ip_port="${temp#*@}"
    
    IFS=':' read -r user pass <<< "$user_pass"
    IFS=':' read -r ip port <<< "$ip_port"
  else
    # 格式: ip:port:user:pass
    IFS=':' read -r ip port user pass <<< "$proxy_line"
    protocol="http"
  fi
  
  if [[ -z "$ip" || -z "$port" || -z "$user" || -z "$pass" ]]; then
    echo -e "${RED}✗ 代理配置格式错误${NC}"
    return 1
  fi
  
  # 创建 proxychains 配置
  sudo tee /etc/proxychains.conf > /dev/null <<EOF
strict_chain
proxy_dns
remote_dns_subnet 224
tcp_read_time_out 15000
tcp_connect_time_out 8000
localnet 127.0.0.0/255.0.0.0

[ProxyList]
$protocol $ip $port $user $pass
EOF

  echo -e "${GREEN}✓ 代理配置已应用到系统${NC}"
  echo -e "${BLUE}代理信息:${NC}"
  echo "协议: $protocol"
  echo "地址: $ip:$port"
  echo "用户: $user"
  echo -e "${GREEN}配置完成！${NC}"
}

# 3) 测试代理连接
test_proxy() {
  echo -e "${YELLOW}测试代理连接...${NC}"
  
  if [[ ! -f "dynamic_proxy.conf" ]]; then
    echo -e "${RED}请先配置代理${NC}"
    return 1
  fi
  
  echo -e "${GREEN}正在测试代理连接（最多10秒）...${NC}"
  
  # 直接测试，完全静默
  if timeout 10 proxychains -q curl -s ipinfo.io/ip >/tmp/proxy_test_ip.txt 2>/dev/null; then
    local ip=$(cat /tmp/proxy_test_ip.txt)
    echo -e "${GREEN}✅ 代理连接成功！${NC}"
    echo -e "${BLUE}当前公网IP: $ip${NC}"
  else
    echo -e "${YELLOW}⚠️ 代理连接测试超时${NC}"
    echo -e "${YELLOW}但代理配置已生效，可以尝试直接使用${NC}"
  fi
  
  rm -f /tmp/proxy_test_ip.txt
  echo
}

# 4) 修复 Miden 客户端配置
fix_miden_client() {
    echo -e "${YELLOW}修复 Miden 客户端配置...${NC}"
    
    # 设置环境变量
    export PATH="$HOME/.cargo/bin:$PATH"
    echo "export PATH=\"\$HOME/.cargo/bin:\$PATH\"" >> ~/.bashrc
    source ~/.bashrc
    
    # 重新初始化客户端 - 连接到本地节点
    echo -e "${YELLOW}初始化 Miden 客户端...${NC}"
    miden-client init --network http://localhost:57291 2>/dev/null || true
    
    # 验证安装
    if command -v miden-client &>/dev/null; then
        echo -e "${GREEN}✅ Miden 客户端已正确配置${NC}"
        version=$(get_miden_version)
        echo -e "${BLUE}客户端版本: $version${NC}"
    else
        echo -e "${RED}❌ Miden 客户端配置失败${NC}"
        echo -e "${YELLOW}尝试重新安装...${NC}"
        install_deps
    fi
}

# 5) 生成钱包地址（使用代理路由）
gen_wallets() {
    echo -e "${YELLOW}检查 Miden 客户端状态...${NC}"
    
    export PATH="$HOME/.cargo/bin:$PATH"
    
    if ! command -v miden-client &>/dev/null; then
        echo -e "${RED}错误: Miden 客户端未安装，请先运行选项1安装依赖${NC}"
        return 1
    fi
    
    # 确保日志目录和文件存在
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
    chmod 755 "$LOG_DIR" 2>/dev/null || true
    chmod 644 "$LOG_FILE" 2>/dev/null || true
    
    read -p "生成多少个钱包？(默认10) > " total
    total=${total:-10}
    
    echo -e "${YELLOW}开始生成 $total 个钱包...${NC}"
    
    # 检查代理路由配置
    if [[ -f "$PROXY_ROUTER_CONF" ]]; then
        echo -e "${BLUE}🔗 通过代理路由生成钱包${NC}"
        # 测试代理路由是否有效
        if ! grep -qE "^http\s+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s+[0-9]+\s+[^\s]+\s+[^\s]+" "$PROXY_ROUTER_CONF" 2>/dev/null; then
            echo -e "${RED}❌ 代理路由配置格式错误，使用直连模式${NC}"
            USE_PROXY=false
        else
            USE_PROXY=true
            echo -e "${GREEN}✅ 代理路由配置有效${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️ 使用直连模式生成钱包${NC}"
        USE_PROXY=false
    fi
    
    success_count=0
    failed_count=0
    current_dir=$(pwd)
    
    # 清空之前的钱包列表
    > "$ACCOUNTS_DIR/batch_accounts.txt"
    
    for ((i=1;i<=total;i++)); do
        echo -e "\n${BLUE}=== 生成钱包 $i/$total ===${NC}"
        
        WALLET_DIR="$ACCOUNTS_DIR/wallet_$i"
        mkdir -p "$WALLET_DIR"
        cd "$WALLET_DIR" || {
            echo -e "${RED}无法进入目录 $WALLET_DIR${NC}"
            ((failed_count++))
            continue
        }
        
        # 使用代理路由初始化（如果配置了且有效）
        if [[ "$USE_PROXY" == "true" ]]; then
            echo -e "${YELLOW}通过代理路由初始化...${NC}"
            if ! proxychains -q -f "$PROXY_ROUTER_CONF" miden-client init --network http://localhost:57291 > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2); then
                echo -e "${YELLOW}代理路由失败，尝试直连...${NC}"
                miden-client init --network http://localhost:57291 > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2) || true
            fi
        else
            echo -e "${YELLOW}直连初始化...${NC}"
            miden-client init --network http://localhost:57291 > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2) || true
        fi
        
        # 生成钱包
        echo -e "${YELLOW}创建钱包...${NC}"
        if [[ "$USE_PROXY" == "true" ]]; then
            if ! proxychains -q -f "$PROXY_ROUTER_CONF" miden-client new-wallet --storage-mode public > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2); then
                echo -e "${YELLOW}代理创建失败，尝试直连创建...${NC}"
                miden-client new-wallet --storage-mode public > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2) || true
            fi
        else
            miden-client new-wallet --storage-mode public > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2) || true
        fi
        
        # 获取地址
        addr=$(miden-client account --list 2>/dev/null | grep -oE "0x[0-9a-f]+" | head -1)
        if [[ -n "$addr" ]]; then
            echo "$addr" >> "$current_dir/$ACCOUNTS_DIR/batch_accounts.txt"
            ((success_count++))
            echo -e "${GREEN}✅ 钱包 $i 生成成功: ${addr}${NC}"
        else
            ((failed_count++))
            echo -e "${YELLOW}⚠️ 钱包 $i 生成失败${NC}"
            # 显示错误信息
            if [[ -f "$LOG_FILE" ]]; then
                echo -e "${YELLOW}最近错误信息:${NC}"
                tail -5 "$LOG_FILE" | grep -i error 2>/dev/null || echo -e "${YELLOW}无具体错误信息${NC}"
            fi
        fi
        
        cd "$current_dir" || break
        echo -e "${GREEN}进度: $i/$total, 成功: $success_count, 失败: $failed_count${NC}"
        
        if [[ $i -lt $total ]]; then
            sleep 3
        fi
    done
    
    echo -e "\n${GREEN}生成完成！成功: $success_count/$total, 失败: $failed_count${NC}"
    if [[ $success_count -gt 0 ]]; then
        echo -e "${BLUE}钱包地址保存在: $ACCOUNTS_DIR/batch_accounts.txt${NC}"
    fi
}

# 6) 查看钱包列表
view_wallets() {
  if [[ -f "$ACCOUNTS_DIR/batch_accounts.txt" ]]; then
    echo -e "${YELLOW}钱包地址列表:${NC}"
    cat "$ACCOUNTS_DIR/batch_accounts.txt"
    count=$(get_wallet_count)
    echo -e "\n${GREEN}总计: $count 个钱包${NC}"
  else
    echo -e "${YELLOW}还没有生成钱包${NC}"
  fi
}

# 7) 启动动态代理刷子（使用代理路由）
start_dynamic_brush() {
  if ! command -v miden-client &>/dev/null; then
    echo -e "${RED}错误: Miden 客户端未安装${NC}"
    return 1
  fi
  
  if [[ ! -f "$ACCOUNTS_DIR/batch_accounts.txt" ]]; then
    echo -e "${RED}请先生成钱包地址${NC}"
    return 1
  fi
  
  echo -e "${YELLOW}启动动态代理刷子...${NC}"
  
  # 修改Python刷子脚本，使用代理路由
  cat > $PYTHON_BRUSH <<'EOF'
#!/usr/bin/env python3
import time
import random
import subprocess
import os
import glob
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait, Select
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options

print("🚀 动态代理刷子启动！")

# 读取钱包地址
accounts = []
with open("miden_wallets/batch_accounts.txt", "r") as f:
    accounts = [line.strip() for line in f if line.strip()]

print(f"找到 {len(accounts)} 个钱包地址")

def get_chrome_driver():
    """创建浏览器"""
    options = Options()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    
    driver = webdriver.Chrome(options=options)
    return driver

def faucet_claim(address):
    """领取水龙头"""
    driver = None
    try:
        driver = get_chrome_driver()
        print(f"[{time.strftime('%H:%M:%S')}] 为地址 {address[:12]}... 领取水龙头")
        
        driver.get("https://faucet.testnet.miden.io/")
        
        # 等待页面加载
        WebDriverWait(driver, 20).until(
            EC.presence_of_element_located((By.TAG_NAME, "body"))
        )
        
        # 填写地址
        address_input = WebDriverWait(driver, 15).until(
            EC.element_to_be_clickable((By.NAME, "recipient-address"))
        )
        address_input.clear()
        address_input.send_keys(address)
        
        # 选择金额
        amount_select = WebDriverWait(driver, 10).until(
            EC.presence_of_element_located((By.NAME, "token-amount"))
        )
        select = Select(amount_select)
        select.select_by_visible_text("1000")
        
        # 随机选择笔记类型
        if random.random() < 0.3:
            public_btn = WebDriverWait(driver, 10).until(
                EC.element_to_be_clickable((By.XPATH, "//button[contains(text(), 'SEND PUBLIC NOTE')]"))
            )
            public_btn.click()
            note_type = "Public"
        else:
            private_btn = WebDriverWait(driver, 10).until(
                EC.element_to_be_clickable((By.XPATH, "//button[contains(text(), 'SEND PRIVATE NOTE')]"))
            )
            private_btn.click()
            note_type = "Private"
        
        # 提交并等待成功
        success_element = WebDriverWait(driver, 60).until(
            EC.presence_of_element_located((By.XPATH, 
                "//div[contains(text(),'Successfully') or contains(text(),'successfully')]"))
        )
        
        print(f"✅ [{time.strftime('%H:%M:%S')}] 领取成功 | {address[:12]}... | {note_type}")
        return True
        
    except Exception as e:
        print(f"❌ [{time.strftime('%H:%M:%S')}] 领取失败: {str(e)}")
        return False
    finally:
        if driver:
            driver.quit()

def send_transaction():
    """发送交易"""
    try:
        amount = round(random.uniform(0.001, 0.1), 6)
        target_addr = random.choice(accounts)
        
        # 使用代理路由配置和新 CLI 命令
        cmd = ["proxychains", "-q", "-f", "/tmp/proxychains-god.conf", "miden-client", "send", "--target", target_addr, "--asset", f"{amount}::<FAUCET_ID>", "--note-type", "Public"]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            print(f"✅ [{time.strftime('%H:%M:%S')}] 交易成功: {amount} POL")
        else:
            print(f"❌ [{time.strftime('%H:%M:%S')}] 交易失败")
            
    except Exception as e:
        print(f"❌ [{time.strftime('%H:%M:%S')}] 交易错误: {str(e)}")

def create_note():
    """创建笔记"""
    try:
        amount = round(random.uniform(0.001, 0.05), 6)
        # 使用新 CLI 命令创建笔记
        cmd = ["proxychains", "-q", "-f", "/tmp/proxychains-god.conf", "miden-client", "mint", "--target", "<ACCOUNT_ID>", "--asset", f"{amount}::<FAUCET_ID>", "--note-type", "Private"]
        subprocess.run(cmd, capture_output=True, timeout=30)
        print(f"📝 [{time.strftime('%H:%M:%S')}] 创建笔记: {amount} POL")
    except:
        print(f"❌ [{time.strftime('%H:%M:%S')}] 创建笔记失败")

# 主循环
round_count = 0

while True:
    round_count += 1
    print(f"=== 第 {round_count} 轮开始 ===")
    
    random.shuffle(accounts)
    
    for account in accounts:
        faucet_claim(account)
        
        for _ in range(random.randint(2, 5)):
            if random.random() < 0.7:
                send_transaction()
            else:
                create_note()
            
            time.sleep(random.randint(10, 30))
    
    sleep_time = random.randint(300, 600)
    print(f"⏰ [{time.strftime('%H:%M:%S')}] 本轮结束，休息 {sleep_time//60} 分钟")
    time.sleep(sleep_time)
EOF

  chmod +x $PYTHON_BRUSH
  
  echo -e "${YELLOW}启动刷子进程...${NC}"
  nohup ./$PYTHON_BRUSH >> "$LOG_FILE" 2>&1 &
  echo $! > $PID_FILE
  
  echo -e "${GREEN}动态代理刷子已启动！${NC}"
  echo -e "${YELLOW}日志文件: $LOG_FILE${NC}"
  echo -e "${YELLOW}进程ID: $(cat $PID_FILE)${NC}"
}

# 8) 停止刷子
stop_brush() {
  if [[ -f $PID_FILE ]]; then
    kill $(cat $PID_FILE) 2>/dev/null && echo -e "${GREEN}刷子已停止${NC}" || echo -e "${YELLOW}刷子进程已结束${NC}"
    rm $PID_FILE
  else
    echo -e "${YELLOW}刷子未在运行${NC}"
  fi
}

# 9) 查看实时日志
view_logs() {
  if [[ -f "$LOG_FILE" ]]; then
    echo -e "${YELLOW}显示实时日志 (Ctrl+C 退出)...${NC}"
    tail -f "$LOG_FILE"
  else
    echo -e "${YELLOW}日志文件不存在${NC}"
  fi
}

# 主菜单
menu() {
  while true; do
    banner
    echo -e "${BLUE}=== Miden 动态代理刷子（智能路由版）===${NC}"
    echo "1) 一键安装所有依赖"
    echo "2) 配置动态代理"
    echo "3) 测试代理连接"
    echo "4) 修复 Miden 客户端"
    echo "5) 生成钱包地址"
    echo "6) 查看钱包列表"
    echo "7) 启动动态代理刷子"
    echo "8) 停止刷子"
    echo "9) 查看实时日志"
    echo "10) 🆕 配置智能代理路由"
    echo "11) 🆕 启动节点服务"
    echo "12) 🆕 测试代理路由"
    echo "13) 🆕 显示路由状态"
    echo "0) 退出"
    echo "============================"
    
    # 显示状态信息
    miden_version=$(get_miden_version)
    proxy_info=$(get_proxy_info)
    wallet_count=$(get_wallet_count)
    node_status=$(check_node_status)
    router_status=$(check_proxy_router_status)
    
    if [[ "$miden_version" != "未安装" ]]; then
        echo -e "${GREEN}✓ Miden: $miden_version${NC}"
    else
        echo -e "${RED}✗ Miden: 未安装${NC}"
    fi
    
    if [[ "$proxy_info" != "未配置" ]]; then
        echo -e "${GREEN}✓ 代理: $proxy_info${NC}"
    else
        echo -e "${RED}✗ 代理: 未配置${NC}"
    fi
    
    if [[ "$wallet_count" != "0" ]]; then
        echo -e "${GREEN}✓ 钱包: $wallet_count 个${NC}"
    else
        echo -e "${RED}✗ 钱包: 未生成${NC}"
    fi
    
    echo -e "${GREEN}✓ 节点: $node_status${NC}"
    echo -e "${GREEN}✓ 路由: $router_status${NC}"
    
    if [[ -f $PID_FILE ]]; then
        echo -e "${GREEN}✓ 刷子: 运行中${NC}"
    else
        echo -e "${YELLOW}○ 刷子: 未运行${NC}"
    fi
    
    echo "============================"
    
    read -p "输入数字 > " choice
    case $choice in
      1) install_deps;;
      2) setup_dynamic_proxy;;
      3) test_proxy;;
      4) fix_miden_client;;
      5) gen_wallets;;
      6) view_wallets;;
      7) start_dynamic_brush;;
      8) stop_brush;;
      9) view_logs;;
      10) setup_proxy_router;;
      11) start_node_direct;;
      12) test_proxy_router;;
      13) show_router_status;;
      0) echo "再见！"; exit 0;;
      *) echo -e "${RED}输入错误，请重新选择${NC}"; sleep 1;;
    esac
    
    echo
    read -p "按回车继续..."
  done
}

# 检查root权限
if [[ $EUID -eq 0 ]]; then
  echo -e "${RED}请不要使用root权限运行此脚本${NC}"
  exit 1
fi

# 启动主菜单
menu
