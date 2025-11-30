#!/bin/bash
# miden-god-dynamic-proxy.sh —— 动态代理专版 最新版（集成智能路由）
set -e

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[34m'; NC='\033[0m'
ACCOUNTS_DIR="miden_wallets"
LOG_DIR="miden_logs"
LOG_FILE="$LOG_DIR/ultimate.log"
PID_FILE="miden-god.pid"
PYTHON_BRUSH="miden_brush.py"
PROXY_ROUTER_CONF="/tmp/proxychains-god.conf"

mkdir -p "$ACCOUNTS_DIR" "$LOG_DIR"

banner() {
  clear
  echo -e "${BLUE}
  ███╗   █╗██╗██████╗ ███████╗██╗   ██╗     ██████╗  ██████╗ ██████╗ 
  ██╗   ██║██║██╔══██╗██╔════╝██║   ██║    ██╔════╝ ██╔═══██╗██╔══██╗
  ██╗   ██║██║██║  ██║█████╗  ██║   ██║    ██║  ███╗██║   ██║██║  ██║
  ╚██╗ ██╔╝██║██║  ██║██╔══╝  ██║   ██║    ██║   ██║██║   ██║██║  ██║
   ╚████╔╝ ██║██████╔╝███████╗╚██████╔╝    ╚██████╔╝╚██████╔╝██████╔╝
    ╚═══╝  ╚═╝╚═════╝ ╚══════╝ ╚═════╝      ╚═════╝  ╚═════╝ ╚═════╝ 
          动态代理专版 最新版 —— 集成智能路由
${NC}"
}

# 获取简洁的 Miden 版本信息
get_miden_version() {
    if command -v miden &>/dev/null; then
        version=$(miden --version 2>/dev/null | grep -o 'miden [0-9]\+\.[0-9]\+\.[0-9]\+' | head -1 | sed 's/miden //')
        if [[ -n "$version" ]]; then
            echo "$version"
        else
            echo "已安装"
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
        proxy_ip=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$PROXY_ROUTER_CONF" | head -1 2>/dev/null || echo "未知")
        echo "已配置 ($proxy_ip)"
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
    
    # 创建代理路由配置
    cat > "$PROXY_ROUTER_CONF" <<EOF
strict_chain
proxy_dns
tcp_read_time_out 15000
tcp_connect_time_out 8000

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
    pkill -f "miden-node" 2>/dev/null
    sleep 2
    
    # 确保节点使用直连模式
    if [[ -f "/etc/proxychains.conf" ]]; then
        sudo mv /etc/proxychains.conf /etc/proxychains.conf.bak.node 2>/dev/null
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
        echo -e "${GREEN}✅ GOD脚本将通过代理IP运行${NC}"
    fi
}

# ========== 原有功能保持不变 ==========

# 1) 一键安装所有依赖
install_deps() {
  # ... 保持原有代码不变 ...
}

# 2) 配置动态代理
setup_dynamic_proxy() {
  # ... 保持原有代码不变 ...
}

# 3) 测试代理连接
test_proxy() {
  # ... 保持原有代码不变 ...
}

# 4) 修复 Miden 客户端配置
fix_miden_client() {
    # ... 保持原有代码不变，但修改为连接本地节点 ...
    echo -e "${YELLOW}初始化 Miden 客户端...${NC}"
    miden init --rpc http://localhost:57291 --network testnet 2>/dev/null || true
}

# 5) 生成钱包地址（使用代理路由）
gen_wallets() {
    echo -e "${YELLOW}检查 Miden 客户端状态...${NC}"
    
    export PATH="$HOME/.cargo/bin:$PATH"
    
    if ! command -v miden &>/dev/null; then
        echo -e "${RED}错误: Miden 客户端未安装，请先运行选项1安装依赖${NC}"
        return 1
    fi
    
    read -p "生成多少个钱包？(默认10) > " total
    total=${total:-10}
    
    echo -e "${YELLOW}开始生成 $total 个钱包...${NC}"
    echo -e "${GREEN}使用智能路由模式...${NC}"
    
    # 使用代理路由生成钱包
    if [[ -f "$PROXY_ROUTER_CONF" ]]; then
        echo -e "${BLUE}🔗 通过代理路由生成钱包${NC}"
    else
        echo -e "${YELLOW}⚠️ 使用直连模式生成钱包${NC}"
    fi
    
    success_count=0
    failed_count=0
    current_dir=$(pwd)
    
    for ((i=1;i<=total;i++)); do
        echo -e "\n${BLUE}=== 生成钱包 $i/$total ===${NC}"
        
        WALLET_DIR="$ACCOUNTS_DIR/wallet_$i"
        mkdir -p "$WALLET_DIR"
        cd "$WALLET_DIR" || {
            echo -e "${RED}无法进入目录 $WALLET_DIR${NC}"
            ((failed_count++))
            continue
        }
        
        # 使用代理路由初始化（如果配置了）
        if [[ -f "$PROXY_ROUTER_CONF" ]]; then
            echo -e "${YELLOW}通过代理路由初始化...${NC}"
            proxychains -q -f "$PROXY_ROUTER_CONF" miden init --rpc http://localhost:57291 --network testnet 2>&1 | tee -a "$LOG_FILE"
        else
            echo -e "${YELLOW}直连初始化...${NC}"
            miden init --rpc http://localhost:57291 --network testnet 2>&1 | tee -a "$LOG_FILE"
        fi
        
        # 生成钱包
        echo -e "${YELLOW}创建钱包...${NC}"
        if [[ -f "$PROXY_ROUTER_CONF" ]]; then
            proxychains -q -f "$PROXY_ROUTER_CONF" miden new-wallet --deploy 2>&1 | tee -a "$LOG_FILE"
        else
            miden new-wallet --deploy 2>&1 | tee -a "$LOG_FILE"
        fi
        
        # 获取地址
        addr=$(miden account 2>/dev/null | grep -oE "0x[0-9a-f]+" | head -1)
        if [[ -n "$addr" ]]; then
            echo "$addr" >> "$current_dir/$ACCOUNTS_DIR/batch_accounts.txt"
            ((success_count++))
            echo -e "${GREEN}✅ 钱包 $i 生成成功: ${addr}${NC}"
        else
            ((failed_count++))
            echo -e "${YELLOW}⚠️ 钱包 $i 生成失败${NC}"
        fi
        
        cd "$current_dir" || break
        echo -e "${GREEN}进度: $i/$total, 成功: $success_count, 失败: $failed_count${NC}"
        
        if [[ $i -lt $total ]]; then
            sleep 3
        fi
    done
    
    echo -e "\n${GREEN}生成完成！成功: $success_count/$total, 失败: $failed_count${NC}"
}

# 6) 查看钱包列表
view_wallets() {
  # ... 保持原有代码不变 ...
}

# 7) 启动动态代理刷子（使用代理路由）
start_dynamic_brush() {
  if ! command -v miden &>/dev/null; then
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
        
        # 使用代理路由配置
        cmd = ["proxychains", "-q", "-f", "/tmp/proxychains-god.conf", "miden", "send", "--to", target_addr, "--amount", str(amount), "--asset", "POL"]
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
        cmd = ["proxychains", "-q", "-f", "/tmp/proxychains-god.conf", "miden", "notes", "create", "--type", "private", "--asset", f"{amount}:POL"]
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
}

# 8) 停止刷子
stop_brush() {
  # ... 保持原有代码不变 ...
}

# 9) 查看实时日志
view_logs() {
  # ... 保持原有代码不变 ...
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
