#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

# ----------- 可配置参数（可在运行前导出环境变量覆盖） -----------
CHAIN="${CHAIN:-dockerized-node}"
PRIVATE_KEY="${PRIVATE_KEY:-0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110}"
ACCOUNT_ADDRESS="${ACCOUNT_ADDRESS:-0x36615cf349d7f6344891b1e7ca7c72883f5dc049}"
L1_RPC="${L1_RPC:-http://127.0.0.1:8545}"
L2_RPC="${L2_RPC:-http://127.0.0.1:3050}"
DEPOSIT_AMOUNT="${DEPOSIT_AMOUNT:-0.01}"     # L1 -> L2
WITHDRAW_AMOUNT="${WITHDRAW_AMOUNT:-0.005}"  # L2 -> L1
DEPOSIT_WAIT_SECONDS="${DEPOSIT_WAIT_SECONDS:-60}"          # 等待存款到账
WITHDRAW_FINALIZE_WAIT="${WITHDRAW_FINALIZE_WAIT:-120}"     # 等待可 finalize
TOKEN_ADDRESS="${TOKEN_ADDRESS:-}"           # ERC20 地址，如为空则默认 ETH
# -------------------------------------------------------------

ZK_CLI_CMD=(npx "zksync-cli" "bridge")

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "错误: 未找到命令 $1"
    exit 1
  fi
}

require npx
require grep

token_args=()
if [[ -n "$TOKEN_ADDRESS" ]]; then
  token_args+=(--token "$TOKEN_ADDRESS")
fi

run_command() {
  local desc="$1"
  shift
  log "$desc"
  local output
  if ! output="$("$@" 2>&1)"; then
    printf '%s\n' "$output" >&2
    log "命令失败: $*"
    exit 1
  fi
  printf '%s\n' "$output" >&2
  printf '%s\n' "$output" >> logs/bridge-test.log
  echo "$output"
}

extract_hash() {
  local text="$1"
  local hash
  hash=$(echo "$text" | grep -Eo '0x[0-9a-fA-F]{64}' | tail -1 || true)
  if [[ -z "$hash" ]]; then
    log "无法从输出中解析交易哈希"
    echo ""
  else
    echo "$hash"
  fi
}

ensure_logs_dir() {
  mkdir -p logs
  : > logs/bridge-test.log
}

deposit_l1_to_l2() {
  local output
  output=$(run_command "执行 L1 → L2 存款，金额 $DEPOSIT_AMOUNT ETH" \
    "${ZK_CLI_CMD[@]}" deposit \
    --chain "$CHAIN" \
    --amount "$DEPOSIT_AMOUNT" \
    --recipient "$ACCOUNT_ADDRESS" \
    --l1-rpc "$L1_RPC" \
    --rpc "$L2_RPC" \
    --private-key "$PRIVATE_KEY" \
    ${token_args[@]+"${token_args[@]}"} )
  local hash
  hash=$(extract_hash "$output")
  if [[ -z "$hash" ]]; then
    log "警告: 未能解析存款交易哈希，请检查上方输出"
  else
    log "存款 TX: $hash"
  fi
  log "等待 $DEPOSIT_WAIT_SECONDS 秒让 L2 同步..."
  sleep "$DEPOSIT_WAIT_SECONDS"
}

withdraw_l2_to_l1() {
  local output
  output=$(run_command "执行 L2 → L1 提现，金额 $WITHDRAW_AMOUNT ETH" \
    "${ZK_CLI_CMD[@]}" withdraw \
    --chain "$CHAIN" \
    --amount "$WITHDRAW_AMOUNT" \
    --recipient "$ACCOUNT_ADDRESS" \
    --l1-rpc "$L1_RPC" \
    --rpc "$L2_RPC" \
    --private-key "$PRIVATE_KEY" \
    ${token_args[@]+"${token_args[@]}"} )
  local withdraw_hash
  withdraw_hash=$(extract_hash "$output")
  if [[ -z "$withdraw_hash" ]]; then
    log "错误: 无法获取提现交易哈希，无法继续"
    exit 1
  fi
  log "提现 TX: $withdraw_hash"
  echo "$withdraw_hash"
}

finalize_withdrawal() {
  local withdraw_hash="$1"
  log "等待 $WITHDRAW_FINALIZE_WAIT 秒，确保撤回批次已在 L1 可用..."
  sleep "$WITHDRAW_FINALIZE_WAIT"
  run_command "对提现进行 finalization" \
    "${ZK_CLI_CMD[@]}" withdraw-finalize \
    --chain "$CHAIN" \
    --hash "$withdraw_hash" \
    --l1-rpc "$L1_RPC" \
    --rpc "$L2_RPC" \
    --private-key "$PRIVATE_KEY"
}

main() {
  ensure_logs_dir
  log "开始 L1 ↔ L2 跨链测试 (链: $CHAIN)"
  deposit_l1_to_l2
  local withdraw_hash
  withdraw_hash=$(withdraw_l2_to_l1)
  finalize_withdrawal "$withdraw_hash"
  log "跨链测试完成，详情见 logs/bridge-test.log"
}

main "$@"

