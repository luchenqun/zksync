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

# 更新 ZkStack.yaml
CHAIN_NAME="${CHAIN_NAME:-custom_zkchain}"
ZKSTACK_YAML="${PROJECT_ROOT}/chains/${CHAIN_NAME}/ZkStack.yaml"

if [ -f "$ZKSTACK_YAML" ]; then
  log "更新 ${CHAIN_NAME}/ZkStack.yaml..."
  # 使用 sed 更新 base_token.address
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s|^\(\s*address:\s*\).*|\1${TOKEN_ADDRESS}|" "$ZKSTACK_YAML"
  else
    # Linux
    sed -i "s|^\(\s*address:\s*\).*|\1${TOKEN_ADDRESS}|" "$ZKSTACK_YAML"
  fi
  log "✓ 已更新 ${CHAIN_NAME}/ZkStack.yaml"
else
  log "⚠ 链配置文件不存在，跳过更新: $ZKSTACK_YAML"
fi

# 更新 contracts.yaml
CONTRACTS_YAML="${PROJECT_ROOT}/chains/${CHAIN_NAME}/configs/contracts.yaml"

if [ -f "$CONTRACTS_YAML" ]; then
  log "更新 ${CHAIN_NAME}/configs/contracts.yaml..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s|^\(\s*base_token_addr:\s*\).*|\1${TOKEN_ADDRESS}|" "$CONTRACTS_YAML"
  else
    # Linux
    sed -i "s|^\(\s*base_token_addr:\s*\).*|\1${TOKEN_ADDRESS}|" "$CONTRACTS_YAML"
  fi
  log "✓ 已更新 ${CHAIN_NAME}/configs/contracts.yaml"
else
  log "⚠ 合约配置文件不存在，跳过更新: $CONTRACTS_YAML"
fi

# 更新 portal.config.json
PORTAL_CONFIG="${PROJECT_ROOT}/configs/apps/portal.config.json"

if [ -f "$PORTAL_CONFIG" ]; then
  log "更新 configs/apps/portal.config.json..."

  # 使用 jq 或手动替换
  if command -v jq >/dev/null 2>&1; then
    # 使用 jq 更新 JSON
    TMP_FILE=$(mktemp)
    jq --arg chain "$CHAIN_NAME" --arg addr "$TOKEN_ADDRESS" \
      '(.hyperchainsConfig[] | select(.network.key == $chain) | .tokens[] | select(.address == "0x000000000000000000000000000000000000800A") | .l1Address) = $addr' \
      "$PORTAL_CONFIG" > "$TMP_FILE" && mv "$TMP_FILE" "$PORTAL_CONFIG"
    log "✓ 已更新 configs/apps/portal.config.json"
  else
    # 如果没有 jq，使用 sed（不太可靠，但可以工作）
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s|\"l1Address\": \"0x[0-9a-fA-F]*\"|\"l1Address\": \"${TOKEN_ADDRESS}\"|g" "$PORTAL_CONFIG"
    else
      sed -i "s|\"l1Address\": \"0x[0-9a-fA-F]*\"|\"l1Address\": \"${TOKEN_ADDRESS}\"|g" "$PORTAL_CONFIG"
    fi
    log "✓ 已更新 configs/apps/portal.config.json (使用 sed)"
  fi
else
  log "⚠ Portal 配置文件不存在，跳过更新: $PORTAL_CONFIG"
fi

# 更新 explorer.config.json
EXPLORER_CONFIG="${PROJECT_ROOT}/configs/apps/explorer.config.json"

if [ -f "$EXPLORER_CONFIG" ]; then
  log "更新 configs/apps/explorer.config.json..."

  if command -v jq >/dev/null 2>&1; then
    # 使用 jq 更新 JSON
    TMP_FILE=$(mktemp)
    jq --arg chain "$CHAIN_NAME" --arg addr "$TOKEN_ADDRESS" \
      '(.environmentConfig.networks[] | select(.name == $chain) | .baseTokenAddress) = $addr' \
      "$EXPLORER_CONFIG" > "$TMP_FILE" && mv "$TMP_FILE" "$EXPLORER_CONFIG"
    log "✓ 已更新 configs/apps/explorer.config.json"
  else
    # 如果没有 jq，使用 sed
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s|\"baseTokenAddress\": \"0x[0-9a-fA-F]*\"|\"baseTokenAddress\": \"${TOKEN_ADDRESS}\"|g" "$EXPLORER_CONFIG"
    else
      sed -i "s|\"baseTokenAddress\": \"0x[0-9a-fA-F]*\"|\"baseTokenAddress\": \"${TOKEN_ADDRESS}\"|g" "$EXPLORER_CONFIG"
    fi
    log "✓ 已更新 configs/apps/explorer.config.json (使用 sed)"
  fi
else
  log "⚠ Explorer 配置文件不存在，跳过更新: $EXPLORER_CONFIG"
fi

log "========================================="
log "部署完成！"
log "========================================="
log "Token Address: $TOKEN_ADDRESS"
log "已自动更新以下文件:"
log "  - .env"
log "  - chains/${CHAIN_NAME}/ZkStack.yaml"
log "  - chains/${CHAIN_NAME}/configs/contracts.yaml"
log "  - configs/apps/portal.config.json"
log "  - configs/apps/explorer.config.json"
log "========================================="
