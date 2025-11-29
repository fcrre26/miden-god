#!/bin/bash
# miden-god-dynamic-proxy.sh —— 动态代理专版 v0.12.2
set -e

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[34m'; NC='\033[0m'
ACCOUNTS_DIR="miden_wallets"
LOG_DIR="miden_logs"
LOG_FILE="$LOG_DIR/ultimate.log"
PID_FILE="miden-god.pid"
PYTHON_BRUSH="miden_brush.py"

mkdir -p "$ACCOUNTS_DIR" "$LOG_DIR"

banner() {
  clear
  echo -e "${BLUE}
  ███╗   █╗██╗██████╗ ███████╗██╗   ██╗     ██████╗  ██████╗ ██████╗ 
  ██║   ██║██║██╔══██╗██╔════╝██║   ██║    ██╔════╝ ██╔═══██╗██╔══██╗
  ██║   ██║██║██║  ██║█████╗  ██║   ██║    ██║  ███╗██║   ██║██║  ██║
  ╚██╗ ██╔╝██║██║  ██║██╔══╝  ██║   ██║    ██║   ██║██║   ██║██║  ██║
   ╚████╔╝ ██║██████╔╝███████╗╚██████╔╝    ╚██████╔╝╚██████╔╝██████╔╝
    ╚═══╝  ╚═╝╚═════╝ ╚══════╝ ╚═════╝      ╚═════╝  ╚═════╝ ╚═════╝ 
                  动态代理专版 v0.12.2 —— 智能IP轮换
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
            echo "$ip:$port"
        else
            IFS=':' read -r ip port user pass <<< "$proxy_line"
            echo "$ip:$port"
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

# 1) 一键安装所有依赖 - 修改版：使用 v0.12.2
install_deps() {
  echo -e "${YELLOW}正在安装所有依赖...${NC}"
  
  # 安装系统构建工具
  if command -v apt &>/dev/null; then
    sudo apt update -qq
    sudo apt install -y build-essential pkg-config libssl-dev curl wget python3-pip unzip proxychains4 libsqlite3-dev
  elif command -v yum &>/dev/null; then
    sudo yum groupinstall -y "Development Tools"
    sudo yum install -y pkgconfig openssl-devel curl wget python3-pip unzip proxychains-ng sqlite-devel
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
  
  # 安装 Miden v0.12.2 - 使用指定版本
# 安装 Miden v0.12.2 - 修复版
if ! command -v miden &>/dev/null; then
  echo -e "${YELLOW}安装 Miden 客户端 v0.12.2...${NC}"
  
  # 创建临时目录
  TEMP_DIR=$(mktemp -d)
  cd "$TEMP_DIR"
  
  # 下载并解压 v0.12.2 版本
  wget -O miden-v0.12.2.tar.gz "https://github.com/0xMiden/miden-client/archive/refs/tags/v0.12.2.tar.gz"
  tar -xzf miden-v0.12.2.tar.gz
  cd miden-client-0.12.2
  
  # 构建项目而不是直接安装
  echo -e "${YELLOW}构建 Miden 工作区...${NC}"
  cargo build --release --features testing --locked
  
  # 查找并安装可执行文件
  echo -e "${YELLOW}安装可执行文件...${NC}"
  if [ -f "target/release/miden" ]; then
      sudo cp target/release/miden /usr/local/bin/
      echo -e "${GREEN}✅ Miden 客户端安装成功${NC}"
  elif [ -f "target/release/miden-client" ]; then
      sudo cp target/release/miden-client /usr/local/bin/miden
      echo -e "${GREEN}✅ Miden 客户端安装成功${NC}"
  else
      # 尝试安装第一个找到的可执行文件
      first_bin=$(find target/release/ -maxdepth 1 -type f -executable | head -1)
      if [ -n "$first_bin" ]; then
          sudo cp "$first_bin" /usr/local/bin/miden
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
  
  # 验证安装
  if command -v miden &>/dev/null; then
      echo -e "${GREEN}✅ 验证: miden 命令可用${NC}"
  else
      echo -e "${RED}❌ 验证失败: miden 命令不可用${NC}"
      exit 1
  fi
  
else
  echo -e "${GREEN}Miden 客户端已安装${NC}"
fi
  
  # 安装 Python 依赖
  echo -e "${YELLOW}安装 Python 依赖...${NC}"
  pip3 install --quiet selenium
  
  # 初始化客户端
  echo -e "${YELLOW}初始化 Miden 客户端...${NC}"
  miden init --network testnet 2>/dev/null || true
  
  echo -e "${GREEN}所有依赖安装完成！${NC}"
  echo -e "${YELLOW}请运行: source ~/.bashrc${NC}"
}

# 2) 配置动态代理（直接录入完整字符串）
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
tcp_read_time_out 15000
tcp_connect_time_out 8000

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
    
    # 重新初始化客户端
    echo -e "${YELLOW}初始化 Miden 客户端...${NC}"
    miden init --network testnet 2>/dev/null || true
    
    # 验证安装
    if command -v miden &>/dev/null; then
        echo -e "${GREEN}✅ Miden 客户端已正确配置${NC}"
        version=$(get_miden_version)
        echo -e "${BLUE}客户端版本: $version${NC}"
    else
        echo -e "${RED}❌ Miden 客户端配置失败${NC}"
        echo -e "${YELLOW}尝试重新安装...${NC}"
        install_deps
    fi
}

# 5) 生成钱包地址（使用自有IP）
gen_wallets() {
    echo -e "${YELLOW}检查 Miden 客户端状态...${NC}"
    
    # 确保环境变量正确
    export PATH="$HOME/.cargo/bin:$PATH"
    
    if ! command -v miden &>/dev/null; then
        echo -e "${RED}错误: Miden 客户端未安装，请先运行选项1安装依赖${NC}"
        return 1
    fi
    
    read -p "生成多少个钱包？(默认10) > " total
    total=${total:-10}
    
    echo -e "${YELLOW}开始生成 $total 个钱包...${NC}"
    echo -e "${YELLOW}这可能需要几分钟时间...${NC}"
    echo -e "${GREEN}注意：生成钱包使用自有IP，不走代理${NC}"
    
    # 确保在正确的目录
    cd "$(pwd)"
    
    # 临时禁用代理（使用自有IP）
    if [[ -f "/etc/proxychains.conf" ]]; then
        sudo mv /etc/proxychains.conf /etc/proxychains.conf.bak
        echo -e "${YELLOW}已临时禁用代理，使用自有IP生成钱包${NC}"
    fi
    
    success_count=0
    for ((i=1;i<=total;i++)); do
        printf "\r${GREEN}进度 %d%% (%d/%d) 成功: %d${NC}" $((i*100/total)) $i $total $success_count
        
        WALLET_DIR="$ACCOUNTS_DIR/wallet_$i"
        mkdir -p "$WALLET_DIR"
        cd "$WALLET_DIR"
        
        # 创建新钱包（不使用代理）
        if miden new-wallet --deploy --testing 2>/dev/null; then
            # 获取账户地址
            addr=$(miden account 2>/dev/null | grep -oE "0x[0-9a-f]+" | head -1)
            if [[ -n "$addr" ]]; then
                echo "$addr" >> "../batch_accounts.txt"
                ((success_count++))
                printf "\r${GREEN}进度 %d%% (%d/%d) 成功: %d - 地址: ${addr:0:12}...${NC}" $((i*100/total)) $i $total $success_count
            fi
        fi
        
        cd - >/dev/null
    done
    
    # 恢复代理配置
    if [[ -f "/etc/proxychains.conf.bak" ]]; then
        sudo mv /etc/proxychains.conf.bak /etc/proxychains.conf
        echo -e "${GREEN}已恢复代理配置${NC}"
    fi
    
    echo -e "\n${GREEN}生成完成！成功: $success_count/$total${NC}"
    
    if [[ $success_count -eq 0 ]]; then
        echo -e "${RED}所有钱包生成都失败了！${NC}"
        echo -e "${YELLOW}可能的原因：${NC}"
        echo "1. Miden 客户端未正确安装"
        echo "2. 网络连接问题" 
        echo "3. 测试网服务暂时不可用"
        echo -e "${YELLOW}建议先运行选项1或4修复依赖${NC}"
    else
        echo -e "${GREEN}✅ 钱包生成完成，现在可以启动刷子了${NC}"
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

# 7) 启动动态代理刷子
start_dynamic_brush() {
  if ! command -v miden &>/dev/null; then
    echo -e "${RED}错误: Miden 客户端未安装${NC}"
    return 1
  fi
  
  if [[ ! -f "dynamic_proxy.conf" ]]; then
    echo -e "${RED}请先配置动态代理${NC}"
    return 1
  fi
  
  if [[ ! -f "$ACCOUNTS_DIR/batch_accounts.txt" ]]; then
    echo -e "${RED}请先生成钱包地址${NC}"
    return 1
  fi
  
  echo -e "${YELLOW}启动动态代理刷子...${NC}"
  
  # 创建Python刷子脚本
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
        # 随机选择一个目标地址
        target_addr = random.choice(accounts)
        
        # 使用proxychains执行命令（通过系统代理）
        cmd = ["proxychains", "-q", "miden", "client", "tx", "send", "--to", target_addr, "--amount", str(amount), "--asset", "POL"]
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
        cmd = ["proxychains", "-q", "miden", "client", "note", "create", "--type", "private", "--asset", f"{amount}:POL"]
        subprocess.run(cmd, capture_output=True, timeout=30)
        print(f"📝 [{time.strftime('%H:%M:%S')}] 创建笔记: {amount} POL")
    except:
        print(f"❌ [{time.strftime('%H:%M:%S')}] 创建笔记失败")

# 主循环
round_count = 0

while True:
    round_count += 1
    printf(f"=== 第 {round_count} 轮开始 ===")
    
    # 随机打乱账户顺序
    random.shuffle(accounts)
    
    # 为每个账户执行操作
    for account in accounts:
        # 领取水龙头
        faucet_claim(account)
        
        # 执行一些交易
        for _ in range(random.randint(2, 5)):
            if random.random() < 0.7:
                send_transaction()
            else:
                create_note()
            
            # 随机延迟
            time.sleep(random.randint(10, 30))
    
    # 每轮结束后休息
    sleep_time = random.randint(300, 600)  # 5-10分钟
    print(f"⏰ [{time.strftime('%H:%M:%S')}] 本轮结束，休息 {sleep_time//60} 分钟")
    time.sleep(sleep_time)
EOF

  chmod +x $PYTHON_BRUSH
  
  # 启动刷子
  echo -e "${YELLOW}启动刷子进程...${NC}"
  nohup ./$PYTHON_BRUSH >> "$LOG_FILE" 2>&1 &
  echo $! > $PID_FILE
  
  echo -e "${GREEN}动态代理刷子已启动！${NC}"
  echo -e "${YELLOW}日志文件: $LOG_FILE${NC}"
  echo -e "${YELLOW}实时日志: tail -f $LOG_FILE${NC}"
}

# 8) 停止刷子
stop_brush() {
  if [[ -f $PID_FILE ]]; then
    kill $(cat $PID_FILE) 2>/dev/null
    rm $PID_FILE
    echo -e "${GREEN}刷子已停止${NC}"
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
    echo -e "${BLUE}=== Miden 动态代理刷子 ===${NC}"
    echo "1) 一键安装所有依赖"
    echo "2) 配置动态代理"
    echo "3) 测试代理连接"
    echo "4) 修复 Miden 客户端"
    echo "5) 生成钱包地址"
    echo "6) 查看钱包列表"
    echo "7) 启动动态代理刷子"
    echo "8) 停止刷子"
    echo "9) 查看实时日志"
    echo "0) 退出"
    echo "============================"
    
    # 显示状态信息（简洁版）
    miden_version=$(get_miden_version)
    proxy_info=$(get_proxy_info)
    wallet_count=$(get_wallet_count)
    
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
