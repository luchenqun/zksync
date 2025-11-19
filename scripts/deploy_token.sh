#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# 从 wallets.yaml 提取 governor private key
WALLETS_FILE="${PROJECT_ROOT}/configs/wallets.yaml"

if [ ! -f "$WALLETS_FILE" ]; then
  echo "错误: 未找到 wallets.yaml 文件: $WALLETS_FILE"
  exit 1
fi

GOVERNOR_PRIVATE_KEY=$(yq eval '.governor.private_key' "$WALLETS_FILE")
GOVERNOR_ADDRESS=$(yq eval '.governor.address' "$WALLETS_FILE")

if [ -z "$GOVERNOR_PRIVATE_KEY" ] || [ "$GOVERNOR_PRIVATE_KEY" = "null" ]; then
  echo "错误: 无法从 wallets.yaml 获取 governor private key"
  exit 1
fi

# 创建/更新 .env 文件
cat > .env <<EOF
WALLET_PRIVATE_KEY=${GOVERNOR_PRIVATE_KEY}
L1_RPC=http://127.0.0.1:8545
L2_RPC=http://127.0.0.1:3150
EOF

log "开始部署 ERC20 token..."
log "部署者地址: $GOVERNOR_ADDRESS"

# 部署合约
mkdir -p logs
npx hardhat ignition deploy ./ignition/modules/CustomBaseToken.ts --network localRethNode --reset 2>&1 | tee logs/token-deploy.log

# 从输出中提取 token address
TOKEN_ADDRESS=$(grep -Eo "CustomBaseToken#CustomBaseToken - 0x[0-9a-fA-F]{40}" logs/token-deploy.log | grep -Eo "0x[0-9a-fA-F]{40}" || true)

if [ -z "$TOKEN_ADDRESS" ]; then
  echo "错误: 无法从部署输出中提取 token address"
  exit 1
fi

log "Token 部署成功！"
log "Token Address: $TOKEN_ADDRESS"

# 添加到 .env
echo "TOKEN_ADDRESS=${TOKEN_ADDRESS}" >> .env

# 验证余额
log "验证 token balance..."
BALANCE=$(cast balance --erc20 "$TOKEN_ADDRESS" "$GOVERNOR_ADDRESS" --rpc-url http://127.0.0.1:8545)
log "Governor ($GOVERNOR_ADDRESS) balance: $BALANCE"

log "========================================="
log "部署完成！"
log "Token Address: $TOKEN_ADDRESS"
log "已保存到 .env 文件"
log "========================================="
