#!/bin/bash
# miden-god.sh —— 2025.11.30 宇宙最强完整版（一行代码都不省）
set -e

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[34m'; NC='\033[0m'
ACCOUNTS_DIR="miden_wallets"
LOG_DIR="miden_logs"
BATCH_SIZE=1000
LOG_FILE="$LOG_DIR/ultimate.log"
PID_FILE="miden-god.pid"
NODE_PID="miden-node.pid"
PYTHON_BRUSH="miden_ultimate.py"

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
                  宇宙最强完整版 v2025.11.30 —— 前0.1%
${NC}"
}

# 1) 一键安装所有依赖
install_deps() {
  echo -e "${YELLOW}正在安装所有依赖...${NC}"
  if ! command -v miden &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    git clone https://github.com/0xPolygonMiden/miden-client.git /tmp/mc
    cd /tmp/mc
    cargo install --path . --features testing,concurrent --locked
    cd ~
    rm -rf /tmp/mc
  fi
  sudo apt update -qq 2>/dev/null || true
  sudo apt install -y proxychains-ng python3-pip unzip wget >/dev/null 2>&1 || brew install proxychains-ng python git 2>/dev/null || true
  pip3 install --quiet selenium >/dev/null 2>&1
  wget -q https://edgedl.me.gvt1.com/edgedl/chrome/chrome-for-testing/131.0.6778.85/linux64/chromedriver-linux64.zip
  unzip -q chromedriver-linux64.zip
  sudo mv chromedriver-linux64/chromedriver /usr/local/bin/ 2>/dev/null || true
  sudo chmod +x /usr/local/bin/chromedriver 2>/dev/null || true
  miden init --rpc https://testnet-rpc.miden.xyz &>/dev/null || true
  echo -e "${GREEN}依赖安装完成！${NC}"
}

# 2) 无限生成钱包
gen_unlimited() {
  read -p "生成多少个钱包？（回车默认10000） > " total
  total=${total:-10000}
  echo -e "${YELLOW}开始生成 $total 个钱包...${NC}"
  read -p "回车开始" xxx
  start=$(date +%s)
  batch=1
  file="$ACCOUNTS_DIR/batch_$(printf "%04d" $batch).txt"
  > "$file"
  for ((i=1;i<=total;i++)); do
    printf "\r${GREEN}进度 %d%% (%d/%d)${NC}" $((i*100/total)) $i $total
    addr=$(miden account new --seed "god2025-$i-$(date +%s%N)" --testing 2>/dev/null | grep "Account ID" | awk '{print $4}')
    echo "$addr" >> "$file"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | batch_$batch | $addr" >> "$LOG_DIR/generate.log"
    (( i % BATCH_SIZE == 0 )) && batch=$((batch+1)) && file="$ACCOUNTS_DIR/batch_$(printf "%04d" $batch).txt" && > "$file"
  done
  echo -e "\n${GREEN}生成完成！耗时 $(( $(date +%s)-start )) 秒${NC}"
  read -p "按回车继续"
}

# 3) 启动满分刷子（互转+私有笔记+合约全拉满）
start_brush() {
  echo -e "${YELLOW}启动宇宙最强刷子...${NC}"
  cat > $PYTHON_BRUSH <<'EOF'
#!/usr/bin/env python3
import time,random,subprocess,glob
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

files = glob.glob("miden_wallets/batch_*.txt")
accounts = [l.strip() for f in files for l in open(f) if l.strip()]

def faucet(a):
    try:
        o=Options(); o.add_argument('--headless'); o.add_argument('--no-sandbox')
        d=webdriver.Chrome(options=o)
        d.get("https://faucet.testnet.miden.io/")
        WebDriverWait(d,12).until(EC.presence_of_element_located((By.NAME,"recipient-address"))).send_keys(a)
        if random.random()<0.22:
            try: d.find_element(By.ID,"public-note-radio").click()
            except: pass
        d.find_element(By.CSS_SELECTOR,"button[type=submit],.btn-request").click()
        time.sleep(7); d.quit()
    except: pass

def tx(a):
    r=random.randint(1,100); amt=round(random.uniform(0.000123,88.8888),6)
    cmd=["proxychains","-q","miden"]
    if r<=33: cmd+=["tx","send","--to",a,"--amount",str(amt),"--asset","POL","--rpc","https://testnet-rpc.miden.xyz"]
    elif r<=58:
        o=random.choice(accounts)
        while o==a: o=random.choice(accounts)
        cmd+=["tx","send","--to",o,"--amount",str(amt),"--asset","POL","--rpc","https://testnet-rpc.miden.xyz"]
    elif r<=78: cmd+=["note","create","--type","private","--asset",f"{amt}:POL","--tag",hex(random.getrandbits(32))]
    elif r<=93: cmd+=["note","consume","--type","private","--asset",f"{amt}:POL"]
    else:
        if random.random()<0.07:
            subprocess.run(["proxychains","-q","miden","contract","deploy","/tmp/hello.masm"], stdout=subprocess.DEVNULL)
        else:
            cmd+=["contract","call","--address","0x0000000000000000000000000000000000000000","--function","mint","--args","1"]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(random.randint(7,40))

print(f"启动！共{len(accounts)}个钱包")
while True:
    random.shuffle(accounts)
    for a in accounts:
        faucet(a)
        for _ in range(random.randint(9,17)): tx(a)
    print(f"[{time.strftime('%H:%M')}] 本轮结束，睡6-16分钟")
    time.sleep(random.randint(360,960))
EOF
  chmod +x $PYTHON_BRUSH
  nohup ./$PYTHON_BRUSH >> "$LOG_FILE" 2>&1 &
  echo $! > $PID_FILE
  echo -e "${GREEN}刷子已启动！日志 tail -f $LOG_FILE${NC}"
}

# 4-9 全功能（完整不省略）
stop_brush() {
  [[ -f $PID_FILE ]] && kill $(cat $PID_FILE) && rm $PID_FILE && echo -e "${GREEN}刷子已停止${NC}" || echo "没在跑"
  [[ -f $NODE_PID ]] && kill $(cat $NODE_PID) && rm $NODE_PID && echo -e "${GREEN}节点已停止${NC}" || true
  read -p "按回车继续"
}

set_proxy() {
  clear; echo -e "${YELLOW}动态IP一键配置${NC}"
  read -p "粘贴代理那一整行 > " line
  [[ -z "$line" ]] && return
  sudo cp /etc/proxychains.conf /etc/proxychains.conf.bak 2>/dev/null || true
  sudo sed -i '/^http\|^socks/d' /etc/proxychains.conf
  echo "$line" | sudo tee -a /etc/proxychains.conf >/dev/null
  echo -e "${GREEN}配置完成！当前IP: $(proxychains -q curl -s ipinfo.io/ip)${NC}"
  read -p "按回车继续"
}

start_node() {
  echo -e "${YELLOW}启动Miden全节点...${NC}"
  nohup miden-node --rpc https://testnet-rpc.miden.xyz --store ~/.miden-node >> "$LOG_DIR/node.log" 2>&1 &
  echo $! > $NODE_PID
  echo -e "${GREEN}节点已启动！日志 tail -f $LOG_DIR/node.log${NC}"
  read -p "按回车继续"
}

pioneer_feedback() {
  clear; echo -e "${YELLOW}Pioneer反馈（每天一次就爆分）${NC}"
  read -p "输入反馈内容（回车用默认） > " msg
  [[ -z "$msg" ]] && msg="Testnet运行稳定，建议增加更多MASM教程"
  curl -s -X POST "https://miden.xyz/api/pioneer-feedback" -d "{\"msg\":\"$msg\"}" >/dev/null
  echo -e "${GREEN}反馈已提交！${NC}"
  read -p "按回车继续"
}

# 你最爱的原始菜单（一个字没改！）
menu() {
  while true; do
    banner
    echo -e "${BLUE}=== Miden 0撸终极神器 ===${NC}"
    echo "1) 一键安装所有依赖（只跑一次）"
    echo "2) 无限生成钱包（支持10万+，自动分批+日志）"
    echo "3) 启动全自动刷子（领水+无限tx）"
    echo "4) 停止刷子"
    echo "5) 查看实时日志"
    echo "6) 一键打开 Midenscan 批量查积分"
    echo "7) 动态IP快速配置"
    echo "8) 启动 Miden 全节点（+500% bonus）"
    echo "9) 提交 Pioneer 反馈（前0.1%必备）"
    echo "0) 退出"
    echo "============================"
    read -p "输入数字 > " n
    case $n in
      1) install_deps; read -p "按回车继续";;
      2) gen_unlimited; read -p "按回车继续";;
      3) start_brush; read -p "已启动，按回车继续";;
      4) stop_brush;;
      5) tail -f "$LOG_FILE";;
      6) xdg-open "https://testnet.midenscan.com/accounts?list=$(find $ACCOUNTS_DIR -name 'batch_*.txt' -exec cat {} + | paste -sd, -)" 2>/dev/null || open "https://testnet.midenscan.com/"; read -p "按回车继续";;
      7) set_proxy;;
      8) start_node;;
      9) pioneer_feedback;;
      0) echo "2026 Q1 见！" ; exit 0;;
      *) echo "输错了"; sleep 1;;
    esac
  done
}

[[ $EUID -eq 0 ]] && echo "别用root" && exit 1
menu
