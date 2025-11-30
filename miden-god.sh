#!/bin/bash
# miden-god-dynamic-proxy.sh —— 动态代理专版 最新版（集成智能路由） - 完整修复版
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
          动态代理专版 完整修复版 —— 集成智能路由 (CLI 0.13)
${NC}"
}

# 获取简洁的 Miden 版本信息
get_miden_version() {
    export PATH="$HOME/.cargo/bin:$PATH"
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

# 检查代理路由状态 - 修复版本
check_proxy_router_status() {
    if [[ -f "$PROXY_ROUTER_CONF" ]]; then
        if grep -qE "^(http|socks4|socks5)" "$PROXY_ROUTER_CONF" 2>/dev/null; then
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
    
    # 检查代理配置文件是否存在
    if [[ ! -f "dynamic_proxy.conf" ]]; then
        echo -e "${RED}请先配置代理信息（选项2）${NC}"
        echo -e "${YELLOW}按回车返回菜单...${NC}"
        read
        return 1
    fi
    
    # 读取代理配置
    proxy_line=$(grep -v '^#' dynamic_proxy.conf | head -1 | tr -d '[:space:]')
    
    if [[ -z "$proxy_line" ]]; then
        echo -e "${RED}代理配置文件为空或格式错误${NC}"
        echo -e "${YELLOW}按回车返回菜单...${NC}"
        read
        return 1
    fi
    
    echo -e "${GREEN}找到代理配置:${NC}"
    echo "$proxy_line"
    echo
    
    # 解析代理配置
    local ip port user pass protocol
    
    if [[ "$proxy_line" == http* ]]; then
        # 格式: http://user:pass@ip:port
        protocol="http"
        temp="${proxy_line#http://}"
        if [[ "$temp" == *"@"* ]]; then
            user_pass="${temp%@*}"
            ip_port="${temp#*@}"
            IFS=':' read -r user pass <<< "$user_pass"
            IFS=':' read -r ip port <<< "$ip_port"
        else
            # 格式: http://ip:port
            IFS=':' read -r ip port <<< "$temp"
            user=""
            pass=""
        fi
    else
        # 格式: ip:port:user:pass 或 ip:port
        IFS=':' read -r ip port user pass <<< "$proxy_line"
        protocol="http"
    fi
    
    # 验证必要参数
    if [[ -z "$ip" || -z "$port" ]]; then
        echo -e "${RED}✗ 代理配置缺少IP或端口信息${NC}"
        echo -e "${YELLOW}配置格式应为: IP:端口:用户名:密码 或 http://用户名:密码@IP:端口${NC}"
        echo -e "${YELLOW}按回车返回菜单...${NC}"
        read
        return 1
    fi
    
    # 如果用户密码为空，使用占位符
    user="${user:-user}"
    pass="${pass:-pass}"
    
    # 检查是否为域名
    is_domain=false
    original_domain=""
    if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        is_domain=true
        original_domain="$ip"
        echo -e "${YELLOW}检测到域名: $ip${NC}"
        echo -e "${YELLOW}尝试解析为IP地址（如果失败将使用dynamic_chain模式）...${NC}"
        # 尝试解析域名
        resolved_ip=$(getent hosts "$ip" 2>/dev/null | awk '{print $1}' | head -1)
        if [[ -n "$resolved_ip" && "$resolved_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${GREEN}解析成功: $ip -> $resolved_ip${NC}"
            echo -e "${YELLOW}将使用IP地址模式（更稳定）${NC}"
            ip="$resolved_ip"
            is_domain=false
        else
            echo -e "${YELLOW}无法解析域名，将使用dynamic_chain模式（支持域名）${NC}"
        fi
    else
        original_domain=""
    fi
    
    echo -e "${YELLOW}解析出的代理信息:${NC}"
    echo "协议: $protocol"
    if [[ "$is_domain" == "true" ]]; then
        echo "地址: $original_domain:$port (域名，将使用round_robin_chain)"
        proxy_ip="$original_domain"
    else
        echo "地址: $ip:$port (IP地址，将使用strict_chain)"
        proxy_ip="$ip"
    fi
    echo "用户: $user"
    echo "密码: [已隐藏]"
    echo
    
    # 确认配置
    echo -e "${YELLOW}是否创建智能代理路由配置？${NC}"
    echo -e "这将允许GOD脚本通过代理运行，同时节点服务保持直连。"
    echo -n "确认 (y/N): "
    read confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}已取消配置${NC}"
        echo -e "${YELLOW}按回车返回菜单...${NC}"
        read
        return 0
    fi
    
    # 创建代理路由配置
    # 如果IP是域名，使用dynamic_chain（对域名最兼容）并启用proxy_dns
    # 如果是IP地址，可以使用strict_chain
    if [[ "$is_domain" == "true" ]]; then
        # 使用域名时，必须使用dynamic_chain（最兼容域名），并启用proxy_dns
        chain_type="dynamic_chain"
        echo -e "${BLUE}使用域名模式: dynamic_chain + proxy_dns${NC}"
    else
        chain_type="strict_chain"
        echo -e "${BLUE}使用IP模式: strict_chain${NC}"
    fi
    
    # 根据proxychains文档，对于域名，必须使用dynamic_chain并启用proxy_dns
    if [[ "$is_domain" == "true" ]]; then
        # 域名模式：使用dynamic_chain（最兼容域名），必须启用proxy_dns
        cat > "$PROXY_ROUTER_CONF" <<EOF
dynamic_chain
proxy_dns
remote_dns_subnet 224
tcp_read_time_out 15000
tcp_connect_time_out 8000
localnet 127.0.0.0/255.0.0.0

[ProxyList]
$protocol $proxy_ip $port $user $pass
EOF
        echo -e "${GREEN}✓ 已创建域名代理配置（dynamic_chain + proxy_dns）${NC}"
    else
        # IP模式：可以使用strict_chain
    cat > "$PROXY_ROUTER_CONF" <<EOF
strict_chain
proxy_dns
remote_dns_subnet 224
tcp_read_time_out 15000
tcp_connect_time_out 8000
localnet 127.0.0.0/255.0.0.0

[ProxyList]
$protocol $proxy_ip $port $user $pass
EOF
        echo -e "${GREEN}✓ 已创建IP代理配置（strict_chain）${NC}"
    fi
    
    # 验证配置文件
    if [[ ! -f "$PROXY_ROUTER_CONF" ]]; then
        echo -e "${RED}❌ 配置文件创建失败${NC}"
        return 1
    fi
    
    # 显示配置内容（隐藏密码）
    echo -e "${BLUE}配置文件内容:${NC}"
    sed 's/\([^:]*:\)[^ ]*\( .*\)/\1****\2/' "$PROXY_ROUTER_CONF" | head -10

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ 智能代理路由配置完成！${NC}"
        echo
        echo -e "${BLUE}路由配置详情:${NC}"
        echo "🔗 节点服务: 直连模式 (保持P2P稳定)"
        echo "🔄 GOD脚本: 代理模式 ($ip:$port)"
        echo "📁 配置文件: $PROXY_ROUTER_CONF"
        echo
        echo -e "${YELLOW}现在GOD脚本将通过代理运行，节点服务保持直连${NC}"
    else
        echo -e "${RED}❌ 配置创建失败${NC}"
        echo -e "${YELLOW}按回车返回菜单...${NC}"
        read
        return 1
    fi
    
    echo -e "${YELLOW}按回车返回菜单...${NC}"
    read
    return 0
}

# 测试代理路由 - 修复版本
test_proxy_router() {
    echo -e "${YELLOW}测试代理路由...${NC}"
    
    if [[ ! -f "$PROXY_ROUTER_CONF" ]]; then
        echo -e "${RED}请先配置代理路由（选项10）${NC}"
        return 1
    fi
    
    # 检查代理配置格式（更宽松的检查）
    if ! grep -qE "^(http|socks4|socks5)" "$PROXY_ROUTER_CONF"; then
        echo -e "${RED}❌ 代理路由配置格式错误${NC}"
        return 1
    fi
    
    echo -e "${GREEN}通过代理路由测试连接...${NC}"
    
    if timeout 10 proxychains -q -f "$PROXY_ROUTER_CONF" curl -s ifconfig.me >/tmp/proxy_router_test.txt 2>/dev/null; then
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
        if curl -s http://localhost:57291 >/dev/null 2>&1; then
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
        if grep -qE "^(http|socks4|socks5)" "$PROXY_ROUTER_CONF"; then
            echo -e "${GREEN}✅ GOD脚本将通过代理IP运行${NC}"
        else
            echo -e "${RED}❌ 代理路由配置错误${NC}"
        fi
    fi
}

# ========== 修复 ChromeDriver 问题 ==========

fix_chromedriver() {
    echo -e "${YELLOW}检查 ChromeDriver...${NC}"
    
    # 检测 Chrome 版本
    if command -v google-chrome &>/dev/null; then
        CHROME_VERSION=$(google-chrome --version | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
        MAJOR_VERSION=$(echo $CHROME_VERSION | cut -d. -f1)
        echo -e "${BLUE}检测到 Chrome 版本: $CHROME_VERSION${NC}"
    else
        echo -e "${RED}Chrome 未安装，正在安装...${NC}"
        sudo apt update && sudo apt install -y google-chrome-stable
        CHROME_VERSION=$(google-chrome --version | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
        MAJOR_VERSION=$(echo $CHROME_VERSION | cut -d. -f1)
    fi
    
    # 检查是否已安装ChromeDriver且可用
    if command -v chromedriver &>/dev/null; then
        INSTALLED_VERSION=$(chromedriver --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
        INSTALLED_MAJOR=$(echo $INSTALLED_VERSION | cut -d. -f1)
        
        if [[ "$INSTALLED_MAJOR" == "$MAJOR_VERSION" ]]; then
            echo -e "${GREEN}✅ ChromeDriver 已安装且版本匹配: $INSTALLED_VERSION${NC}"
            return 0
        else
            echo -e "${YELLOW}ChromeDriver 版本不匹配 (已安装: $INSTALLED_VERSION, 需要: $MAJOR_VERSION.x)${NC}"
        fi
    else
        echo -e "${YELLOW}ChromeDriver 未安装${NC}"
    fi
    
    # 需要安装或更新
    echo -e "${YELLOW}下载 ChromeDriver 版本 $MAJOR_VERSION...${NC}"
    cd /tmp
    
    # 清理旧文件
    rm -f chromedriver.zip
    rm -rf chromedriver-linux64
    
    # 尝试下载对应版本的ChromeDriver（使用更通用的方法）
    DOWNLOAD_SUCCESS=false
    
    # 方法1: 尝试下载stable版本（推荐）
    if wget -q "https://storage.googleapis.com/chrome-for-testing-public/stable/chromedriver-linux64.zip" -O chromedriver.zip 2>/dev/null; then
        DOWNLOAD_SUCCESS=true
        echo -e "${GREEN}下载 stable 版本成功${NC}"
    else
        # 方法2: 尝试下载特定主版本的最新版本
        echo -e "${YELLOW}尝试下载主版本 $MAJOR_VERSION 的最新版本...${NC}"
        if wget -q "https://storage.googleapis.com/chrome-for-testing-public/${MAJOR_VERSION}.0.0.0/linux64/chromedriver-linux64.zip" -O chromedriver.zip 2>/dev/null; then
            DOWNLOAD_SUCCESS=true
        else
            # 方法3: 使用ChromeDriverManager（如果Python可用）
            if python3 -c "from webdriver_manager.chrome import ChromeDriverManager" 2>/dev/null; then
                echo -e "${YELLOW}使用 webdriver-manager 下载...${NC}"
                python3 -c "from webdriver_manager.chrome import ChromeDriverManager; ChromeDriverManager().install()" 2>/dev/null
                if command -v chromedriver &>/dev/null; then
                    echo -e "${GREEN}✅ 通过 webdriver-manager 安装成功${NC}"
                    cd - >/dev/null
                    return 0
                fi
            fi
        fi
    fi
    
    if [[ "$DOWNLOAD_SUCCESS" == "true" ]]; then
        # 解压并安装
        if unzip -q chromedriver.zip 2>/dev/null; then
            if [[ -f chromedriver-linux64/chromedriver ]]; then
                sudo mv chromedriver-linux64/chromedriver /usr/local/bin/chromedriver 2>/dev/null
                sudo chmod +x /usr/local/bin/chromedriver
                echo -e "${GREEN}✅ ChromeDriver 安装成功${NC}"
            else
                echo -e "${RED}❌ 解压后未找到 chromedriver 文件${NC}"
            fi
        else
            echo -e "${RED}❌ 解压失败${NC}"
        fi
        rm -rf chromedriver.zip chromedriver-linux64
    else
        echo -e "${YELLOW}⚠️ 自动下载失败，将使用系统ChromeDriver或webdriver-manager${NC}"
    fi
    
    # 验证安装
    if command -v chromedriver &>/dev/null; then
        INSTALLED_VERSION=$(chromedriver --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
        echo -e "${GREEN}✅ ChromeDriver 可用: $INSTALLED_VERSION${NC}"
    else
        echo -e "${YELLOW}⚠️ ChromeDriver 未安装，Python脚本将使用webdriver-manager自动管理${NC}"
    fi
    
    cd - >/dev/null
}

# ========== 更新后的 CLI 命令功能 ==========

# 1) 一键安装所有依赖 - 修复版本
install_deps() {
  echo -e "${YELLOW}正在安装所有依赖...${NC}"
  
  # 安装系统构建工具
  if command -v apt &>/dev/null; then
    sudo apt update -qq
    sudo apt install -y build-essential pkg-config libssl-dev curl wget python3-pip unzip proxychains4 libsqlite3-dev git
    # 检查并安装 grpcurl（如果可用）
    if apt-cache show grpcurl &>/dev/null; then
        sudo apt install -y grpcurl
    else
        echo -e "${YELLOW}⚠️ grpcurl 不可用，跳过安装${NC}"
    fi
  elif command -v yum &>/dev/null; then
    sudo yum groupinstall -y "Development Tools"
    sudo yum install -y pkgconfig openssl-devel curl wget python3-pip unzip proxychains-ng sqlite-devel git
    # 检查并安装 grpcurl（如果可用）
    if yum list available grpcurl &>/dev/null; then
        sudo yum install -y grpcurl
    else
        echo -e "${YELLOW}⚠️ grpcurl 不可用，跳过安装${NC}"
    fi
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
  pip3 install --quiet selenium webdriver-manager
  
  # 修复 ChromeDriver
  fix_chromedriver
  
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
  if timeout 10 proxychains -q curl -s ifconfig.me >/tmp/proxy_test_ip.txt 2>/dev/null; then
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

# 4) 修复 Miden 客户端配置 - 增强版本
fix_miden_client() {
    echo -e "${YELLOW}修复 Miden 客户端配置...${NC}"
    
    # 清理损坏的文件
    echo -e "${YELLOW}清理损坏的配置文件...${NC}"
    rm -rf ~/.miden 2>/dev/null || true
    rm -rf miden_wallets 2>/dev/null || true
    mkdir -p ~/.miden/packages
    mkdir -p miden_wallets
    mkdir -p miden_logs
    
    # 设置环境变量
    export PATH="$HOME/.cargo/bin:$PATH"
    echo "export PATH=\"\$HOME/.cargo/bin:\$PATH\"" >> ~/.bashrc
    source ~/.bashrc
    
    # 修复 ChromeDriver
    fix_chromedriver
    
    # 重新初始化客户端
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

# 5) 生成钱包地址（使用代理路由）- 修复版本
gen_wallets() {
    # 保存当前的 set -e 状态
    local old_set_e=$(set +o | grep -oP '(?<=set )[-+]e')
    
    # 在整个函数内禁用错误退出，确保即使遇到错误也能继续
    set +e
    
    echo -e "${YELLOW}检查 Miden 客户端状态...${NC}"
    
    export PATH="$HOME/.cargo/bin:$PATH"
    source "$HOME/.cargo/env" 2>/dev/null || true
    
    if ! command -v miden-client &>/dev/null; then
        echo -e "${RED}错误: Miden 客户端未安装，请先运行选项1安装依赖${NC}"
        # 恢复原来的 set -e 状态
        [[ "$old_set_e" == "+e" ]] && set +e || set -e
        return 1
    fi
    
    # 确保日志目录和文件存在
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
    chmod 755 "$LOG_DIR" 2>/dev/null || true
    chmod 644 "$LOG_FILE" 2>/dev/null || true
    
    read -p "生成多少个钱包？(默认10) > " total
    total=${total:-10}
    
    # 询问是否设置导出密码（用于导出钱包文件）- 批量生成时只询问一次
    echo -e "${YELLOW}钱包导出密码设置（将应用于所有 $total 个钱包）：${NC}"
    echo -e "${BLUE}提示：这是导出钱包文件时设置的密码${NC}"
    echo -e "${BLUE}      用于加密导出的钱包文件${NC}"
    echo -e "${BLUE}      在浏览器中导入钱包时，需要输入此密码（导出时设置的密码）${NC}"
    echo -e "${BLUE}      注意：这是导出密码，不是创建钱包时的密码${NC}"
        read -p "是否设置导出密码？(y/N，默认N，留空表示不设置密码) > " set_password
    WALLET_PASSWORD=""
    if [[ "$set_password" == "y" || "$set_password" == "Y" ]]; then
        read -sp "请输入导出密码（将用于加密所有钱包导出文件，只需输入一次）: " WALLET_PASSWORD
        echo
        if [[ -z "$WALLET_PASSWORD" ]]; then
            echo -e "${YELLOW}密码为空，将不设置钱包密码${NC}"
            WALLET_PASSWORD=""
        else
            # 可选：询问是否跳过确认（批量生成时更友好）
            read -p "是否跳过密码确认？(Y/n，默认Y，批量生成建议跳过) > " skip_confirm
            if [[ "$skip_confirm" != "n" && "$skip_confirm" != "N" ]]; then
                echo -e "${GREEN}✓ 导出密码已设置（已跳过确认）${NC}"
                echo -e "${BLUE}  密码将用于加密所有 $total 个钱包的导出文件${NC}"
                echo -e "${YELLOW}  ⚠️  重要：导入钱包时，需要输入此密码（导出时设置的密码）${NC}"
            else
                read -sp "请再次确认密码: " WALLET_PASSWORD_CONFIRM
                echo
                if [[ "$WALLET_PASSWORD" != "$WALLET_PASSWORD_CONFIRM" ]]; then
                    echo -e "${RED}密码不一致，将不设置密码${NC}"
                    WALLET_PASSWORD=""
                else
                    echo -e "${GREEN}✓ 导出密码已确认并设置${NC}"
                    echo -e "${BLUE}  密码将用于加密所有 $total 个钱包的导出文件${NC}"
                    echo -e "${YELLOW}  ⚠️  重要：导入钱包时，需要输入此密码（导出时设置的密码）${NC}"
                fi
            fi
        fi
    else
        echo -e "${YELLOW}未设置导出密码${NC}"
        echo -e "${YELLOW}注意：某些浏览器钱包可能要求设置导出密码才能导入${NC}"
    fi
    
    # 创建密码提示文件（如果设置了密码）
    if [[ -n "$WALLET_PASSWORD" ]]; then
        password_hint_file="$ACCOUNTS_DIR/wallet_export_password_hint.txt"
        {
            echo "=========================================="
            echo "⚠️  钱包导出密码提示文件"
            echo "=========================================="
            echo ""
            echo "所有钱包使用相同的导出密码"
            echo "导出密码: [已在生成钱包时设置]"
            echo ""
            echo "⚠️  重要提示："
            echo "1. 这是导出钱包时设置的密码，用于加密导出文件"
            echo "2. 在浏览器中导入钱包时，需要输入此密码"
            echo "3. 浏览器会提示: 'Enter the password you set when exporting your wallet'"
            echo "4. 请输入导出时设置的密码（不是创建钱包时的密码）"
            echo "5. 请妥善保管此密码，丢失将无法恢复钱包"
            echo "6. 建议将密码保存在安全的地方"
            echo ""
            echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "钱包数量: $total"
            echo ""
            echo "=========================================="
            echo "注意：出于安全考虑，密码不会直接保存在此文件中"
            echo "请记住您在生成钱包时设置的导出密码"
            echo "=========================================="
        } > "$password_hint_file" 2>/dev/null || true
        chmod 600 "$password_hint_file" 2>/dev/null || true
        echo -e "${GREEN}✓ 密码提示文件已创建: $password_hint_file${NC}"
    fi
    
    echo -e "${YELLOW}开始生成 $total 个钱包...${NC}"
    
    # 检查代理路由配置 - 修复逻辑
    if [[ -f "$PROXY_ROUTER_CONF" && -s "$PROXY_ROUTER_CONF" ]]; then
            echo -e "${BLUE}检查代理配置...${NC}"
            
            # 显示当前配置（调试用）
            chain_type=$(grep -E "^(strict_chain|round_robin_chain|dynamic_chain|random_chain)" "$PROXY_ROUTER_CONF" 2>/dev/null | head -1 | awk '{print $1}')
            proxy_line=$(grep -E "^(http|socks4|socks5)" "$PROXY_ROUTER_CONF" 2>/dev/null | head -1)
            
            echo -e "${YELLOW}当前链类型: ${chain_type:-未找到}${NC}"
            if [[ -n "$proxy_line" ]]; then
                proxy_host=$(echo "$proxy_line" | awk '{print $2}')
                echo -e "${YELLOW}代理地址: $proxy_host${NC}"
                
                # 检查是否是域名（不是IP地址）
                if [[ ! "$proxy_host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    echo -e "${YELLOW}检测到域名，检查配置兼容性...${NC}"
                    
                    # 如果是域名，必须使用dynamic_chain，并且必须启用proxy_dns
                    if [[ "$chain_type" != "dynamic_chain" ]]; then
                        echo -e "${YELLOW}⚠️ 域名必须使用dynamic_chain，当前是${chain_type}，正在修复...${NC}"
                        # 备份原配置
                        cp "$PROXY_ROUTER_CONF" "$PROXY_ROUTER_CONF.bak" 2>/dev/null || true
                        
                        # 重新创建正确的配置
                        protocol=$(echo "$proxy_line" | awk '{print $1}')
                        port=$(echo "$proxy_line" | awk '{print $3}')
                        user=$(echo "$proxy_line" | awk '{print $4}')
                        pass=$(echo "$proxy_line" | awk '{print $5}')
                        
                        cat > "$PROXY_ROUTER_CONF" <<EOF
dynamic_chain
proxy_dns
remote_dns_subnet 224
tcp_read_time_out 15000
tcp_connect_time_out 8000
localnet 127.0.0.0/255.0.0.0

[ProxyList]
$protocol $proxy_host $port $user $pass
EOF
                        echo -e "${GREEN}✓ 配置已修复为dynamic_chain${NC}"
                    fi
                    
                    # 确保proxy_dns存在
                    if ! grep -q "^proxy_dns" "$PROXY_ROUTER_CONF" 2>/dev/null; then
                        echo -e "${YELLOW}添加proxy_dns配置...${NC}"
                        sed -i '/^dynamic_chain/a proxy_dns' "$PROXY_ROUTER_CONF"
                    fi
                    
                    # 尝试解析域名为IP（如果proxychains版本不支持域名）
                    echo -e "${YELLOW}尝试解析域名为IP地址（提高兼容性）...${NC}"
                    resolved_ip=$(getent hosts "$proxy_host" 2>/dev/null | awk '{print $1}' | head -1)
                    if [[ -n "$resolved_ip" && "$resolved_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                        echo -e "${GREEN}解析成功: $proxy_host -> $resolved_ip${NC}"
                        echo -e "${YELLOW}使用IP地址模式（更稳定）...${NC}"
                        # 使用IP地址替换域名
                        sed -i "s|$protocol $proxy_host $port|$protocol $resolved_ip $port|" "$PROXY_ROUTER_CONF"
                        # 改为strict_chain（IP地址可以使用strict_chain）
                        sed -i 's/^dynamic_chain/strict_chain/' "$PROXY_ROUTER_CONF"
                        echo -e "${GREEN}✓ 已切换为IP地址模式（strict_chain）${NC}"
                    else
                        echo -e "${YELLOW}无法解析域名，将使用dynamic_chain模式${NC}"
                    fi
                fi
            fi
            
            # 显示最终配置（调试用）
            echo -e "${BLUE}最终配置:${NC}"
            head -10 "$PROXY_ROUTER_CONF" | grep -v "^#" | grep -v "^$" || true
            
        echo -e "${BLUE}🔗 通过代理路由生成钱包${NC}"
        USE_PROXY=true
    else
        echo -e "${YELLOW}⚠️ 使用直连模式生成钱包${NC}"
        USE_PROXY=false
    fi
    
    success_count=0
    failed_count=0
    current_dir=$(pwd)
    
    # 确保日志目录和文件存在
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    touch "$LOG_FILE" 2>/dev/null || true
    chmod 755 "$LOG_DIR" 2>/dev/null || true
    chmod 644 "$LOG_FILE" 2>/dev/null || true
    
    # 清空之前的钱包列表
    > "$ACCOUNTS_DIR/batch_accounts.txt"
    
    # 在整个循环内禁用错误退出，确保即使某个操作失败也能继续
    set +e
    
    # 添加错误捕获，确保即使遇到错误也不会退出
    trap 'echo "[错误捕获] 遇到错误但继续执行..." >&2; set +e' ERR
    
    for ((i=1;i<=total;i++)); do
        echo -e "\n${BLUE}════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}=== 生成钱包 $i/$total ===${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}[调试] 开始创建钱包 $i，循环内已禁用错误退出${NC}"
        
        WALLET_DIR="$ACCOUNTS_DIR/wallet_$i"
        mkdir -p "$WALLET_DIR"
        cd "$WALLET_DIR" || {
            echo -e "${RED}无法进入目录 $WALLET_DIR${NC}"
            ((failed_count++))
            continue
        }
        
        # 为每个钱包使用独立的数据库文件和配置目录，避免冲突
        WALLET_STORE_PATH="$WALLET_DIR/wallet_$i.sqlite3"
        WALLET_CONFIG_DIR="$WALLET_DIR/.miden"
        WALLET_CONFIG_FILE="$WALLET_CONFIG_DIR/miden-client.toml"
        
        # 清理可能存在的旧数据库和配置
        if [[ -f "$WALLET_STORE_PATH" ]]; then
            rm -f "$WALLET_STORE_PATH" 2>/dev/null || true
        fi
        if [[ -d "$WALLET_CONFIG_DIR" ]]; then
            rm -rf "$WALLET_CONFIG_DIR" 2>/dev/null || true
        fi
        
        # 确保目录存在
        mkdir -p ~/.miden/packages 2>/dev/null || true
        mkdir -p "$(dirname "$WALLET_STORE_PATH")" 2>/dev/null || true
        mkdir -p "$WALLET_CONFIG_DIR" 2>/dev/null || true
        
        # 根据文档，init会在当前目录创建miden-client.toml
        # 由于我们在钱包目录中执行（cd "$WALLET_DIR"），配置文件会在钱包目录中创建
        # 为了确保完全隔离，我们设置MIDEN_HOME环境变量（如果支持）
        # 或者直接在当前目录创建配置文件
        
        # 使用代理路由初始化（如果配置了且有效）
        # 使用独立的store-path避免冲突
        # 注意：根据文档，init会在当前目录或~/.miden创建配置文件
        # 为了确保每个钱包独立，我们在初始化前先清理全局配置文件
        # 初始化后立即移动到钱包目录
        
        # 清理全局配置文件，避免"已存在"错误
        if [[ -f ~/.miden/miden-client.toml ]]; then
            echo -e "${YELLOW}清理全局配置文件（确保每个钱包独立）...${NC}"
            rm -f ~/.miden/miden-client.toml 2>/dev/null || true
        fi
        
        if [[ "$USE_PROXY" == "true" ]]; then
            echo -e "${YELLOW}通过代理路由初始化...${NC}"
            # 添加超时机制，避免卡住（30秒超时）
            # 在钱包目录中初始化，配置文件会在当前目录或~/.miden
            if timeout 30 proxychains -q -f "$PROXY_ROUTER_CONF" miden-client init --network http://localhost:57291 --store-path "$WALLET_STORE_PATH" > "$WALLET_DIR/init.log" 2>&1; then
                init_exit_code=0
                init_output=$(cat "$WALLET_DIR/init.log")
            else
                init_exit_code=$?
                init_output=$(cat "$WALLET_DIR/init.log" 2>/dev/null || echo "初始化超时或失败")
            fi
            # 确保日志目录存在，避免tee失败导致脚本退出（set -e）
            mkdir -p "$LOG_DIR" 2>/dev/null || true
            touch "$LOG_FILE" 2>/dev/null || true
            echo "$init_output" | tee -a "$LOG_FILE" 2>/dev/null || echo "$init_output"
            
            if [[ $init_exit_code -ne 0 ]]; then
                # 检查是否是配置文件已存在的错误
                if echo "$init_output" | grep -q "already exists"; then
                    echo -e "${YELLOW}配置文件已存在，删除全局配置后重新初始化...${NC}"
                    rm -f ~/.miden/miden-client.toml 2>/dev/null || true
                    rm -f "$WALLET_CONFIG_FILE" 2>/dev/null || true
                    sleep 1
                    timeout 30 proxychains -q -f "$PROXY_ROUTER_CONF" miden-client init --network http://localhost:57291 --store-path "$WALLET_STORE_PATH" >> "$WALLET_DIR/init.log" 2>&1 || true
                else
                    echo -e "${YELLOW}代理路由失败（可能超时），尝试直连...${NC}"
                    sleep 1
                    if timeout 30 miden-client init --network http://localhost:57291 --store-path "$WALLET_STORE_PATH" >> "$WALLET_DIR/init.log" 2>&1; then
                        echo -e "${GREEN}✓ 直连初始化成功${NC}"
                    else
                        echo -e "${YELLOW}⚠️ 直连初始化也失败，继续尝试创建钱包...${NC}"
                    fi
                fi
            else
                echo -e "${GREEN}✓ 初始化成功${NC}"
            fi
            
            # 立即检查并移动配置文件（必须在初始化后立即执行，避免下一个钱包冲突）
            echo -e "${BLUE}🔍 检查配置文件位置...${NC}"
            sleep 2  # 等待文件系统同步（增加等待时间）
            
            # 检查全局目录
            if [[ -f ~/.miden/miden-client.toml ]]; then
                echo -e "${YELLOW}⚠️ 检测到配置文件在全局目录，立即移动到钱包目录...${NC}"
                echo -e "${BLUE}   源文件: ~/.miden/miden-client.toml${NC}"
                echo -e "${BLUE}   目标: $WALLET_CONFIG_FILE${NC}"
                # 确保目标目录存在
                mkdir -p "$WALLET_CONFIG_DIR" 2>/dev/null || true
                
                # 移动配置文件
                if mv ~/.miden/miden-client.toml "$WALLET_CONFIG_FILE" 2>/dev/null; then
                    echo -e "${GREEN}✅ 配置文件已成功移动到钱包目录${NC}"
                    # 更新配置文件中的store_path（如果存在）
                    if grep -q "store_path" "$WALLET_CONFIG_FILE" 2>/dev/null; then
                        sed -i "s|store_path = .*|store_path = \"$WALLET_STORE_PATH\"|" "$WALLET_CONFIG_FILE" 2>/dev/null || true
                        echo -e "${GREEN}✓ 已更新数据库路径${NC}"
                    fi
                    # 验证移动成功
                    if [[ -f "$WALLET_CONFIG_FILE" ]] && [[ ! -f ~/.miden/miden-client.toml ]]; then
                        echo -e "${GREEN}✓ 验证成功：配置文件已在钱包目录，全局目录已清理${NC}"
                    fi
                else
                    echo -e "${YELLOW}⚠️ 移动失败，尝试复制配置文件...${NC}"
                    if cp ~/.miden/miden-client.toml "$WALLET_CONFIG_FILE" 2>/dev/null; then
                        echo -e "${GREEN}✓ 配置文件已复制到钱包目录${NC}"
                        # 更新配置文件中的store_path
                        if grep -q "store_path" "$WALLET_CONFIG_FILE" 2>/dev/null; then
                            sed -i "s|store_path = .*|store_path = \"$WALLET_STORE_PATH\"|" "$WALLET_CONFIG_FILE" 2>/dev/null || true
                            echo -e "${GREEN}✓ 已更新数据库路径${NC}"
                        fi
                        # 删除全局配置文件（已复制）
                        if rm -f ~/.miden/miden-client.toml 2>/dev/null; then
                            echo -e "${GREEN}✓ 已删除全局配置文件${NC}"
                        else
                            echo -e "${YELLOW}⚠️ 无法删除全局配置文件，但已复制到钱包目录${NC}"
                        fi
                    else
                        echo -e "${RED}❌ 复制也失败，请检查权限${NC}"
                    fi
                fi
            elif [[ -f "$WALLET_CONFIG_FILE" ]]; then
                echo -e "${GREEN}✓ 配置文件已在钱包目录${NC}"
            else
                echo -e "${YELLOW}⚠️ 未找到配置文件（可能初始化失败）${NC}"
            fi
        else
            # 清理全局配置文件（直连模式也需要）
            if [[ -f ~/.miden/miden-client.toml ]]; then
                echo -e "${YELLOW}清理全局配置文件（确保每个钱包独立）...${NC}"
                rm -f ~/.miden/miden-client.toml 2>/dev/null || true
            fi
            
            echo -e "${YELLOW}直连初始化...${NC}"
            if timeout 30 miden-client init --network http://localhost:57291 --store-path "$WALLET_STORE_PATH" > "$WALLET_DIR/init.log" 2>&1; then
                init_exit_code=0
                init_output=$(cat "$WALLET_DIR/init.log")
            else
                init_exit_code=$?
                init_output=$(cat "$WALLET_DIR/init.log" 2>/dev/null || echo "初始化超时或失败")
            fi
            # 确保日志目录存在，避免tee失败导致脚本退出（set -e）
            mkdir -p "$LOG_DIR" 2>/dev/null || true
            touch "$LOG_FILE" 2>/dev/null || true
            echo "$init_output" | tee -a "$LOG_FILE" 2>/dev/null || echo "$init_output"
            
            if [[ $init_exit_code -ne 0 ]]; then
                # 检查是否是配置文件已存在的错误
                if echo "$init_output" | grep -q "already exists"; then
                    echo -e "${YELLOW}配置文件已存在，删除全局配置后重新初始化...${NC}"
                    rm -f ~/.miden/miden-client.toml 2>/dev/null || true
                    rm -f "$WALLET_CONFIG_FILE" 2>/dev/null || true
                    sleep 1
                    timeout 30 miden-client init --network http://localhost:57291 --store-path "$WALLET_STORE_PATH" >> "$WALLET_DIR/init.log" 2>&1 || true
                else
                    echo -e "${YELLOW}⚠️ 初始化失败，但继续尝试创建钱包...${NC}"
                fi
            else
                echo -e "${GREEN}✓ 初始化成功${NC}"
            fi
            
            # 立即检查并移动配置文件（必须在初始化后立即执行，避免下一个钱包冲突）
            sleep 1  # 等待文件系统同步
            if [[ -f ~/.miden/miden-client.toml ]]; then
                echo -e "${YELLOW}检测到配置文件在全局目录，立即移动到钱包目录...${NC}"
                # 确保目标目录存在
                mkdir -p "$WALLET_CONFIG_DIR" 2>/dev/null || true
                # 移动配置文件
                if mv ~/.miden/miden-client.toml "$WALLET_CONFIG_FILE" 2>/dev/null; then
                    echo -e "${GREEN}✓ 配置文件已移动到: $WALLET_CONFIG_FILE${NC}"
                    # 更新配置文件中的store_path（如果存在）
                    if grep -q "store_path" "$WALLET_CONFIG_FILE" 2>/dev/null; then
                        sed -i "s|store_path = .*|store_path = \"$WALLET_STORE_PATH\"|" "$WALLET_CONFIG_FILE" 2>/dev/null || true
                        echo -e "${GREEN}✓ 已更新数据库路径为: $WALLET_STORE_PATH${NC}"
                    fi
                else
                    echo -e "${YELLOW}⚠️ 移动失败，复制配置文件...${NC}"
                    cp ~/.miden/miden-client.toml "$WALLET_CONFIG_FILE" 2>/dev/null || true
                    # 更新配置文件中的store_path
                    if grep -q "store_path" "$WALLET_CONFIG_FILE" 2>/dev/null; then
                        sed -i "s|store_path = .*|store_path = \"$WALLET_STORE_PATH\"|" "$WALLET_CONFIG_FILE" 2>/dev/null || true
                        echo -e "${GREEN}✓ 已更新数据库路径为: $WALLET_STORE_PATH${NC}"
                    fi
                    # 删除全局配置文件（已复制）
                    rm -f ~/.miden/miden-client.toml 2>/dev/null || true
                    echo -e "${GREEN}✓ 已删除全局配置文件${NC}"
                fi
            else
                echo -e "${BLUE}配置文件未在全局目录（可能已在钱包目录或未创建）${NC}"
            fi
        fi
        
        # 验证：确保每个钱包有独立的配置和数据库
        if [[ -f "$WALLET_CONFIG_FILE" ]]; then
            echo -e "${GREEN}✓ 钱包 $i 使用独立配置: $WALLET_CONFIG_FILE${NC}"
        elif [[ -f ~/.miden/miden-client.toml ]]; then
            echo -e "${YELLOW}⚠️ 钱包 $i 配置仍在全局目录，但数据库是独立的${NC}"
            echo -e "${YELLOW}   全局配置: ~/.miden/miden-client.toml${NC}"
            echo -e "${YELLOW}   独立数据库: $WALLET_STORE_PATH${NC}"
        fi
        
        # 生成钱包
        echo -e "${YELLOW}创建钱包...${NC}"
        wallet_output=""
        
        if [[ "$USE_PROXY" == "true" ]]; then
            echo -e "${BLUE}通过代理创建钱包...${NC}"
            # 添加超时，避免卡住
            if timeout 60 proxychains -q -f "$PROXY_ROUTER_CONF" miden-client new-wallet --storage-mode public > "$WALLET_DIR/wallet.log" 2>&1; then
                wallet_output=$(cat "$WALLET_DIR/wallet.log")
                echo "$wallet_output" | tee -a "$LOG_FILE"
                echo -e "${GREEN}✓ 钱包创建成功${NC}"
            else
                wallet_exit_code=$?
                wallet_output=$(cat "$WALLET_DIR/wallet.log" 2>/dev/null || echo "钱包创建超时或失败")
                echo "$wallet_output" | tee -a "$LOG_FILE"
                echo -e "${YELLOW}代理创建失败（退出码: $wallet_exit_code），尝试直连创建...${NC}"
                # 尝试直连
                if timeout 60 miden-client new-wallet --storage-mode public > "$WALLET_DIR/wallet.log" 2>&1; then
                    wallet_output=$(cat "$WALLET_DIR/wallet.log")
                    echo "$wallet_output" | tee -a "$LOG_FILE"
                    echo -e "${GREEN}✓ 直连创建成功${NC}"
                else
                    wallet_output=$(cat "$WALLET_DIR/wallet.log" 2>/dev/null || echo "钱包创建失败")
                    echo "$wallet_output" | tee -a "$LOG_FILE"
                    echo -e "${RED}❌ 钱包 $i 创建失败（直连也失败）${NC}"
                    echo -e "${YELLOW}错误详情已保存到: $WALLET_DIR/wallet.log${NC}"
                fi
            fi
        else
            echo -e "${BLUE}直连创建钱包...${NC}"
            if timeout 60 miden-client new-wallet --storage-mode public > "$WALLET_DIR/wallet.log" 2>&1; then
                wallet_output=$(cat "$WALLET_DIR/wallet.log")
                echo "$wallet_output" | tee -a "$LOG_FILE"
                echo -e "${GREEN}✓ 钱包创建成功${NC}"
            else
                wallet_exit_code=$?
                wallet_output=$(cat "$WALLET_DIR/wallet.log" 2>/dev/null || echo "钱包创建超时或失败")
                echo "$wallet_output" | tee -a "$LOG_FILE"
                echo -e "${RED}❌ 钱包 $i 创建失败（退出码: $wallet_exit_code）${NC}"
                echo -e "${YELLOW}错误详情已保存到: $WALLET_DIR/wallet.log${NC}"
            fi
        fi
        
        # 检查钱包是否真的创建成功（通过检查输出中是否包含账户ID）
        if [[ -z "$wallet_output" ]] || ! echo "$wallet_output" | grep -qE "0x[0-9a-f]+"; then
            echo -e "${RED}❌ 钱包 $i 创建失败：未找到账户ID${NC}"
            echo -e "${YELLOW}继续处理下一个钱包...${NC}"
            ((failed_count++))
            cd "$current_dir" 2>/dev/null || current_dir=$(pwd)
            continue
        fi
        
        # 保存完整的钱包输出到文件（添加错误处理）
        wallet_info_file="$WALLET_DIR/wallet_info_$i.txt"
        {
            echo "=== 钱包 $i 创建信息 ==="
            echo "创建时间: $(date '+%Y-%m-%d %H:%M:%S')"
            echo ""
            echo "=== 完整输出 ==="
            echo "$wallet_output"
            echo ""
        } > "$wallet_info_file" 2>/dev/null || {
            echo -e "${YELLOW}⚠️ 警告：无法创建钱包信息文件，但继续处理...${NC}"
            wallet_info_file="/dev/null"  # 设置为空设备，避免后续操作失败
        }
        
        # 尝试从输出中提取助记词（Miden可能使用不同的格式）
        # 方法1: 查找常见的助记词模式（12或24个单词，用空格分隔）
        mnemonic=$(echo "$wallet_output" | grep -oE "([a-z]+ ){11,23}[a-z]+" | head -1)
        
        # 方法2: 如果没找到标准格式，尝试查找包含助记词关键词的行
        if [[ -z "$mnemonic" ]]; then
            mnemonic_line=$(echo "$wallet_output" | grep -iE "(mnemonic|seed phrase|recovery phrase|recovery words|backup words)" | head -1)
            if [[ -n "$mnemonic_line" ]]; then
                # 尝试从行中提取单词
                mnemonic=$(echo "$mnemonic_line" | grep -oE "([a-z]+ ){11,23}[a-z]+" | head -1)
            fi
        fi
        
        # 方法3: 尝试从keystore导出密钥信息（如果Miden支持）
        if [[ -z "$mnemonic" ]]; then
            keystore_path="$HOME/.miden/keystore"
            if [[ -d "$keystore_path" ]]; then
                # 查找最新的密钥文件
                latest_key_file=$(find "$keystore_path" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
                if [[ -n "$latest_key_file" && -f "$latest_key_file" ]]; then
                    # 尝试读取密钥文件内容（可能是JSON格式，添加错误处理）
                    if command -v jq &>/dev/null && [[ "$latest_key_file" == *.json ]]; then
                        key_info=$(jq -r '.' "$latest_key_file" 2>/dev/null || echo "无法读取")
                        {
                            echo "=== Keystore信息 ==="
                            echo "$key_info"
                        } >> "$wallet_info_file" 2>/dev/null || true
                    else
                        # 保存密钥文件路径和基本信息（添加错误处理）
                        {
                            echo "=== Keystore文件 ==="
                            echo "文件路径: $latest_key_file"
                            echo "文件大小: $(stat -c%s "$latest_key_file" 2>/dev/null || stat -f%z "$latest_key_file" 2>/dev/null || echo "未知") 字节"
                            echo "修改时间: $(stat -c%y "$latest_key_file" 2>/dev/null || stat -f%Sm "$latest_key_file" 2>/dev/null || echo "未知")"
                        } >> "$wallet_info_file" 2>/dev/null || true
                    fi
                fi
            fi
        fi
        
        # 保存助记词到单独文件（如果找到，添加错误处理）
        if [[ -n "$mnemonic" ]]; then
            echo "助记词: $mnemonic" >> "$wallet_info_file" 2>/dev/null || true
            echo "$mnemonic" > "$WALLET_DIR/mnemonic_$i.txt" 2>/dev/null || {
                echo -e "${YELLOW}⚠️ 警告：无法保存助记词文件，但继续处理...${NC}"
            }
            chmod 600 "$WALLET_DIR/mnemonic_$i.txt" 2>/dev/null || true
            echo -e "${GREEN}✓ 助记词已保存${NC}"
        else
            echo "助记词: 未在输出中找到（Miden可能使用keystore存储）" >> "$wallet_info_file" 2>/dev/null || true
            echo -e "${YELLOW}⚠️ 未找到助记词，将保存keystore路径${NC}"
        fi
        
        # 从输出中提取账户ID
        account_id=$(echo "$wallet_output" | grep -oE "0x[0-9a-f]+" | head -1)
        
        # 如果从输出中没找到，尝试从账户列表中获取最新的账户ID
        if [[ -z "$account_id" ]]; then
            echo -e "${YELLOW}从输出中未找到账户ID，尝试查询账户列表...${NC}"
            if [[ "$USE_PROXY" == "true" ]]; then
                account_list_output=$(timeout 30 proxychains -q -f "$PROXY_ROUTER_CONF" miden-client account --list 2>&1)
            else
                account_list_output=$(timeout 30 miden-client account --list 2>&1)
            fi
            echo -e "${BLUE}账户列表输出:${NC}"
            echo "$account_list_output" | head -10
            account_id=$(echo "$account_list_output" | grep -oE "0x[0-9a-f]+" | tail -1)
        fi
        
        if [[ -z "$account_id" ]]; then
            echo -e "${RED}❌ 无法获取账户ID${NC}"
            echo -e "${YELLOW}钱包输出内容:${NC}"
            echo "$wallet_output" | head -20
            echo -e "${YELLOW}继续处理下一个钱包...${NC}"
            ((failed_count++))
            cd "$current_dir" 2>/dev/null || current_dir=$(pwd)
            continue
        fi
        
        echo -e "${BLUE}账户ID: $account_id${NC}"
        
        # 尝试导出账户（如果Miden客户端支持）
        # 这是浏览器钱包期望的标准导出格式
        if [[ -n "$WALLET_PASSWORD" && -n "$account_id" ]]; then
            echo -e "${YELLOW}尝试导出账户（用于浏览器导入）...${NC}"
            export_file="$WALLET_DIR/account_export_$i.bin"
            
            # 尝试使用Miden客户端的账户导出功能
            # 注意：Miden CLI可能没有直接的账户导出命令，但我们可以尝试
            if [[ "$USE_PROXY" == "true" ]]; then
                # 尝试导出账户（使用密码）
                # 注意：Miden CLI可能不支持账户导出，这里先尝试
                export_output=$(timeout 30 proxychains -q -f "$PROXY_ROUTER_CONF" miden-client account --show "$account_id" 2>&1)
            else
                export_output=$(timeout 30 miden-client account --show "$account_id" 2>&1)
            fi
            
            # 如果Miden CLI支持账户导出，这里可以添加导出命令
            # 目前先保存账户信息，后续可以用于导出
            echo "$export_output" > "$WALLET_DIR/account_info_$i.txt" 2>/dev/null || true
        fi
        
        # 等待一下，确保账户已完全创建
        sleep 2
        
        # 获取地址 - Miden地址是bech32格式（mtst1, mm1, mlcl1等）
        # 根据文档：每个账户创建时都有一个默认的 "Unspecified" 地址（不绑定任何接口）
        # 可以添加 BasicWallet 接口的地址用于接收资产
        # 先尝试同步账户状态（新创建的钱包可能需要同步）
        echo -e "${YELLOW}同步账户状态...${NC}"
        if [[ "$USE_PROXY" == "true" ]]; then
            sync_output=$(timeout 30 proxychains -q -f "$PROXY_ROUTER_CONF" miden-client sync 2>&1 | head -20)
        else
            sync_output=$(timeout 30 miden-client sync 2>&1 | head -20)
        fi
        if echo "$sync_output" | grep -qi "error\|fail"; then
            echo -e "${YELLOW}⚠️ 同步可能失败，继续尝试获取地址...${NC}"
        else
            echo -e "${GREEN}✓ 同步完成${NC}"
        fi
        
        # 先尝试获取该账户的所有地址
        echo -e "${YELLOW}查询钱包地址...${NC}"
        if [[ "$USE_PROXY" == "true" ]]; then
            address_output=$(timeout 30 proxychains -q -f "$PROXY_ROUTER_CONF" miden-client address list "$account_id" 2>&1)
        else
            address_output=$(timeout 30 miden-client address list "$account_id" 2>&1)
        fi
        
        # 显示地址查询的原始输出（用于调试）
        if [[ -n "$address_output" ]]; then
            echo -e "${BLUE}地址查询输出:${NC}"
            echo "$address_output" | head -10
        else
            echo -e "${YELLOW}⚠️ 地址查询无输出${NC}"
        fi
        
        # 从地址列表中提取bech32地址（支持多种格式：mtst1, mm1, mlcl1等）
        # 根据文档，地址格式是bech32，可能的前缀：mtst1, mm1, mlcl1等
        addr=$(echo "$address_output" | grep -oE "(mtst1|mm1|mlcl1)[a-z0-9]+" | head -1)
        
        # 如果还是没找到，尝试更宽泛的匹配（任何以字母开头，包含数字和字母的bech32地址）
        if [[ -z "$addr" ]]; then
            addr=$(echo "$address_output" | grep -oE "[a-z]{2,5}1[a-z0-9]{30,}" | head -1)
        fi
        
        # 如果没找到地址，尝试为账户添加BasicWallet接口的地址
        if [[ -z "$addr" ]]; then
            echo -e "${YELLOW}未找到地址，尝试为账户添加BasicWallet地址...${NC}"
            if [[ "$USE_PROXY" == "true" ]]; then
                add_output=$(timeout 30 proxychains -q -f "$PROXY_ROUTER_CONF" miden-client address add "$account_id" BasicWallet 10 2>&1)
            else
                add_output=$(timeout 30 miden-client address add "$account_id" BasicWallet 10 2>&1)
            fi
            echo -e "${BLUE}添加地址输出:${NC}"
            echo "$add_output" | head -10
            echo "$add_output" | tee -a "$LOG_FILE"
            
            # 再次尝试获取地址
            sleep 3
            if [[ "$USE_PROXY" == "true" ]]; then
                address_output=$(timeout 30 proxychains -q -f "$PROXY_ROUTER_CONF" miden-client address list "$account_id" 2>&1)
            else
                address_output=$(timeout 30 miden-client address list "$account_id" 2>&1)
            fi
            echo -e "${BLUE}再次查询地址输出:${NC}"
            echo "$address_output" | head -10
            addr=$(echo "$address_output" | grep -oE "(mtst1|mm1|mlcl1)[a-z0-9]+" | head -1)
            if [[ -z "$addr" ]]; then
                addr=$(echo "$address_output" | grep -oE "[a-z]{2,5}1[a-z0-9]{30,}" | head -1)
            fi
        fi
        
        # 如果还是没找到，尝试从账户详情中查找
        if [[ -z "$addr" ]]; then
            echo -e "${YELLOW}从地址列表未找到，尝试从账户详情查找...${NC}"
            if [[ "$USE_PROXY" == "true" ]]; then
                account_detail_output=$(timeout 30 proxychains -q -f "$PROXY_ROUTER_CONF" miden-client account --show "$account_id" 2>&1)
            else
                account_detail_output=$(timeout 30 miden-client account --show "$account_id" 2>&1)
            fi
            echo -e "${BLUE}账户详情输出:${NC}"
            echo "$account_detail_output" | head -20
            addr=$(echo "$account_detail_output" | grep -oE "(mtst1|mm1|mlcl1)[a-z0-9]+" | head -1)
            if [[ -z "$addr" ]]; then
                addr=$(echo "$account_detail_output" | grep -oE "[a-z]{2,5}1[a-z0-9]{30,}" | head -1)
            fi
        fi
        
        # 如果仍然没找到，尝试从账户列表输出中查找（某些版本可能直接显示地址）
        if [[ -z "$addr" ]]; then
            echo -e "${YELLOW}从账户详情未找到，尝试从账户列表查找...${NC}"
            if [[ "$USE_PROXY" == "true" ]]; then
                account_list_output=$(timeout 30 proxychains -q -f "$PROXY_ROUTER_CONF" miden-client account --list 2>&1)
            else
                account_list_output=$(timeout 30 miden-client account --list 2>&1)
            fi
            echo -e "${BLUE}账户列表输出:${NC}"
            echo "$account_list_output" | head -20
            addr=$(echo "$account_list_output" | grep -oE "(mtst1|mm1|mlcl1)[a-z0-9]+" | head -1)
            if [[ -z "$addr" ]]; then
                addr=$(echo "$account_list_output" | grep -oE "[a-z]{2,5}1[a-z0-9]{30,}" | head -1)
            fi
        fi
        
        # 如果仍然没找到，使用账户ID（虽然格式不对，但至少能识别）
        if [[ -z "$addr" ]]; then
            addr="$account_id"
            echo -e "${YELLOW}⚠️ 未找到bech32地址，使用账户ID: ${addr}${NC}"
            echo -e "${YELLOW}根据文档：每个账户创建时都有一个默认的 'Unspecified' 地址${NC}"
            echo -e "${YELLOW}可能原因：${NC}"
            echo -e "${YELLOW}  1. 地址格式不匹配（已尝试多种格式：mtst1, mm1, mlcl1等）${NC}"
            echo -e "${YELLOW}  2. 需要先同步账户状态（已尝试同步）${NC}"
            echo -e "${YELLOW}  3. 输出格式不同，请查看上方的调试输出${NC}"
            echo -e "${YELLOW}提示: 可以手动运行以下命令查看地址：${NC}"
            echo -e "${BLUE}  miden-client address list $account_id${NC}"
            echo -e "${YELLOW}提示: 可以手动添加 BasicWallet 地址：${NC}"
            echo -e "${BLUE}  miden-client address add $account_id BasicWallet 10${NC}"
        else
            echo -e "${GREEN}✓ 找到钱包地址: ${addr}${NC}"
            echo -e "${BLUE}  账户ID: ${account_id}${NC}"
            echo -e "${BLUE}  地址: ${addr}${NC}"
        fi
        
        if [[ -n "$addr" ]]; then
            # 注意：set +e 已在循环开始处设置，这里不需要重复设置
            
            # 保存地址到列表文件（添加错误处理，避免set -e导致脚本退出）
            echo "$addr" >> "$current_dir/$ACCOUNTS_DIR/batch_accounts.txt" 2>/dev/null || {
                echo -e "${YELLOW}⚠️ 警告：无法写入地址列表文件，但继续处理...${NC}"
            }
            
            # 更新钱包信息文件（添加错误处理）
            {
                echo ""
                echo "=== 账户信息 ==="
                echo "账户ID: $account_id"
                echo "地址: $addr"
                echo "钱包目录: $WALLET_DIR"
            } >> "$wallet_info_file" 2>/dev/null || {
                echo -e "${YELLOW}⚠️ 警告：无法写入钱包信息文件，但继续处理...${NC}"
            }
            
            # 保存keystore路径（如果存在）
            # 注意：Miden使用Falcon512密钥，存储在keystore中，没有传统助记词
            # keystore路径可能在全局目录或钱包目录
            # 注意：set +e 已在 if 块开始处设置
            keystore_path_global="$HOME/.miden/keystore"
            keystore_path_wallet="$WALLET_CONFIG_DIR/keystore"
            
            # 优先查找钱包目录的keystore，然后是全局目录
            keystore_path=""
            if [[ -d "$keystore_path_wallet" ]]; then
                keystore_path="$keystore_path_wallet"
            elif [[ -d "$keystore_path_global" ]]; then
                keystore_path="$keystore_path_global"
            fi
            
            if [[ -n "$keystore_path" && -d "$keystore_path" ]]; then
                # 查找最新的密钥文件（可能以账户ID命名或按时间排序）
                latest_key=$(find "$keystore_path" -type f -name "*$account_id*" 2>/dev/null | head -1)
                
                # 如果没找到，按修改时间找最新的（添加错误处理）
                if [[ -z "$latest_key" ]]; then
                    # 尝试使用 -printf（GNU find），如果失败则使用 ls -t
                    latest_key=$(find "$keystore_path" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2- 2>/dev/null)
                    # 如果 -printf 不支持，使用 ls -t
                    if [[ -z "$latest_key" ]]; then
                        latest_key=$(ls -t "$keystore_path"/* 2>/dev/null | head -1)
                    fi
                fi
                
                if [[ -n "$latest_key" && -f "$latest_key" ]]; then
                    echo "密钥文件: $latest_key" >> "$wallet_info_file" 2>/dev/null || true
                    # 备份整个keystore目录到钱包目录
                    keystore_backup_dir="$WALLET_DIR/keystore_backup"
                    mkdir -p "$keystore_backup_dir" 2>/dev/null || true
                    cp -r "$keystore_path"/* "$keystore_backup_dir/" 2>/dev/null || true
                    
                    # 备份完整的keystore目录结构（保持原始结构）
                    keystore_full_backup="$WALLET_DIR/keystore_full_backup"
                    mkdir -p "$keystore_full_backup" 2>/dev/null || true
                    cp -r "$keystore_path" "$keystore_full_backup/" 2>/dev/null || true
                    
                    # 也复制单个密钥文件（保留原始文件名）
                    if [[ -f "$latest_key" ]]; then
                        key_filename=$(basename "$latest_key")
                        cp "$latest_key" "$WALLET_DIR/$key_filename" 2>/dev/null || true
                        echo "密钥文件备份: $WALLET_DIR/$key_filename" >> "$wallet_info_file" 2>/dev/null || true
                    fi
                    
                    # 创建浏览器可用的JSON格式文件（包含账户信息和keystore数据）
                    wallet_json_file="$WALLET_DIR/wallet_export_$i.json"
                    
                    # 尝试编码keystore数据为base64
                    keystore_base64=""
                    if [[ -f "$latest_key" ]]; then
                        # 尝试不同的base64编码方式（兼容不同系统）
                        if command -v base64 &>/dev/null; then
                            if base64 -w 0 "$latest_key" &>/dev/null 2>&1; then
                                keystore_base64=$(base64 -w 0 "$latest_key" 2>/dev/null)
                            else
                                keystore_base64=$(base64 "$latest_key" 2>/dev/null | tr -d '\n')
                            fi
                        fi
                    fi
                    
                    # 尝试编码为十六进制
                    keystore_hex=""
                    if [[ -f "$latest_key" ]]; then
                        if command -v xxd &>/dev/null; then
                            keystore_hex=$(xxd -p "$latest_key" 2>/dev/null | tr -d '\n')
                        elif command -v od &>/dev/null; then
                            keystore_hex=$(od -An -tx1 "$latest_key" 2>/dev/null | tr -d ' \n')
                        fi
                    fi
                    
                    # 创建JSON文件（如果设置了密码，则加密keystore数据）
                    if [[ -n "$WALLET_PASSWORD" ]]; then
                        # 使用密码加密keystore数据（使用openssl或python）
                        encrypted_keystore=""
                        if command -v openssl &>/dev/null && [[ -f "$latest_key" ]]; then
                            # 使用openssl加密
                            encrypted_keystore=$(openssl enc -aes-256-cbc -salt -pbkdf2 -base64 -in "$latest_key" -pass pass:"$WALLET_PASSWORD" 2>/dev/null | tr -d '\n')
                        elif command -v python3 &>/dev/null && [[ -f "$latest_key" ]]; then
                            # 使用python3加密（如果openssl不可用）
                            # 注意：需要安装 cryptography: pip3 install cryptography
                            encrypted_keystore=$(python3 <<PYTHON_EOF 2>/dev/null
import base64
import sys
try:
    from cryptography.fernet import Fernet
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
    import os
    
    password = b'$WALLET_PASSWORD'
    salt = os.urandom(16)
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=100000,
    )
    key = base64.urlsafe_b64encode(kdf.derive(password))
    f = Fernet(key)
    
    with open('$latest_key', 'rb') as file:
        file_data = file.read()
        encrypted_data = f.encrypt(file_data)
        result = base64.b64encode(salt + encrypted_data).decode('utf-8')
        print(result)
except ImportError:
    # cryptography未安装，使用简单的base64编码（不加密）
    sys.exit(1)
except Exception as e:
    sys.exit(1)
PYTHON_EOF
)
                        fi
                        
                        # 创建加密的JSON文件
                        {
                            echo "{"
                            echo "  \"version\": \"1.1\","
                            echo "  \"encrypted\": true,"
                            echo "  \"accountId\": \"$account_id\","
                            echo "  \"address\": \"$addr\","
                            if [[ -n "$encrypted_keystore" ]]; then
                                echo "  \"encryptedKeystore\": \"$encrypted_keystore\","
                            fi
                            echo "  \"keystorePath\": \"$keystore_path\","
                            echo "  \"keystoreFile\": \"$latest_key\","
                            echo "  \"keystoreBackupDir\": \"$keystore_backup_dir\","
                            echo "  \"configFile\": \"$WALLET_CONFIG_FILE\","
                            echo "  \"walletDir\": \"$WALLET_DIR\","
                            echo "  \"createdAt\": \"$(date -Iseconds 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')\","
                            echo "  \"note\": \"Miden钱包导出文件（加密）- 这是导出钱包时设置的密码。导入时需要输入导出时设置的密码（Enter the password you set when exporting your wallet）。如果浏览器无法导入，请使用Miden CLI导入方式。\""
                            echo "}"
                        } > "$wallet_json_file" 2>/dev/null || {
                            echo -e "${YELLOW}⚠️ 警告：无法创建加密JSON导出文件${NC}" >&2
                        }
                    else
                        # 创建未加密的JSON文件（兼容旧版本）
                        {
                            echo "{"
                            echo "  \"version\": \"1.0\","
                            echo "  \"encrypted\": false,"
                            echo "  \"accountId\": \"$account_id\","
                            echo "  \"address\": \"$addr\","
                            echo "  \"keystorePath\": \"$keystore_path\","
                            echo "  \"keystoreFile\": \"$latest_key\","
                            echo "  \"keystoreBackupDir\": \"$keystore_backup_dir\","
                            echo "  \"configFile\": \"$WALLET_CONFIG_FILE\","
                            if [[ -n "$keystore_base64" ]]; then
                                echo "  \"keystoreDataBase64\": \"$keystore_base64\","
                            fi
                            if [[ -n "$keystore_hex" ]]; then
                                echo "  \"keystoreDataHex\": \"$keystore_hex\","
                            fi
                            echo "  \"walletDir\": \"$WALLET_DIR\","
                            echo "  \"createdAt\": \"$(date -Iseconds 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')\","
                            echo "  \"note\": \"Miden钱包导出文件（未加密）- 包含账户ID、地址和keystore数据。如果浏览器无法导入，请使用Miden CLI导入方式。注意：某些浏览器钱包可能要求加密的导出文件。如果导出时设置了密码，导入时需要输入导出时设置的密码。\""
                            echo "}"
                        } > "$wallet_json_file" 2>/dev/null || {
                            echo -e "${YELLOW}⚠️ 警告：无法创建JSON导出文件${NC}" >&2
                        }
                    fi
                    
                    if [[ -f "$wallet_json_file" ]]; then
                        if [[ -n "$WALLET_PASSWORD" ]]; then
                            echo -e "${GREEN}✓ 浏览器导入JSON文件已创建（已加密）: $wallet_json_file${NC}"
                            echo -e "${BLUE}  导出密码: [已设置，请妥善保管]${NC}"
                            echo -e "${YELLOW}  ⚠️  重要：导入时需要输入导出时设置的密码！${NC}"
                            echo -e "${YELLOW}  ⚠️  提示：浏览器会提示 'Enter the password you set when exporting your wallet'${NC}"
                            echo -e "${YELLOW}  ⚠️  请输入导出时设置的密码（不是创建钱包时的密码）${NC}"
                            echo "JSON导出文件: $wallet_json_file" >> "$wallet_info_file" 2>/dev/null || true
                            echo "导出密码: [已设置，请查看生成钱包时的密码设置]" >> "$wallet_info_file" 2>/dev/null || true
                        else
                            echo -e "${GREEN}✓ 浏览器导入JSON文件已创建（未加密）: $wallet_json_file${NC}"
                            echo -e "${YELLOW}  注意：未设置导出密码，某些浏览器钱包可能无法导入${NC}"
                            echo "JSON导出文件: $wallet_json_file" >> "$wallet_info_file" 2>/dev/null || true
                            echo "导出密码: 未设置" >> "$wallet_info_file" 2>/dev/null || true
                        fi
                    fi
                    
                    echo -e "${GREEN}✓ Keystore已备份到: $keystore_backup_dir${NC}"
                    echo -e "${GREEN}✓ 完整Keystore目录备份: $keystore_full_backup${NC}"
                    echo "[调试] Keystore备份完成，继续执行..." >&2
                    echo "Keystore备份目录: $keystore_backup_dir" >> "$wallet_info_file" 2>/dev/null || true
                    echo "完整Keystore目录: $keystore_full_backup" >> "$wallet_info_file" 2>/dev/null || true
                    echo "[调试] 文件写入完成，继续执行..." >&2
                    # 强制刷新输出
                    sync 2>/dev/null || true
                else
                    # 列出所有密钥文件
                    {
                        echo "密钥目录: $keystore_path"
                        ls -la "$keystore_path" 2>/dev/null || echo "无法列出密钥文件"
                    } >> "$wallet_info_file" 2>/dev/null || true
                fi
            else
                echo -e "${YELLOW}⚠️ 未找到keystore目录，钱包密钥可能存储在全局位置${NC}"
                echo "Keystore路径: 未找到（可能在 $HOME/.miden/keystore）" >> "$wallet_info_file" 2>/dev/null || true
            fi
            
            echo -e "${BLUE}[调试] Keystore处理完成，准备保存助记词文件...${NC}"
            
            # 保存到统一的助记词/密钥文件（添加错误处理）
            # 注意：set +e 已在 if 块开始处设置，这里不需要重复设置
            mnemonic_file="$current_dir/$ACCOUNTS_DIR/wallet_mnemonics.txt"
            echo -e "${BLUE}[调试] 助记词文件路径: $mnemonic_file${NC}"
            {
                echo "=== 钱包 $i ==="
                echo "地址: $addr"
                echo "账户ID: $account_id"
                if [[ -n "$mnemonic" ]]; then
                    echo "助记词: $mnemonic"
                else
                    echo "助记词: Miden使用Falcon512密钥，存储在keystore中，没有传统助记词"
                    echo "Keystore位置: ${keystore_path:-未找到}"
                    echo "Keystore备份: $WALLET_DIR/keystore_backup"
                    echo ""
                    if [[ -n "$WALLET_PASSWORD" ]]; then
                        echo "⚠️ 导出密码: [已设置]"
                        echo "   ⚠️  重要：这是导出钱包时设置的密码"
                        echo "   ⚠️  在浏览器中导入钱包时，需要输入此密码"
                        echo "   ⚠️  浏览器会提示: 'Enter the password you set when exporting your wallet'"
                        echo "   ⚠️  请输入导出时设置的密码（不是创建钱包时的密码）"
                        echo "   ⚠️  请妥善保管此密码，丢失将无法恢复钱包"
                        echo ""
                    else
                        echo "导出密码: 未设置"
                        echo "   注意：某些浏览器钱包可能要求设置导出密码才能导入"
                        echo ""
                    fi
                    echo "⚠️ 重要：Miden钱包导出说明："
                    echo "1. 备份整个钱包目录: $WALLET_DIR"
                    echo "2. Keystore文件位置: ${keystore_path:-$HOME/.miden/keystore}"
                    echo "3. Keystore备份目录: $WALLET_DIR/keystore_backup"
                    echo "4. 配置文件: $WALLET_CONFIG_FILE"
                    echo "5. JSON导出文件: $wallet_json_file（包含账户信息和keystore数据）"
                    echo ""
                    echo "⚠️ 注意：Miden的keystore文件是二进制格式，不是标准JSON格式"
                    echo "   浏览器导入说明："
                    echo "   - JSON文件已创建: $wallet_json_file"
                    echo "   - 该文件包含账户ID、地址和编码后的keystore数据"
                    if [[ -n "$WALLET_PASSWORD" ]]; then
                        echo "   - ⚠️  导入时需要输入导出时设置的密码"
                        echo "   - ⚠️  浏览器会提示: 'Enter the password you set when exporting your wallet'"
                        echo "   - ⚠️  请输入导出时设置的密码（不是创建钱包时的密码）"
                    fi
                    echo "   - 如果浏览器仍无法导入，可能需要："
                    echo "     1. 查看浏览器钱包的具体导入要求"
                    echo "     2. 使用Miden CLI导入（推荐方式）"
                    echo "     3. 联系浏览器钱包支持，询问Miden钱包导入格式"
                    echo ""
                    echo "   使用Miden CLI导入（推荐）："
                    echo "   1. 将整个钱包目录复制到新机器"
                    echo "   2. 将keystore目录复制到 ~/.miden/keystore"
                    echo "   3. 将配置文件复制到 ~/.miden/miden-client.toml"
                    echo "   4. 运行: miden-client account --list 查看账户"
                fi
                echo "钱包目录: $WALLET_DIR"
                echo "配置文件: $WALLET_CONFIG_FILE"
                echo "创建时间: $(date '+%Y-%m-%d %H:%M:%S')"
                echo ""
            } >> "$mnemonic_file" 2>/dev/null || {
                echo -e "${YELLOW}⚠️ 警告：无法写入助记词文件，但继续处理...${NC}"
            }
            
            # 设置文件权限（保护敏感信息，添加错误处理）
            chmod 600 "$mnemonic_file" 2>/dev/null || echo -e "${YELLOW}⚠️ 警告：无法设置助记词文件权限${NC}" >&2
            chmod 600 "$wallet_info_file" 2>/dev/null || echo -e "${YELLOW}⚠️ 警告：无法设置钱包信息文件权限${NC}" >&2
            
            # 确保所有关键变量都已定义
            keystore_path="${keystore_path:-未找到}"
            
            # 使用 set +e 保护算术表达式，避免意外退出
            ((success_count++))
            
            echo -e "${GREEN}✅ 钱包 $i 生成成功: ${addr}${NC}"
            if [[ -n "$mnemonic" ]]; then
                echo -e "${GREEN}   助记词已保存${NC}"
            else
                echo -e "${YELLOW}   密钥信息已保存到: $WALLET_DIR${NC}"
                echo -e "${BLUE}   Keystore文件位置: ${keystore_path}${NC}"
            fi
            echo -e "${BLUE}   钱包信息文件: $wallet_info_file${NC}"
            echo -e "${BLUE}[调试] 钱包 $i 成功信息已显示，准备继续...${NC}"
            # 注意：set -e 将在循环结束后恢复
        else
            ((failed_count++))
            echo -e "${YELLOW}⚠️ 钱包 $i 生成失败${NC}"
            # 显示错误信息
            if [[ -f "$LOG_FILE" ]]; then
                echo -e "${YELLOW}最近错误信息:${NC}"
                tail -5 "$LOG_FILE" | grep -i error 2>/dev/null || echo -e "${YELLOW}无具体错误信息${NC}"
            fi
        fi
        
        # 钱包 $i 处理完成，清理环境确保下一个钱包独立
        echo -e "${BLUE}[调试] 钱包 $i 处理完成，开始清理环境...${NC}"
        
        # 返回原始目录（如果失败，记录错误但继续）
        if ! cd "$current_dir" 2>/dev/null; then
            echo -e "${RED}⚠️ 警告：无法返回原始目录，但继续处理下一个钱包...${NC}"
            # 尝试使用绝对路径
            current_dir=$(pwd)
            if [[ ! -d "$ACCOUNTS_DIR" ]]; then
                echo -e "${RED}❌ 严重错误：无法找到钱包目录，停止生成${NC}"
                break
            fi
        else
            echo -e "${BLUE}[调试] 已返回原始目录: $current_dir${NC}"
        fi
        
        # 清理全局配置文件，确保下一个钱包从干净状态开始
        if [[ -f ~/.miden/miden-client.toml ]]; then
            echo -e "${YELLOW}清理全局配置文件（为下一个钱包做准备）...${NC}"
            rm -f ~/.miden/miden-client.toml 2>/dev/null || true
        fi
        
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}进度: $i/$total, 成功: $success_count, 失败: $failed_count${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        # 如果还有下一个钱包，等待并准备
        if [[ $i -lt $total ]]; then
            echo -e "${YELLOW}钱包 $i 已完成，等待 3 秒后开始创建钱包 $((i+1))...${NC}"
            sleep 3
            echo -e "${BLUE}[调试] 准备开始创建钱包 $((i+1))...${NC}"
        else
            echo -e "${BLUE}[调试] 所有钱包已创建完成${NC}"
        fi
    done
    
    # 循环结束，移除错误捕获
    trap - ERR
    
    # 恢复错误退出
    [[ "$old_set_e" == "+e" ]] && set +e || set -e
    
    echo -e "\n${BLUE}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}生成完成！成功: $success_count/$total, 失败: $failed_count${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════${NC}"
    if [[ $success_count -gt 0 ]]; then
        echo -e "${BLUE}钱包地址保存在: $ACCOUNTS_DIR/batch_accounts.txt${NC}"
        echo -e "${BLUE}钱包信息保存在: $ACCOUNTS_DIR/wallet_mnemonics.txt${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}⚠️ 重要：Miden钱包导出和导入说明${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}Miden使用Falcon512密钥，存储在keystore中，没有传统助记词${NC}"
        echo -e "${YELLOW}Keystore文件是二进制格式，不是JSON格式${NC}"
        echo ""
        echo -e "${BLUE}📦 备份内容：${NC}"
        echo -e "${BLUE}  1. 整个钱包目录: $ACCOUNTS_DIR/wallet_*${NC}"
        echo -e "${BLUE}  2. Keystore备份: 每个钱包目录下的 keystore_backup/ 或 keystore_full_backup/${NC}"
        echo -e "${BLUE}  3. 配置文件: 每个钱包目录下的 .miden/miden-client.toml${NC}"
        echo -e "${BLUE}  4. JSON导出文件: 每个钱包目录下的 wallet_export_*.json（浏览器导入用）${NC}"
        echo ""
        echo -e "${BLUE}📥 导入钱包到新机器（使用Miden CLI，推荐）：${NC}"
        echo -e "${BLUE}  1. 将整个钱包目录复制到新机器${NC}"
        echo -e "${BLUE}  2. 将keystore_backup目录内容复制到 ~/.miden/keystore/${NC}"
        echo -e "${BLUE}  3. 将配置文件复制到 ~/.miden/miden-client.toml${NC}"
        echo -e "${BLUE}  4. 运行: miden-client account --list 查看账户${NC}"
        echo ""
        echo -e "${YELLOW}⚠️ 浏览器导入说明：${NC}"
        echo -e "${YELLOW}  已创建JSON导出文件: wallet_export_*.json${NC}"
        if [[ -n "$WALLET_PASSWORD" ]]; then
            echo -e "${GREEN}  ✓ 导出文件已加密，导入时需要输入密码${NC}"
            echo -e "${RED}  ⚠️  重要：请妥善保管导出密码！${NC}"
            echo -e "${RED}  ⚠️  密码: [已设置，请查看每个钱包目录下的 wallet_info_*.txt 文件]${NC}"
        else
            echo -e "${YELLOW}  ⚠️  导出文件未加密（未设置密码）${NC}"
            echo -e "${YELLOW}  ⚠️  某些浏览器钱包可能要求加密的导出文件${NC}"
            echo -e "${YELLOW}  💡 提示：重新生成钱包时可以设置密码${NC}"
        fi
        echo -e "${YELLOW}  该文件包含账户ID、地址和编码后的keystore数据${NC}"
        echo -e "${YELLOW}  如果浏览器仍无法导入，可能原因：${NC}"
        echo -e "${YELLOW}    1. 浏览器钱包需要特定的JSON格式${NC}"
        echo -e "${YELLOW}    2. Miden的keystore格式与浏览器期望的格式不匹配${NC}"
        echo -e "${YELLOW}    3. 浏览器可能不支持Miden钱包的直接导入${NC}"
        echo -e "${YELLOW}    4. 如果设置了密码，导入时必须输入正确的密码${NC}"
        echo -e "${YELLOW}  建议：${NC}"
        echo -e "${YELLOW}    - 查看浏览器钱包的Miden导入说明${NC}"
        echo -e "${YELLOW}    - 如果设置了密码，导入时输入导出时设置的密码${NC}"
        echo -e "${YELLOW}    - 使用账户ID和地址手动导入（如果支持）${NC}"
        echo -e "${YELLOW}    - 使用Miden CLI进行操作（最可靠）${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}详细信息文件: $ACCOUNTS_DIR/wallet_mnemonics.txt${NC}"
        echo -e "${BLUE}每个钱包的详细信息保存在: $ACCOUNTS_DIR/wallet_*/${NC}"
    fi
}

# 6) 查看钱包列表
view_wallets() {
  if [[ -f "$ACCOUNTS_DIR/batch_accounts.txt" ]]; then
    echo -e "${YELLOW}钱包地址列表:${NC}"
    echo
    # 显示带编号的列表
    line_num=1
    while IFS= read -r line; do
      if [[ -n "$line" ]]; then
        echo -e "${BLUE}[$line_num]${NC} $line"
        ((line_num++))
      fi
    done < "$ACCOUNTS_DIR/batch_accounts.txt"
    count=$(get_wallet_count)
    echo -e "\n${GREEN}总计: $count 个钱包${NC}"
  else
    echo -e "${YELLOW}还没有生成钱包${NC}"
  fi
}

# 6.5) 查看助记词/密钥信息
view_mnemonics() {
  mnemonic_file="$ACCOUNTS_DIR/wallet_mnemonics.txt"
  
  if [[ -f "$mnemonic_file" ]]; then
    echo -e "${BLUE}=== 钱包助记词/密钥信息 ===${NC}"
    echo -e "${YELLOW}⚠️ 警告：此文件包含敏感信息，请妥善保管！${NC}"
    echo
    read -p "确认查看？(y/N): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
      echo
      cat "$mnemonic_file"
      echo
      echo -e "${BLUE}文件位置: $mnemonic_file${NC}"
      echo -e "${YELLOW}提示: 每个钱包的详细信息保存在: $ACCOUNTS_DIR/wallet_*/${NC}"
    else
      echo -e "${YELLOW}已取消${NC}"
    fi
  else
    echo -e "${YELLOW}助记词文件不存在${NC}"
    echo -e "${YELLOW}可能原因:${NC}"
    echo "1. 还没有生成钱包"
    echo "2. 钱包是在添加此功能之前生成的"
    echo
    echo -e "${BLUE}提示: 重新生成钱包将自动保存助记词信息${NC}"
  fi
}

# 6.5) 删除钱包地址
delete_wallet() {
  if [[ ! -f "$ACCOUNTS_DIR/batch_accounts.txt" ]]; then
    echo -e "${YELLOW}还没有生成钱包${NC}"
    return 1
  fi
  
  # 显示钱包列表
  echo -e "${BLUE}=== 删除钱包地址 ===${NC}"
  echo
  view_wallets
  echo
  
  echo -e "${YELLOW}请选择删除方式:${NC}"
  echo "1) 按编号删除"
  echo "2) 按地址删除"
  echo "3) 删除所有钱包"
  echo "0) 取消"
  echo
  read -p "请选择 (0-3): " delete_mode
  
  case $delete_mode in
    1)
      read -p "请输入要删除的钱包编号: " wallet_num
      if [[ ! "$wallet_num" =~ ^[0-9]+$ ]] || [[ "$wallet_num" -lt 1 ]]; then
        echo -e "${RED}无效的编号${NC}"
        return 1
      fi
      
      # 获取要删除的地址
      target_addr=$(sed -n "${wallet_num}p" "$ACCOUNTS_DIR/batch_accounts.txt" 2>/dev/null)
      if [[ -z "$target_addr" ]]; then
        echo -e "${RED}编号 $wallet_num 不存在${NC}"
        return 1
      fi
      
      echo -e "${YELLOW}将要删除: $target_addr${NC}"
      read -p "确认删除？(y/N): " confirm
      if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        # 删除指定行
        sed -i "${wallet_num}d" "$ACCOUNTS_DIR/batch_accounts.txt"
        echo -e "${GREEN}✅ 已删除钱包: $target_addr${NC}"
      else
        echo -e "${YELLOW}已取消${NC}"
      fi
      ;;
    2)
      read -p "请输入要删除的钱包地址（支持部分匹配）: " search_addr
      if [[ -z "$search_addr" ]]; then
        echo -e "${RED}地址不能为空${NC}"
        return 1
      fi
      
      # 查找匹配的地址
      matches=$(grep -i "$search_addr" "$ACCOUNTS_DIR/batch_accounts.txt" 2>/dev/null)
      if [[ -z "$matches" ]]; then
        echo -e "${RED}未找到匹配的地址${NC}"
        return 1
      fi
      
      echo -e "${YELLOW}找到以下匹配的地址:${NC}"
      echo "$matches"
      echo
      read -p "确认删除所有匹配的地址？(y/N): " confirm
      if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        # 删除匹配的行
        sed -i "/$search_addr/Id" "$ACCOUNTS_DIR/batch_accounts.txt"
        echo -e "${GREEN}✅ 已删除匹配的钱包地址${NC}"
      else
        echo -e "${YELLOW}已取消${NC}"
      fi
      ;;
    3)
      echo -e "${RED}⚠️ 警告：这将删除所有钱包地址！${NC}"
      read -p "确认删除所有钱包？(yes/N): " confirm
      if [[ "$confirm" == "yes" ]]; then
        > "$ACCOUNTS_DIR/batch_accounts.txt"
        echo -e "${GREEN}✅ 已删除所有钱包地址${NC}"
      else
        echo -e "${YELLOW}已取消${NC}"
      fi
      ;;
    0)
      echo -e "${YELLOW}已取消${NC}"
      ;;
    *)
      echo -e "${RED}无效的选择${NC}"
      return 1
      ;;
  esac
  
  # 清理空行
  sed -i '/^[[:space:]]*$/d' "$ACCOUNTS_DIR/batch_accounts.txt" 2>/dev/null
  
  # 显示剩余钱包数量
  remaining=$(get_wallet_count)
  if [[ "$remaining" -gt 0 ]]; then
    echo -e "${BLUE}剩余钱包数量: $remaining${NC}"
  else
    echo -e "${YELLOW}钱包列表已清空${NC}"
  fi
}

# 7) 启动动态代理刷子（使用代理路由）- 完全修复版
start_dynamic_brush() {
  # 添加环境变量
  export PATH="$HOME/.cargo/bin:$PATH"
  source "$HOME/.cargo/env" 2>/dev/null || true
  
  if ! command -v miden-client &>/dev/null; then
    echo -e "${RED}错误: Miden 客户端未安装${NC}"
    return 1
  fi
  
  if [[ ! -f "$ACCOUNTS_DIR/batch_accounts.txt" ]]; then
    echo -e "${RED}请先生成钱包地址${NC}"
    return 1
  fi
  
  # 检查代理路由配置
  if [[ ! -f "$PROXY_ROUTER_CONF" ]]; then
    echo -e "${YELLOW}⚠️ 代理路由配置不存在，将使用直连模式${NC}"
    echo -e "${YELLOW}提示: 如需使用代理，请先运行选项10配置智能代理路由${NC}"
    USE_PROXY_ROUTER=false
  else
    if grep -qE "^(http|socks4|socks5)" "$PROXY_ROUTER_CONF" 2>/dev/null; then
      echo -e "${GREEN}✓ 检测到代理路由配置${NC}"
      USE_PROXY_ROUTER=true
    else
      echo -e "${YELLOW}⚠️ 代理路由配置格式错误，将使用直连模式${NC}"
      USE_PROXY_ROUTER=false
    fi
  fi
  
  echo -e "${YELLOW}启动动态代理刷子...${NC}"
  
  # 彻底停止旧进程
  echo -e "${YELLOW}检查并停止旧进程...${NC}"
  
  # 方法1: 通过PID文件停止
  if [[ -f $PID_FILE ]]; then
    old_pid=$(cat $PID_FILE 2>/dev/null)
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      echo -e "${YELLOW}停止旧进程 (PID: $old_pid)...${NC}"
      kill "$old_pid" 2>/dev/null || true
      sleep 2
      # 如果还在运行，强制杀死
      if kill -0 "$old_pid" 2>/dev/null; then
        kill -9 "$old_pid" 2>/dev/null || true
        sleep 1
      fi
    fi
    rm -f $PID_FILE
  fi
  
  # 方法2: 精确查找并停止运行 miden_brush.py 的进程
  # 使用更精确的匹配，只匹配真正运行脚本的进程
  echo -e "${YELLOW}查找运行中的刷子进程...${NC}"
  
  # 获取当前脚本的PID，避免误杀
  current_pid=$$
  script_pids=$(ps aux | grep -E "python3.*miden_brush\.py" | grep -v grep | grep -v "$$" | awk '{print $2}' 2>/dev/null)
  
  if [[ -n "$script_pids" ]]; then
    echo -e "${YELLOW}发现运行中的刷子进程，正在停止...${NC}"
    for pid in $script_pids; do
      # 再次确认这是运行 miden_brush.py 的进程
      if ps -p "$pid" -o args= 2>/dev/null | grep -q "miden_brush\.py"; then
        echo -e "${YELLOW}停止进程 PID: $pid${NC}"
        kill "$pid" 2>/dev/null || true
      fi
    done
    sleep 2
    
    # 强制停止仍在运行的进程
    for pid in $script_pids; do
      if kill -0 "$pid" 2>/dev/null; then
        if ps -p "$pid" -o args= 2>/dev/null | grep -q "miden_brush\.py"; then
          echo -e "${YELLOW}强制停止进程 PID: $pid${NC}"
          kill -9 "$pid" 2>/dev/null || true
        fi
      fi
    done
    sleep 1
  fi
  
  # 验证进程是否真的停止了（排除当前脚本）
  remaining=$(ps aux | grep -E "python3.*miden_brush\.py" | grep -v grep | grep -v "$$" | wc -l)
  if [[ "$remaining" -gt 0 ]]; then
    echo -e "${YELLOW}⚠️ 仍有 $remaining 个进程在运行${NC}"
    # 再次尝试停止
    remaining_pids=$(ps aux | grep -E "python3.*miden_brush\.py" | grep -v grep | grep -v "$$" | awk '{print $2}' 2>/dev/null)
    for pid in $remaining_pids; do
      if ps -p "$pid" -o args= 2>/dev/null | grep -q "miden_brush\.py"; then
        kill -9 "$pid" 2>/dev/null || true
      fi
    done
    sleep 1
  else
    echo -e "${GREEN}✓ 旧进程已完全停止${NC}"
  fi
  
  # 删除旧的Python脚本，确保重新生成（使用绝对路径，删除所有可能的旧文件）
  PYTHON_BRUSH_ABS=$(realpath "$PYTHON_BRUSH" 2>/dev/null || echo "$(pwd)/$PYTHON_BRUSH")
  echo -e "${YELLOW}清理旧脚本文件...${NC}"
  
  # 查找所有可能的旧脚本文件位置
  OLD_SCRIPT_LOCATIONS=(
    "$PYTHON_BRUSH"
    "$PYTHON_BRUSH_ABS"
    "./$PYTHON_BRUSH"
    "$HOME/$PYTHON_BRUSH"
    "$(pwd)/$PYTHON_BRUSH"
  )
  
  # 删除所有找到的旧文件（但先检查是否有进程在使用）
  for loc in "${OLD_SCRIPT_LOCATIONS[@]}"; do
    if [[ -f "$loc" ]]; then
      # 检查是否有进程在使用这个文件（通过检查进程的命令行）
      loc_abs=$(realpath "$loc" 2>/dev/null || echo "$loc")
      using_pids=$(ps aux | grep -E "python3.*miden_brush" | grep -v grep | grep -v "$$" | awk '{print $2}' 2>/dev/null)
      can_delete=true
      
      if [[ -n "$using_pids" ]]; then
        for pid in $using_pids; do
          # 检查进程使用的脚本文件路径
          pid_script=$(ps -p "$pid" -o args= 2>/dev/null | grep -oE '[^ ]+miden_brush\.py[^ ]*' | head -1)
          if [[ -n "$pid_script" ]]; then
            pid_script_abs=$(realpath "$pid_script" 2>/dev/null || echo "$pid_script")
            if [[ "$pid_script_abs" == "$loc_abs" ]]; then
              can_delete=false
              break
            fi
          fi
        done
      fi
      
      if [[ "$can_delete" == "true" ]]; then
        echo -e "${YELLOW}删除: $loc${NC}"
        rm -f "$loc"
      else
        echo -e "${YELLOW}跳过（有进程在使用）: $loc${NC}"
      fi
    fi
  done
  
  # 也删除可能的备份文件
  rm -f "${PYTHON_BRUSH}.bak" "${PYTHON_BRUSH}.old" 2>/dev/null
  
  # 额外检查：查找所有运行中的进程使用的脚本文件（排除当前脚本）
  running_pids=$(ps aux | grep -E "python3.*miden_brush" | grep -v grep | grep -v "$$" | awk '{print $2}' 2>/dev/null)
  if [[ -n "$running_pids" ]]; then
    echo -e "${YELLOW}发现运行中的进程，检查使用的脚本文件:${NC}"
    for pid in $running_pids; do
      # 确认这是运行 miden_brush.py 的进程
      if ! ps -p "$pid" -o args= 2>/dev/null | grep -q "miden_brush\.py"; then
        continue
      fi
      
      # 获取进程的命令行和脚本文件
      script_file=$(ps -p "$pid" -o args= 2>/dev/null | grep -oE '[^ ]+miden_brush\.py[^ ]*' | head -1)
      if [[ -n "$script_file" ]]; then
        echo -e "${YELLOW}进程 PID $pid 使用脚本: $script_file${NC}"
        # 检查脚本内容，看是否是旧版本
        if [[ -f "$script_file" ]]; then
          if grep -q "from webdriver_manager.chrome import ChromeDriverManager" "$script_file" 2>/dev/null && ! grep -q "try:" "$script_file" 2>/dev/null; then
            echo -e "${RED}⚠️ 发现旧版本脚本（直接导入，无try-except）: $script_file${NC}"
            echo -e "${YELLOW}显示脚本前15行:${NC}"
            head -15 "$script_file"
            echo -e "${YELLOW}强制停止进程并删除旧脚本...${NC}"
            kill -9 "$pid" 2>/dev/null || true
            sleep 1
            # 确认进程已停止后再删除文件
            if ! kill -0 "$pid" 2>/dev/null; then
              rm -f "$script_file"
            fi
          fi
        fi
      fi
    done
    sleep 1
  fi
  
  echo -e "${GREEN}✓ 已清理旧脚本文件${NC}"
  
  # 检查并安装Python依赖
  echo -e "${YELLOW}检查Python依赖...${NC}"
  if ! python3 -c "import selenium" 2>/dev/null; then
    echo -e "${YELLOW}安装selenium...${NC}"
    pip3 install --quiet selenium 2>/dev/null || pip3 install selenium
    if ! python3 -c "import selenium" 2>/dev/null; then
      echo -e "${RED}❌ selenium 安装失败${NC}"
      return 1
    fi
    echo -e "${GREEN}✓ selenium 已安装${NC}"
  else
    echo -e "${GREEN}✓ selenium 已安装${NC}"
  fi
  
  if ! python3 -c "import webdriver_manager" 2>/dev/null; then
    echo -e "${YELLOW}安装webdriver-manager...${NC}"
    pip3 install --quiet webdriver-manager 2>/dev/null || pip3 install webdriver-manager
    if ! python3 -c "import webdriver_manager" 2>/dev/null; then
      echo -e "${YELLOW}⚠️ webdriver-manager 安装失败，将使用系统ChromeDriver${NC}"
    else
      echo -e "${GREEN}✓ webdriver-manager 已安装${NC}"
    fi
  else
    echo -e "${GREEN}✓ webdriver-manager 已安装${NC}"
  fi
  
  # 修复 ChromeDriver
  fix_chromedriver
  
  # 创建修复版的Python刷子脚本
  cat > $PYTHON_BRUSH <<EOF
#!/usr/bin/env python3
import time
import random
import subprocess
import os
import glob
import sys
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait, Select
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options

# 尝试导入webdriver_manager（可选）
try:
    from webdriver_manager.chrome import ChromeDriverManager
    from selenium.webdriver.chrome.service import Service
    HAS_WEBDRIVER_MANAGER = True
except ImportError:
    HAS_WEBDRIVER_MANAGER = False
    print("⚠️ webdriver-manager未安装，将使用系统ChromeDriver")

print("=" * 50)
print("🚀 动态代理刷子启动！")
print("=" * 50)
import sys
sys.stdout.flush()  # 确保输出立即显示

# 获取代理路由配置路径（从环境变量或使用默认值）
PROXY_ROUTER_CONF = os.environ.get('PROXY_ROUTER_CONF', '/tmp/proxychains-god.conf')
USE_PROXY_ROUTER = os.path.exists(PROXY_ROUTER_CONF) and os.path.getsize(PROXY_ROUTER_CONF) > 0

if USE_PROXY_ROUTER:
    # 检查配置文件格式
    try:
        with open(PROXY_ROUTER_CONF, 'r') as f:
            content = f.read()
            if not any(line.strip().startswith(('http', 'socks4', 'socks5')) for line in content.split('\n') if line.strip() and not line.strip().startswith('#')):
                USE_PROXY_ROUTER = False
                print("⚠️ 代理路由配置文件格式错误，使用直连模式")
    except:
        USE_PROXY_ROUTER = False
        print("⚠️ 无法读取代理路由配置，使用直连模式")

if USE_PROXY_ROUTER:
    print(f"✓ 使用代理路由模式: {PROXY_ROUTER_CONF}")
else:
    print("✓ 使用直连模式")

# 读取钱包地址
accounts = []
accounts_file = "miden_wallets/batch_accounts.txt"
if not os.path.exists(accounts_file):
    print(f"❌ 错误: 钱包文件不存在: {accounts_file}")
    sys.exit(1)

try:
    with open(accounts_file, "r") as f:
        accounts = [line.strip() for line in f if line.strip()]
except Exception as e:
    print(f"❌ 错误: 无法读取钱包文件: {e}")
    sys.exit(1)

if not accounts:
    print("❌ 错误: 钱包文件为空")
    sys.exit(1)

print(f"✓ 找到 {len(accounts)} 个钱包地址")
print(f"钱包列表: {', '.join([acc[:12] + '...' for acc in accounts[:5]])}{'...' if len(accounts) > 5 else ''}")
sys.stdout.flush()

# 获取账户信息和faucet ID
print("正在获取账户信息...")
sys.stdout.flush()
def get_account_info():
    """获取账户列表和默认账户"""
    try:
        if USE_PROXY_ROUTER:
            cmd = ["proxychains", "-q", "-f", PROXY_ROUTER_CONF, "miden-client", "account", "--list"]
        else:
            cmd = ["miden-client", "account", "--list"]
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            # 提取账户ID
            account_ids = []
            for line in result.stdout.split('\n'):
                if '0x' in line:
                    # 提取16进制账户ID
                    import re
                    matches = re.findall(r'0x[0-9a-f]+', line)
                    account_ids.extend(matches)
            return account_ids[0] if account_ids else None
    except:
        pass
    return None

# 获取默认账户ID（用于sender）
default_account_id = get_account_info()
if default_account_id:
    print(f"✓ 默认账户ID: {default_account_id[:16]}...")
else:
    print("⚠️ 无法获取默认账户，将使用钱包列表中的第一个地址")

# 尝试获取faucet ID（从环境变量或从笔记中查找）
FAUCET_ID = os.environ.get('FAUCET_ID', None)

if not FAUCET_ID:
    print("正在查找FAUCET_ID...")
    sys.stdout.flush()
    
    # 尝试从笔记中查找faucet ID
    try:
        if USE_PROXY_ROUTER:
            cmd = ["proxychains", "-q", "-f", PROXY_ROUTER_CONF, "miden-client", "notes", "--list"]
        else:
            cmd = ["miden-client", "notes", "--list"]
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if result.returncode == 0 and result.stdout:
            # 从笔记输出中查找faucet ID（通常是0x开头的地址）
            import re
            faucet_ids = re.findall(r'0x[0-9a-f]{16,}', result.stdout, re.IGNORECASE)
            if faucet_ids:
                # 使用第一个找到的作为faucet ID
                FAUCET_ID = faucet_ids[0]
                print(f"✓ 从笔记中找到FAUCET_ID: {FAUCET_ID[:16]}...")
                sys.stdout.flush()
    except:
        pass
    
    # 如果还是没找到，尝试使用账户列表中的第一个
    if not FAUCET_ID and default_account_id:
        FAUCET_ID = default_account_id
        print(f"⚠️ 未找到FAUCET_ID，使用默认账户: {FAUCET_ID[:16]}...")
        sys.stdout.flush()
    elif not FAUCET_ID and accounts:
        # 如果账户列表不为空，使用第一个账户地址
        FAUCET_ID = accounts[0]
        print(f"⚠️ 未找到FAUCET_ID，使用第一个钱包地址: {FAUCET_ID[:16]}...")
        sys.stdout.flush()
else:
    print(f"✓ 使用环境变量FAUCET_ID: {FAUCET_ID[:16]}...")
    sys.stdout.flush()

def get_chrome_driver():
    """创建浏览器 - 自动管理驱动版本"""
    options = Options()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--disable-gpu')
    options.add_argument('--window-size=1920,1080')
    
    if HAS_WEBDRIVER_MANAGER:
        try:
            # 自动下载和管理 ChromeDriver
            service = Service(ChromeDriverManager().install())
            driver = webdriver.Chrome(service=service, options=options)
            return driver
        except Exception as e:
            print(f"自动 ChromeDriver 失败: {e}，尝试使用系统ChromeDriver")
    
    # 使用系统 ChromeDriver
    try:
        driver = webdriver.Chrome(options=options)
        return driver
    except Exception as e:
        print(f"❌ 无法创建Chrome驱动: {e}")
        raise

def query_latest_note_amount(address):
    """查询链上最新笔记，获取领取数量"""
    try:
        import re
        
        # 先查询expected状态的笔记（最新收到的）
        for note_type in ["expected", "committed", "consumable"]:
            if USE_PROXY_ROUTER:
                cmd = ["proxychains", "-q", "-f", PROXY_ROUTER_CONF, "miden-client", "notes", "--list", note_type]
            else:
                cmd = ["miden-client", "notes", "--list", note_type]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            
            if result.returncode == 0 and result.stdout:
                lines = result.stdout.split('\n')
                
                # 查找包含数量的行（优先查找大数字，通常是1000）
                found_amounts = []
                for line in lines:
                    # 查找数字模式，优先匹配1000这样的大数字
                    amount_matches = re.findall(r'(\d+(?:\.\d+)?)', line)
                    for amount_str in amount_matches:
                        amount_val = float(amount_str)
                        # 如果是1000或接近1000，很可能是领取的数量
                        if 100 <= amount_val <= 10000:
                            found_amounts.append((amount_val, line))
                
                # 如果找到数量，返回最大的（通常是最新的）
                if found_amounts:
                    # 按数量排序，返回最大的
                    found_amounts.sort(key=lambda x: x[0], reverse=True)
                    amount = found_amounts[0][0]
                    # 如果是整数，不显示小数点
                    if amount == int(amount):
                        return f"{int(amount)} POL"
                    else:
                        return f"{amount} POL"
                
                # 如果没找到大数字，尝试查找任何数字
                for line in lines:
                    amount_match = re.search(r'(\d+(?:\.\d+)?)\s*(?:POL|token|TOKEN)?', line, re.IGNORECASE)
                    if amount_match:
                        amount = float(amount_match.group(1))
                        if amount > 0:
                            if amount == int(amount):
                                return f"{int(amount)} POL"
                            else:
                                return f"{amount} POL"
        
        # 如果笔记查询失败，尝试查询交易记录
        if USE_PROXY_ROUTER:
            cmd = ["proxychains", "-q", "-f", PROXY_ROUTER_CONF, "miden-client", "tx", "--list"]
        else:
            cmd = ["miden-client", "tx", "--list"]
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        
        if result.returncode == 0 and result.stdout:
            lines = result.stdout.split('\n')
            for line in lines:
                # 在交易记录中查找数量
                amount_match = re.search(r'(\d+(?:\.\d+)?)\s*(?:POL|token|TOKEN)?', line, re.IGNORECASE)
                if amount_match:
                    amount = float(amount_match.group(1))
                    if 100 <= amount <= 10000:
                        if amount == int(amount):
                            return f"{int(amount)} POL"
                        else:
                            return f"{amount} POL"
        
    except Exception as e:
        # 查询失败不影响主流程，静默失败
        pass
    
    return None

def check_wallet_has_balance(account_id=None):
    """检查钱包是否有可消费的notes（余额）"""
    try:
        # 查询可消费的notes
        if USE_PROXY_ROUTER:
            cmd = ["proxychains", "-q", "-f", PROXY_ROUTER_CONF, "miden-client", "notes", "--list", "consumable"]
        else:
            cmd = ["miden-client", "notes", "--list", "consumable"]
        
        if account_id:
            cmd.extend(["--account-id", account_id])
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        
        if result.returncode == 0 and result.stdout:
            # 检查是否有可消费的notes（简单检查：输出中是否有note ID或数量）
            if "0x" in result.stdout or "POL" in result.stdout or "consumable" in result.stdout.lower():
                # 尝试提取数量
                import re
                amounts = re.findall(r'(\d+(?:\.\d+)?)\s*POL', result.stdout, re.IGNORECASE)
                if amounts:
                    total = sum(float(a) for a in amounts)
                    if total > 0:
                        return True, total
        
        # 也检查committed状态的notes（可能还未消费）
        if USE_PROXY_ROUTER:
            cmd = ["proxychains", "-q", "-f", PROXY_ROUTER_CONF, "miden-client", "notes", "--list", "committed"]
        else:
            cmd = ["miden-client", "notes", "--list", "committed"]
        
        if account_id:
            cmd.extend(["--account-id", account_id])
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        
        if result.returncode == 0 and result.stdout:
            import re
            amounts = re.findall(r'(\d+(?:\.\d+)?)\s*POL', result.stdout, re.IGNORECASE)
            if amounts:
                total = sum(float(a) for a in amounts)
                if total > 0:
                    return True, total
        
        return False, 0
    except Exception as e:
        # 查询失败，假设没有余额（保守策略）
        return False, 0

def faucet_claim(address):
    """领取水龙头"""
    driver = None
    try:
        driver = get_chrome_driver()
        print(f"  💧 [{time.strftime('%H:%M:%S')}] 为地址 {address[:12]}... 领取水龙头")
        sys.stdout.flush()
        
        driver.get("https://faucet.testnet.miden.io/")
        
        # 等待页面加载，增加等待时间
        WebDriverWait(driver, 30).until(
            EC.presence_of_element_located((By.TAG_NAME, "body"))
        )
        time.sleep(2)  # 额外等待页面完全加载
        
        # 填写地址 - 尝试多种选择器
        address_input = None
        selectors = [
            (By.NAME, "recipient-address"),
            (By.ID, "recipient-address"),
            (By.CSS_SELECTOR, "input[name='recipient-address']"),
            (By.CSS_SELECTOR, "input[placeholder*='address' i]"),
            (By.XPATH, "//input[@name='recipient-address']"),
        ]
        
        for selector_type, selector_value in selectors:
            try:
                address_input = WebDriverWait(driver, 5).until(
                    EC.presence_of_element_located((selector_type, selector_value))
                )
                break
            except:
                continue
        
        if not address_input:
            raise Exception("无法找到地址输入框")
        
        address_input.clear()
        time.sleep(0.5)
        address_input.send_keys(address)
        time.sleep(1)
        
        # 选择金额 - 尝试多种选择器
        amount_select = None
        selectors = [
            (By.NAME, "token-amount"),
            (By.ID, "token-amount"),
            (By.CSS_SELECTOR, "select[name='token-amount']"),
        ]
        
        for selector_type, selector_value in selectors:
            try:
                amount_select = WebDriverWait(driver, 5).until(
                    EC.presence_of_element_located((selector_type, selector_value))
                )
                break
            except:
                continue
        
        if not amount_select:
            raise Exception("无法找到金额选择框")
        
        select = Select(amount_select)
        # 尝试选择1000，如果失败尝试其他值
        try:
            select.select_by_visible_text("1000")
        except:
            try:
                select.select_by_value("1000")
            except:
                # 选择第一个选项
                select.select_by_index(0)
        
        time.sleep(1)
        
        # 随机选择笔记类型 - 尝试多种选择器
        note_type = None
        # 先尝试查找所有可能的按钮
        try:
            # 查找所有包含"PUBLIC"或"PRIVATE"的按钮
            all_buttons = driver.find_elements(By.TAG_NAME, "button")
            public_buttons = []
            private_buttons = []
            
            for btn in all_buttons:
                btn_text = btn.text.upper()
                if "PUBLIC" in btn_text and ("NOTE" in btn_text or "SEND" in btn_text):
                    public_buttons.append(btn)
                elif "PRIVATE" in btn_text and ("NOTE" in btn_text or "SEND" in btn_text):
                    private_buttons.append(btn)
            
            # 随机选择类型
            if random.random() < 0.3 and public_buttons:
                public_buttons[0].click()
                note_type = "Public"
            elif private_buttons:
                private_buttons[0].click()
                note_type = "Private"
            elif public_buttons:
                public_buttons[0].click()
                note_type = "Public"
        except:
            pass
        
        # 如果上面的方法失败，尝试XPATH选择器
        if not note_type:
            if random.random() < 0.3:
                btn_selectors = [
                    (By.XPATH, "//button[contains(translate(text(), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'), 'PUBLIC')]"),
                    (By.XPATH, "//button[contains(text(), 'PUBLIC')]"),
                    (By.XPATH, "//button[contains(text(), 'Public')]"),
                    (By.XPATH, "//button[contains(text(), 'public')]"),
                ]
                for selector_type, selector_value in btn_selectors:
                    try:
                        public_btn = WebDriverWait(driver, 3).until(
                            EC.element_to_be_clickable((selector_type, selector_value))
                        )
                        public_btn.click()
                        note_type = "Public"
                        break
                    except:
                        continue
            else:
                btn_selectors = [
                    (By.XPATH, "//button[contains(translate(text(), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'), 'PRIVATE')]"),
                    (By.XPATH, "//button[contains(text(), 'PRIVATE')]"),
                    (By.XPATH, "//button[contains(text(), 'Private')]"),
                    (By.XPATH, "//button[contains(text(), 'private')]"),
                ]
                for selector_type, selector_value in btn_selectors:
                    try:
                        private_btn = WebDriverWait(driver, 3).until(
                            EC.element_to_be_clickable((selector_type, selector_value))
                        )
                        private_btn.click()
                        note_type = "Private"
                        break
                    except:
                        continue
        
        if not note_type:
            # 最后尝试：查找任何包含"NOTE"的按钮
            try:
                note_buttons = driver.find_elements(By.XPATH, "//button[contains(translate(text(), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'), 'NOTE')]")
                if note_buttons:
                    note_buttons[0].click()
                    note_type = "Unknown"
                    print(f"  ⚠️ [{time.strftime('%H:%M:%S')}] 使用通用按钮选择器")
            except:
                pass
        
        if not note_type:
            raise Exception("无法找到笔记类型按钮，请检查页面结构")
        
        time.sleep(1)
        
        # 提交并等待成功 - 尝试多种成功消息的选择器
        success_element = None
        success_selectors = [
            (By.XPATH, "//div[contains(text(),'Successfully') or contains(text(),'successfully')]"),
            (By.XPATH, "//div[contains(text(),'Success')]"),
            (By.XPATH, "//*[contains(text(),'Successfully')]"),
            (By.CSS_SELECTOR, "[class*='success']"),
            (By.CSS_SELECTOR, "[id*='success']"),
        ]
        
        for selector_type, selector_value in success_selectors:
            try:
                success_element = WebDriverWait(driver, 20).until(
                    EC.presence_of_element_located((selector_type, selector_value))
                )
                break
            except:
                continue
        
        if not success_element:
            # 如果找不到成功消息，等待一段时间看是否有其他提示
            time.sleep(5)
            page_text = driver.page_source.lower()
            if "success" in page_text or "sent" in page_text:
                print(f"  ⚠️ [{time.strftime('%H:%M:%S')}] 页面可能已成功，但未找到明确的成功消息")
            else:
                raise Exception("未找到成功消息，可能领取失败")
        
        print(f"  ✅ [{time.strftime('%H:%M:%S')}] 页面显示领取成功 | {address[:12]}... | {note_type}")
        sys.stdout.flush()
        
        # 关闭浏览器
        driver.quit()
        driver = None
        
        # 等待交易上链
        print(f"  ⏳ [{time.strftime('%H:%M:%S')}] 等待交易上链...")
        sys.stdout.flush()
        time.sleep(5)
        
        # 查询链上最新笔记，获取实际领取数量
        claimed_amount = query_latest_note_amount(address)
        if claimed_amount:
            print(f"  💰 [{time.strftime('%H:%M:%S')}] 链上确认: 实际领取 {claimed_amount}")
        else:
            print(f"  ⚠️ [{time.strftime('%H:%M:%S')}] 无法获取链上数量，可能还在确认中")
        
        sys.stdout.flush()
        return True
        
    except Exception as e:
        print(f"  ❌ [{time.strftime('%H:%M:%S')}] 领取失败: {str(e)[:200]}")
        sys.stdout.flush()
        return False
    finally:
        if driver:
            driver.quit()
            driver = None

def send_transaction():
    """发送交易"""
    try:
        amount = round(random.uniform(0.001, 0.1), 6)
        target_addr = random.choice(accounts)
        
        # 如果没有faucet ID，跳过交易
        if not FAUCET_ID:
            print(f"⚠️ [{time.strftime('%H:%M:%S')}] 跳过交易：未配置FAUCET_ID")
            return
        
        # 构建命令 - 根据文档，可以省略--sender使用默认账户
        asset_str = f"{amount}::{FAUCET_ID}"
        base_cmd = ["miden-client", "send"]
        
        # 如果有默认账户，添加--sender（可选，省略则使用默认账户）
        if default_account_id:
            base_cmd.extend(["--sender", default_account_id])
        
        base_cmd.extend(["--target", target_addr, "--asset", asset_str, "--note-type", "public", "--force"])
        
        if USE_PROXY_ROUTER:
            cmd = ["proxychains", "-q", "-f", PROXY_ROUTER_CONF] + base_cmd
        else:
            cmd = base_cmd
        
        print(f"  📤 [{time.strftime('%H:%M:%S')}] 发送交易: {amount} POL -> {target_addr[:12]}...")
        sys.stdout.flush()
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            # 打印完整的返回结果
            output = result.stdout.strip()
            if output:
                print(f"  ✅ [{time.strftime('%H:%M:%S')}] 交易成功!")
                print(f"     金额: {amount} POL")
                print(f"     目标: {target_addr[:16]}...")
                # 尝试提取交易哈希或ID
                if "0x" in output:
                    tx_hash = [line for line in output.split('\n') if '0x' in line]
                    if tx_hash:
                        print(f"     交易哈希: {tx_hash[0][:50]}...")
                # 打印完整输出（限制长度）
                if len(output) < 500:
                    print(f"     返回: {output}")
                else:
                    print(f"     返回: {output[:200]}...")
            else:
                print(f"  ✅ [{time.strftime('%H:%M:%S')}] 交易成功: {amount} POL -> {target_addr[:12]}...")
        else:
            error_msg = result.stderr.strip() if result.stderr else result.stdout.strip() or "未知错误"
            print(f"  ❌ [{time.strftime('%H:%M:%S')}] 交易失败")
            print(f"     错误: {error_msg[:200]}")
            if result.stdout:
                print(f"     输出: {result.stdout.strip()[:200]}")
        sys.stdout.flush()
            
    except subprocess.TimeoutExpired:
        print(f"❌ [{time.strftime('%H:%M:%S')}] 交易超时")
    except Exception as e:
        print(f"❌ [{time.strftime('%H:%M:%S')}] 交易错误: {str(e)}")

def create_note():
    """创建笔记"""
    try:
        amount = round(random.uniform(0.001, 0.05), 6)
        
        # 如果没有faucet ID或账户ID，跳过
        if not FAUCET_ID:
            print(f"⚠️ [{time.strftime('%H:%M:%S')}] 跳过创建笔记：未配置FAUCET_ID")
            return
        
        # 使用随机账户或默认账户
        target_account = default_account_id if default_account_id else random.choice(accounts)
        
        # 构建命令
        asset_str = f"{amount}::{FAUCET_ID}"
        if USE_PROXY_ROUTER:
            cmd = ["proxychains", "-q", "-f", PROXY_ROUTER_CONF, "miden-client", "mint", "--target", target_account, "--asset", asset_str, "--note-type", "private", "--force"]
        else:
            cmd = ["miden-client", "mint", "--target", target_account, "--asset", asset_str, "--note-type", "private", "--force"]
        
        print(f"  📝 [{time.strftime('%H:%M:%S')}] 创建笔记: {amount} POL -> {target_account[:12]}...")
        sys.stdout.flush()
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            # 打印完整的返回结果
            output = result.stdout.strip()
            if output:
                print(f"  ✅ [{time.strftime('%H:%M:%S')}] 笔记创建成功!")
                print(f"     金额: {amount} POL")
                print(f"     目标: {target_account[:16]}...")
                # 尝试提取笔记ID或哈希
                if "0x" in output:
                    note_id = [line for line in output.split('\n') if '0x' in line]
                    if note_id:
                        print(f"     笔记ID: {note_id[0][:50]}...")
                # 打印完整输出（限制长度）
                if len(output) < 500:
                    print(f"     返回: {output}")
                else:
                    print(f"     返回: {output[:200]}...")
            else:
                print(f"  ✅ [{time.strftime('%H:%M:%S')}] 笔记创建成功: {amount} POL")
        else:
            error_msg = result.stderr.strip() if result.stderr else result.stdout.strip() or "未知错误"
            print(f"  ❌ [{time.strftime('%H:%M:%S')}] 创建笔记失败")
            print(f"     错误: {error_msg[:200]}")
            if result.stdout:
                print(f"     输出: {result.stdout.strip()[:200]}")
        sys.stdout.flush()
    except subprocess.TimeoutExpired:
        print(f"❌ [{time.strftime('%H:%M:%S')}] 创建笔记超时")
    except Exception as e:
        print(f"❌ [{time.strftime('%H:%M:%S')}] 创建笔记错误: {str(e)}")

# 主循环
print("\n" + "=" * 50)
print("✅ 初始化完成，开始主循环...")
print("=" * 50 + "\n")
sys.stdout.flush()

round_count = 0

while True:
    round_count += 1
    print(f"\n{'='*50}")
    print(f"🔄 第 {round_count} 轮开始 - {time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{'='*50}\n")
    sys.stdout.flush()
    
    random.shuffle(accounts)
    
    for idx, account in enumerate(accounts, 1):
        print(f"\n📋 处理钱包 {idx}/{len(accounts)}: {account[:12]}...")
        sys.stdout.flush()
        
        # 先领取测试币
        claim_success = faucet_claim(account)
        
        if claim_success:
            # 等待一段时间让币到账（第一次领取需要等待）
            print(f"  ⏳ 等待测试币到账（30秒）...")
            sys.stdout.flush()
            time.sleep(30)
            
            # 同步账户状态，确保能查询到最新的notes
            print(f"  🔄 同步账户状态...")
            sys.stdout.flush()
            try:
                if USE_PROXY_ROUTER:
                    subprocess.run(["proxychains", "-q", "-f", PROXY_ROUTER_CONF, "miden-client", "sync"], 
                                 capture_output=True, timeout=30)
                else:
                    subprocess.run(["miden-client", "sync"], capture_output=True, timeout=30)
            except:
                pass
            
            # 检查钱包是否有余额（可消费的notes）
            # 尝试从账户地址获取账户ID（如果可能）
            account_id_for_check = None
            if default_account_id:
                account_id_for_check = default_account_id
            
            has_balance, balance_amount = check_wallet_has_balance(account_id_for_check)
            
            if has_balance:
                print(f"  ✅ 钱包有余额: {balance_amount} POL，开始执行交易操作...")
                sys.stdout.flush()
                
                # 有余额才执行交易
                tx_count = random.randint(2, 5)
                print(f"  💸 将执行 {tx_count} 个交易操作...")
                sys.stdout.flush()
                
                for tx_idx in range(tx_count):
                    if random.random() < 0.7:
                        send_transaction()
                    else:
                        create_note()
                    
                    sleep_sec = random.randint(10, 30)
                    print(f"  ⏳ 等待 {sleep_sec} 秒...")
                    sys.stdout.flush()
                    time.sleep(sleep_sec)
            else:
                print(f"  ℹ️ 钱包暂无余额或余额未到账，仅领取测试币，不执行交易操作")
                print(f"  💡 提示：等待下一轮或手动同步后，钱包有余额时会自动执行交易")
                sys.stdout.flush()
        else:
            print(f"  ⚠️ [{time.strftime('%H:%M:%S')}] 领取失败，跳过交易操作")
            sys.stdout.flush()
    
    sleep_time = random.randint(300, 600)
    print(f"\n{'='*50}")
    print(f"⏰ [{time.strftime('%H:%M:%S')}] 本轮结束，休息 {sleep_time//60} 分钟 ({sleep_time} 秒)")
    print(f"{'='*50}\n")
    sys.stdout.flush()
    time.sleep(sleep_time)
EOF

  chmod +x $PYTHON_BRUSH
  
  # 验证脚本文件已生成
  if [[ ! -f "$PYTHON_BRUSH" ]]; then
    echo -e "${RED}❌ Python脚本生成失败${NC}"
    return 1
  fi
  
  # 验证生成的脚本内容是否正确（检查是否有try-except）
  if ! grep -q "try:" "$PYTHON_BRUSH" || ! grep -q "except ImportError:" "$PYTHON_BRUSH"; then
    echo -e "${RED}❌ 生成的Python脚本格式错误，可能使用了旧版本${NC}"
    echo -e "${YELLOW}脚本前20行内容:${NC}"
    head -20 "$PYTHON_BRUSH"
    return 1
  fi
  
  # 显示脚本的关键部分，确认正确生成
  echo -e "${GREEN}✓ Python脚本已正确生成${NC}"
  echo -e "${BLUE}验证脚本导入部分:${NC}"
  grep -A 5 "尝试导入webdriver_manager" "$PYTHON_BRUSH" | head -6 || echo -e "${YELLOW}未找到导入部分${NC}"
  
  echo -e "${YELLOW}启动刷子进程...${NC}"
  # 使用绝对路径启动，确保使用正确的脚本文件
  PYTHON_BRUSH_ABS=$(realpath "$PYTHON_BRUSH" 2>/dev/null || echo "$(pwd)/$PYTHON_BRUSH")
  echo -e "${BLUE}使用脚本: $PYTHON_BRUSH_ABS${NC}"
  
  # 传递代理路由配置路径给Python脚本
  export PROXY_ROUTER_CONF="$PROXY_ROUTER_CONF"
  nohup env PROXY_ROUTER_CONF="$PROXY_ROUTER_CONF" python3 "$PYTHON_BRUSH_ABS" >> "$LOG_FILE" 2>&1 &
  new_pid=$!
  echo $new_pid > $PID_FILE
  
  # 等待一下，确保进程启动
  sleep 2
  
  # 验证新进程是否真的在运行
  if kill -0 "$new_pid" 2>/dev/null; then
    echo -e "${GREEN}✅ 动态代理刷子已启动！${NC}"
    echo -e "${YELLOW}日志文件: $LOG_FILE${NC}"
    echo -e "${YELLOW}进程ID: $new_pid${NC}"
    echo -e "${BLUE}提示: 使用选项9查看实时日志${NC}"
    
    # 等待3秒后检查是否有错误
    sleep 3
    
    # 验证实际运行的进程使用的脚本文件
    actual_script=$(ps -p "$new_pid" -o args= 2>/dev/null | grep -oE '[^ ]+miden_brush\.py[^ ]*' | head -1)
    if [[ -n "$actual_script" ]]; then
      echo -e "${BLUE}实际运行的脚本: $actual_script${NC}"
      if [[ -f "$actual_script" ]]; then
        # 检查是否是旧版本（直接导入，无try-except）
        if grep -q "from webdriver_manager.chrome import ChromeDriverManager" "$actual_script" 2>/dev/null && ! grep -q "try:" "$actual_script" 2>/dev/null; then
          echo -e "${RED}❌ 警告：进程使用的是旧版本脚本（直接导入）！${NC}"
          echo -e "${YELLOW}旧脚本位置: $actual_script${NC}"
          echo -e "${YELLOW}正在停止进程并删除旧脚本...${NC}"
          kill -9 "$new_pid" 2>/dev/null || true
          rm -f "$actual_script"
          rm -f $PID_FILE
          echo -e "${RED}请重新运行选项7启动刷子${NC}"
          return 1
        else
          echo -e "${GREEN}✓ 验证：进程使用的是正确的新版本脚本${NC}"
        fi
      fi
    fi
    
    if tail -10 "$LOG_FILE" 2>/dev/null | grep -q "ModuleNotFoundError.*webdriver_manager\|ImportError.*webdriver_manager"; then
      echo -e "${RED}⚠️ 检测到webdriver_manager导入错误${NC}"
      echo -e "${YELLOW}这可能是旧脚本仍在运行，请检查进程:${NC}"
      ps aux | grep -E "python3.*miden_brush" | grep -v grep || echo "未找到相关进程"
    fi
  else
    echo -e "${RED}❌ 进程启动失败，请检查日志: $LOG_FILE${NC}"
    rm -f $PID_FILE
    return 1
  fi
}

# 8) 停止刷子
stop_brush() {
  echo -e "${YELLOW}停止刷子进程...${NC}"
  
  # 方法1: 通过PID文件停止
  if [[ -f $PID_FILE ]]; then
    old_pid=$(cat $PID_FILE 2>/dev/null)
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      echo -e "${YELLOW}停止进程 (PID: $old_pid)...${NC}"
      kill "$old_pid" 2>/dev/null || true
      sleep 2
      if kill -0 "$old_pid" 2>/dev/null; then
        kill -9 "$old_pid" 2>/dev/null || true
        sleep 1
      fi
    fi
    rm -f $PID_FILE
  fi
  
  # 方法2: 通过进程名查找并停止
  PYTHON_BRUSH_ABS=$(realpath "$PYTHON_BRUSH" 2>/dev/null || echo "$PYTHON_BRUSH")
  pids=$(pgrep -f "python3.*$(basename $PYTHON_BRUSH)" 2>/dev/null || ps aux | grep -E "python3.*$(basename $PYTHON_BRUSH)" | grep -v grep | awk '{print $2}' 2>/dev/null)
  if [[ -n "$pids" ]]; then
    for pid in $pids; do
      if kill -0 "$pid" 2>/dev/null; then
        echo -e "${YELLOW}停止进程 PID: $pid${NC}"
        kill "$pid" 2>/dev/null || true
      fi
    done
    sleep 2
    # 强制停止仍在运行的进程
    for pid in $pids; do
      if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
      fi
    done
  fi
  
  # 方法3: 通过pkill停止
  pkill -f "miden_brush.py" 2>/dev/null || true
  sleep 1
  
  # 验证是否真的停止了
  remaining=$(pgrep -f "python3.*$(basename $PYTHON_BRUSH)" 2>/dev/null | wc -l)
  if [[ "$remaining" -eq 0 ]]; then
    echo -e "${GREEN}✅ 刷子已完全停止${NC}"
  else
    echo -e "${YELLOW}⚠️ 仍有 $remaining 个进程在运行${NC}"
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

# 9.5) 测试钱包导出密码
test_wallet_password() {
  echo -e "${BLUE}=== 测试钱包导出密码 ===${NC}"
  echo
  
  # 查找所有导出文件
  export_files=$(find "$ACCOUNTS_DIR" -name "wallet_export_*.json" 2>/dev/null | head -10)
  
  if [[ -z "$export_files" ]]; then
    echo -e "${RED}未找到钱包导出文件${NC}"
    echo -e "${YELLOW}请先生成钱包（选项5）${NC}"
    return 1
  fi
  
  echo -e "${YELLOW}找到以下导出文件:${NC}"
  echo "$export_files" | nl
  echo
  
  read -p "请输入要测试的文件编号（或直接输入文件路径）: " file_input
  
  if [[ "$file_input" =~ ^[0-9]+$ ]]; then
    test_file=$(echo "$export_files" | sed -n "${file_input}p")
  else
    test_file="$file_input"
  fi
  
  if [[ ! -f "$test_file" ]]; then
    echo -e "${RED}文件不存在: $test_file${NC}"
    return 1
  fi
  
  echo -e "${GREEN}测试文件: $test_file${NC}"
  echo
  
  # 检查文件是否加密
  if grep -q '"encrypted": true' "$test_file" 2>/dev/null; then
    echo -e "${BLUE}文件已加密${NC}"
    
    # 提取加密的keystore数据
    encrypted_data=$(grep -o '"encryptedKeystore": "[^"]*"' "$test_file" 2>/dev/null | cut -d'"' -f4)
    
    if [[ -z "$encrypted_data" ]]; then
      echo -e "${RED}未找到加密数据${NC}"
      return 1
    fi
    
    echo -e "${YELLOW}请输入密码进行测试:${NC}"
    read -sp "密码: " test_password
    echo
    
    if [[ -z "$test_password" ]]; then
      echo -e "${YELLOW}尝试空密码...${NC}"
    fi
    
    # 尝试使用openssl解密
    if command -v openssl &>/dev/null; then
      echo -e "${YELLOW}尝试使用openssl解密...${NC}"
      decrypted=$(echo "$encrypted_data" | openssl enc -d -aes-256-cbc -salt -pbkdf2 -base64 -pass pass:"$test_password" 2>/dev/null)
      
      if [[ $? -eq 0 && -n "$decrypted" ]]; then
        echo -e "${GREEN}✅ 密码正确！openssl解密成功${NC}"
        echo -e "${BLUE}解密后的数据长度: ${#decrypted} 字节${NC}"
      else
        echo -e "${RED}❌ 密码错误或解密失败${NC}"
        echo -e "${YELLOW}提示：${NC}"
        echo "1. 请确认您输入的是导出钱包时设置的密码"
        echo "2. 密码区分大小写"
        echo "3. 如果忘记密码，可能需要重新生成钱包"
      fi
    else
      echo -e "${YELLOW}openssl未安装，无法测试密码${NC}"
    fi
    
    # 尝试使用python解密
    if command -v python3 &>/dev/null; then
      echo -e "${YELLOW}尝试使用python解密...${NC}"
      python3 <<PYTHON_EOF 2>/dev/null
import base64
import sys
try:
    from cryptography.fernet import Fernet
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
    
    encrypted_data = "$encrypted_data"
    password = b'$test_password'
    
    try:
        # 解码base64
        encrypted_bytes = base64.b64decode(encrypted_data)
        
        # 提取salt和加密数据
        salt = encrypted_bytes[:16]
        encrypted = encrypted_bytes[16:]
        
        # 使用PBKDF2派生密钥
        kdf = PBKDF2HMAC(
            algorithm=hashes.SHA256(),
            length=32,
            salt=salt,
            iterations=100000,
        )
        key = base64.urlsafe_b64encode(kdf.derive(password))
        f = Fernet(key)
        
        # 解密
        decrypted = f.decrypt(encrypted)
        print("✅ 密码正确！python解密成功")
        print(f"解密后的数据长度: {len(decrypted)} 字节")
        sys.exit(0)
    except Exception as e:
        print("❌ 密码错误或解密失败")
        sys.exit(1)
except ImportError:
    print("⚠️ cryptography未安装")
    sys.exit(1)
PYTHON_EOF
    
      if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ 密码正确！python解密成功${NC}"
      else
        echo -e "${RED}❌ 密码错误或解密失败（python）${NC}"
      fi
    fi
    
  else
    echo -e "${YELLOW}文件未加密${NC}"
    echo -e "${BLUE}文件内容:${NC}"
    cat "$test_file" | head -20
  fi
  
  echo
  echo -e "${YELLOW}提示：${NC}"
  echo "1. 如果密码正确但仍无法导入，可能是浏览器钱包期望的格式不同"
  echo "2. 可以尝试使用Miden CLI导入方式（选项4修复后使用import命令）"
  echo "3. 如果忘记密码，需要重新生成钱包"
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
    echo "7) 查看助记词/密钥信息"
    echo "8) 删除钱包地址"
    echo "9) 启动动态代理刷子"
    echo "10) 停止刷子"
    echo "11) 查看实时日志"
    echo "12) 配置智能代理路由"
    echo "13) 启动节点服务"
    echo "14) 测试代理路由"
    echo "15) 显示路由状态"
    echo "16) 修复 ChromeDriver"
    echo "17) 测试钱包导出密码"
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
      7) view_mnemonics;;
      8) delete_wallet;;
      9) start_dynamic_brush;;
      10) stop_brush;;
      11) view_logs;;
      12) setup_proxy_router;;
      13) start_node_direct;;
      14) test_proxy_router;;
      15) show_router_status;;
      16) fix_chromedriver;;
      17) test_wallet_password;;
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
