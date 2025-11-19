#!/usr/bin/env bash
set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
  printf "${GREEN}[%s]${NC} %s\n" "$(date '+%H:%M:%S')" "$*"
}

error() {
  printf "${RED}[%s] ERROR:${NC} %s\n" "$(date '+%H:%M:%S')" "$*" >&2
}

warn() {
  printf "${YELLOW}[%s] WARNING:${NC} %s\n" "$(date '+%H:%M:%S')" "$*"
}

# ----------- 配置参数 -----------
CHAIN_NAME="${CHAIN_NAME:-custom_zkchain}"
CHAIN_ID="${CHAIN_ID:-272}"
TOKEN_NAME="${TOKEN_NAME:-ZK Base Token}"
TOKEN_SYMBOL="${TOKEN_SYMBOL:-ZKBT}"
PROVER_MODE="${PROVER_MODE:-NoProofs}"
COMMIT_DATA_MODE="${COMMIT_DATA_MODE:-Rollup}"
ENABLE_EVM_EMULATOR="${ENABLE_EVM_EMULATOR:-true}"
SET_AS_DEFAULT="${SET_AS_DEFAULT:-true}"
PRICE_NOMINATOR="${PRICE_NOMINATOR:-1}"
PRICE_DENOMINATOR="${PRICE_DENOMINATOR:-1}"

# RPC URLs
L1_RPC="${L1_RPC:-http://127.0.0.1:8545}"
L2_RPC_PORT="${L2_RPC_PORT:-3150}"

# Paths
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGS_DIR="${PROJECT_ROOT}/configs"
WALLETS_FILE="${CONFIGS_DIR}/wallets.yaml"
# -------------------------------------

cd "$PROJECT_ROOT"

# 检查必要的命令
require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "未找到命令: $1"
    exit 1
  fi
}

require npx
require zkstack
require yq

# 1. 安装依赖
install_dependencies() {
  log "安装项目依赖..."
  if [ ! -d "node_modules" ]; then
    npm install
  else
    log "依赖已安装，跳过"
  fi
}

# 2. 部署 ERC20 token 到 L1
deploy_token() {
  log "部署 ERC20 token 到 L1..."

  # 从 wallets.yaml 提取 governor private key
  if [ ! -f "$WALLETS_FILE" ]; then
    error "未找到 wallets.yaml 文件: $WALLETS_FILE"
    exit 1
  fi

  GOVERNOR_PRIVATE_KEY=$(yq eval '.governor.private_key' "$WALLETS_FILE")
  if [ -z "$GOVERNOR_PRIVATE_KEY" ] || [ "$GOVERNOR_PRIVATE_KEY" = "null" ]; then
    error "无法从 wallets.yaml 获取 governor private key"
    exit 1
  fi

  # 更新 .env 文件
  cat > .env <<EOF
WALLET_PRIVATE_KEY=${GOVERNOR_PRIVATE_KEY}
L1_RPC=${L1_RPC}
L2_RPC=http://127.0.0.1:${L2_RPC_PORT}
EOF

  log "部署 token: $TOKEN_NAME ($TOKEN_SYMBOL)"

  # 部署合约
  if ! npx hardhat ignition deploy ./ignition/modules/CustomBaseToken.ts --network localRethNode --reset 2>&1 | tee logs/token-deploy.log; then
    error "Token 部署失败"
    exit 1
  fi

  # 从部署输出中提取 token address
  TOKEN_ADDRESS=$(grep -Eo "CustomBaseToken#CustomBaseToken - 0x[0-9a-fA-F]{40}" logs/token-deploy.log | grep -Eo "0x[0-9a-fA-F]{40}" || true)

  if [ -z "$TOKEN_ADDRESS" ]; then
    error "无法从部署输出中提取 token address"
    exit 1
  fi

  log "Token 部署成功: $TOKEN_ADDRESS"

  # 保存到 .env
  echo "TOKEN_ADDRESS=${TOKEN_ADDRESS}" >> .env

  # 验证 token balance
  GOVERNOR_ADDRESS=$(yq eval '.governor.address' "$WALLETS_FILE")
  log "验证 governor token balance..."
  BALANCE=$(cast balance --erc20 "$TOKEN_ADDRESS" "$GOVERNOR_ADDRESS" --rpc-url "$L1_RPC" || echo "0")
  log "Governor token balance: $BALANCE"
}

