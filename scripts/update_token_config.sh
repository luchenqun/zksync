#!/usr/bin/env bash
set -euo pipefail

# 手动更新 token 配置的辅助脚本
# 用法: ./scripts/update_token_config.sh <TOKEN_ADDRESS>

log() {
  printf '\x1b[32m[%s]\x1b[0m %s\n' "$(date '+%H:%M:%S')" "$*"
}

error() {
  printf '\x1b[31m[%s] ERROR:\x1b[0m %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

if [ $# -lt 1 ]; then
  error "用法: $0 <TOKEN_ADDRESS>"
  echo "示例: $0 0x1234567890123456789012345678901234567890"
  exit 1
fi

TOKEN_ADDRESS="$1"
CHAIN_NAME="${CHAIN_NAME:-custom_zkchain}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log "更新 token 配置..."
log "Token Address: $TOKEN_ADDRESS"
log "Chain Name: $CHAIN_NAME"

# 更新 .env
ENV_FILE="${PROJECT_ROOT}/.env"
if [ -f "$ENV_FILE" ]; then
  if grep -q "TOKEN_ADDRESS=" "$ENV_FILE"; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s|^TOKEN_ADDRESS=.*|TOKEN_ADDRESS=${TOKEN_ADDRESS}|" "$ENV_FILE"
    else
      sed -i "s|^TOKEN_ADDRESS=.*|TOKEN_ADDRESS=${TOKEN_ADDRESS}|" "$ENV_FILE"
    fi
  else
    echo "TOKEN_ADDRESS=${TOKEN_ADDRESS}" >> "$ENV_FILE"
  fi
  log "✓ 已更新 .env"
else
  error ".env 文件不存在"
fi

# 更新 ZkStack.yaml
ZKSTACK_YAML="${PROJECT_ROOT}/chains/${CHAIN_NAME}/ZkStack.yaml"
if [ -f "$ZKSTACK_YAML" ]; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|^\(\s*address:\s*\).*|\1${TOKEN_ADDRESS}|" "$ZKSTACK_YAML"
  else
    sed -i "s|^\(\s*address:\s*\).*|\1${TOKEN_ADDRESS}|" "$ZKSTACK_YAML"
  fi
  log "✓ 已更新 chains/${CHAIN_NAME}/ZkStack.yaml"
else
  error "ZkStack.yaml 不存在: $ZKSTACK_YAML"
fi

# 更新 contracts.yaml
CONTRACTS_YAML="${PROJECT_ROOT}/chains/${CHAIN_NAME}/configs/contracts.yaml"
if [ -f "$CONTRACTS_YAML" ]; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|^\(\s*base_token_addr:\s*\).*|\1${TOKEN_ADDRESS}|" "$CONTRACTS_YAML"
  else
    sed -i "s|^\(\s*base_token_addr:\s*\).*|\1${TOKEN_ADDRESS}|" "$CONTRACTS_YAML"
  fi
  log "✓ 已更新 chains/${CHAIN_NAME}/configs/contracts.yaml"
else
  error "contracts.yaml 不存在: $CONTRACTS_YAML"
fi

# 更新 portal.config.json
PORTAL_CONFIG="${PROJECT_ROOT}/configs/apps/portal.config.json"
if [ -f "$PORTAL_CONFIG" ]; then
  log "更新 configs/apps/portal.config.json..."

  if command -v jq >/dev/null 2>&1; then
    # 使用 jq 更新 JSON
    TMP_FILE=$(mktemp)
    jq --arg chain "$CHAIN_NAME" --arg addr "$TOKEN_ADDRESS" \
      '(.hyperchainsConfig[] | select(.network.key == $chain) | .tokens[] | select(.address == "0x000000000000000000000000000000000000800A") | .l1Address) = $addr' \
      "$PORTAL_CONFIG" > "$TMP_FILE" && mv "$TMP_FILE" "$PORTAL_CONFIG"
    log "✓ 已更新 configs/apps/portal.config.json"
  else
    # 如果没有 jq，使用 sed
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
log "配置更新完成！"
log "已更新以下文件:"
log "  - .env"
log "  - chains/${CHAIN_NAME}/ZkStack.yaml"
log "  - chains/${CHAIN_NAME}/configs/contracts.yaml"
log "  - configs/apps/portal.config.json"
log "  - configs/apps/explorer.config.json"
log "========================================="