# 3. 创建新链
create_chain() {
  log "创建新的 ZK Chain: $CHAIN_NAME"

  # 检查链是否已存在
  if [ -d "chains/$CHAIN_NAME" ]; then
    warn "链 $CHAIN_NAME 已存在，跳过创建"
    return
  fi

  # 使用 zkstack chain create (需要手动交互)
  log "请按照以下配置创建链:"
  echo "  Chain name: $CHAIN_NAME"
  echo "  Chain ID: $CHAIN_ID"
  echo "  Wallet: Localhost"
  echo "  Prover mode: $PROVER_MODE"
  echo "  Commit data: $COMMIT_DATA_MODE"
  echo "  Base token: Custom"
  echo "  Token address: $TOKEN_ADDRESS"
  echo "  Price nominator: $PRICE_NOMINATOR"
  echo "  Price denominator: $PRICE_DENOMINATOR"
  echo "  EVM emulator: $ENABLE_EVM_EMULATOR"
  echo "  Set as default: $SET_AS_DEFAULT"
  echo ""

  read -p "按 Enter 继续创建链..."
  zkstack chain create
}

# 4. 初始化链
init_chain() {
  log "初始化链: $CHAIN_NAME"
  zkstack chain init --dev
}

# 5. 启动链服务器
start_server() {
  log "启动链服务器..."
  log "服务器将在后台运行，监听端口 $L2_RPC_PORT"
  log "日志文件: logs/server.log"

  mkdir -p logs
  nohup zkstack server > logs/server.log 2>&1 &
  SERVER_PID=$!
  echo $SERVER_PID > .pids/server.pid

  log "等待服务器启动..."
  sleep 10

  if ps -p $SERVER_PID > /dev/null; then
    log "服务器已启动 (PID: $SERVER_PID)"
  else
    error "服务器启动失败，请查看 logs/server.log"
    exit 1
  fi
}

# 6. Bridge base token 到 L2
bridge_base_token() {
  log "Bridge base token 到 L2..."

  # 等待服务器完全启动
  log "等待 L2 节点完全启动..."
  for i in {1..30}; do
    if curl -s -X POST -H "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
      "http://127.0.0.1:${L2_RPC_PORT}" > /dev/null 2>&1; then
      log "L2 节点已就绪"
      break
    fi
    if [ $i -eq 30 ]; then
      error "L2 节点启动超时"
      exit 1
    fi
    sleep 2
  done

  npx hardhat run scripts/depositBaseToken.ts
}

# 7. 显示配置信息
show_info() {
  log "========================================="
  log "ERC20 Base Token Chain 设置完成！"
  log "========================================="
  log "Chain name: $CHAIN_NAME"
  log "Chain ID: $CHAIN_ID"
  log "L1 RPC: $L1_RPC"
  log "L2 RPC: http://127.0.0.1:${L2_RPC_PORT}"
  log "Token address: $TOKEN_ADDRESS"
  log "Token name: $TOKEN_NAME"
  log "Token symbol: $TOKEN_SYMBOL"
  log "========================================="
  log ""
  log "有用的命令:"
  log "  - 查看服务器日志: tail -f logs/server.log"
  log "  - 停止服务器: kill \$(cat .pids/server.pid)"
  log "  - Bridge base token: npm run bridge:base-token"
  log "  - Bridge ETH: npm run bridge:eth"
  log "========================================="
}

# 主流程
main() {
  mkdir -p logs .pids

  log "开始设置 ERC20 Base Token Chain"
  log "项目目录: $PROJECT_ROOT"

  install_dependencies
  deploy_token
  create_chain
  init_chain
  start_server
  bridge_base_token
  show_info
}

main "$@"
