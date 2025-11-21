#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"
GENESIS_FILE="$REPO_ROOT/zksync-era/etc/reth/chaindata/reth_config"
VOLUMES=(zksync_postgres-data zksync_reth-data)
LOG_DIR="$REPO_ROOT/logs"
INIT_LOG_FILE="$LOG_DIR/ecosystem-init.log"
PID_DIR="$REPO_ROOT/.pids"
L2_SCRIPT="$SCRIPT_DIR/l2.sh"
BLOCKSCOUT_SCRIPT="$REPO_ROOT/blockscout/deploy.sh"

# 确保日志目录存在
mkdir -p "$LOG_DIR"

detect_docker_compose() {
  if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD=(docker-compose)
  elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD=(docker compose)
  else
    log "无法找到 docker-compose 或 docker compose，请先安装 Docker"
    exit 1
  fi
}

detect_docker_compose

compose() {
  (cd "$REPO_ROOT" && "${DOCKER_COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" "$@")
}

# 检查 L2 是否在运行
check_l2_running() {
  local l2_running=false

  # 检查 PID 文件
  if [[ -d "$PID_DIR" ]]; then
    for pid_file in "$PID_DIR"/*.pid; do
      if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
          l2_running=true
          log "检测到运行中的 L2 进程: $(basename "$pid_file") (PID: $pid)"
          break
        fi
      fi
    done
  fi

  # 检查是否有 zkstack server/portal 相关进程在运行
  if pgrep -f "zkstack server" >/dev/null 2>&1 || \
     pgrep -f "zkstack portal" >/dev/null 2>&1 || \
     pgrep -f "zkstack explorer" >/dev/null 2>&1; then
    l2_running=true
    log "检测到运行中的 zkstack 进程"
  fi

  # 检查是否有 explorer 相关的 docker 容器在运行
  if docker ps --format '{{.Names}}' | grep -q "explorer"; then
    l2_running=true
    log "检测到运行中的 explorer 容器:"
    docker ps --format '{{.Names}}' | grep "explorer" || true
  fi

  if [[ "$l2_running" == "true" ]]; then
    return 0
  else
    return 1
  fi
}

# 停止 L2 服务
stop_l2() {
  log '检测到 L2 服务正在运行，正在停止...'

  # 遍历所有链，对每个链调用 l2.sh stop
  if [[ -d "$REPO_ROOT/chains" ]]; then
    for chain_dir in "$REPO_ROOT/chains"/*; do
      if [[ -d "$chain_dir" ]]; then
        local chain_name=$(basename "$chain_dir")
        log "停止链 $chain_name 的 L2 服务..."
        "$L2_SCRIPT" --chain "$chain_name" stop 2>/dev/null || true
      fi
    done
  fi

  # 等待停止完成
  sleep 2

  # 验证是否真的停止了
  if check_l2_running; then
    log '警告: L2 服务可能未完全停止，请检查'
    exit 1
  fi

  log 'L2 服务已停止'
}

stop_stack() {
  log '停止 docker-compose 服务'
  compose down

  log '停止 Blockscout 服务'
  "$BLOCKSCOUT_SCRIPT" stop
}

start_stack() {
  log '启动 docker-compose 服务'
  compose up -d

  log '启动 Blockscout 服务'
  "$BLOCKSCOUT_SCRIPT" start
}

remove_volumes() {
  log '当前卷列表：'
  docker volume ls | grep zksync || true

  log '删除旧卷（如不存在将忽略错误）'
  docker volume rm -f "${VOLUMES[@]}" || true
}

reset_stack() {
  # 检查并停止 L2 服务
  if check_l2_running; then
    stop_l2
  fi

  # 先停止 blockscout（因为它依赖 zksync_default 网络）
  log '停止 Blockscout 服务'
  "$BLOCKSCOUT_SCRIPT" stop

  stop_stack
  remove_volumes
  start_stack

  # 在 L1 启动后再重置 blockscout（此时 zksync_default 网络已存在）
  log '重置 Blockscout 服务'
  "$BLOCKSCOUT_SCRIPT" reset
}

reset_and_init() {
  log '========== 重置并初始化生态系统 =========='
  reset_stack
  log '等待服务启动...'
  sleep 5
  init_ecosystem
  log '========== 重置和初始化完成 =========='
}

init_ecosystem() {
  log '初始化生态系统 (zkstack ecosystem init --chain zkchain --dev --verbose)'
  log "日志将保存到: $INIT_LOG_FILE"
  cd "$REPO_ROOT"
  zkstack ecosystem --chain zkchain init --dev --verbose 2>&1 | tee "$INIT_LOG_FILE"
  local exit_code=${PIPESTATUS[0]}
  if [[ $exit_code -eq 0 ]]; then
    log '生态系统初始化完成'
  else
    log "错误: 生态系统初始化失败 (退出码: $exit_code)"
    log "请查看日志: $INIT_LOG_FILE"
    exit $exit_code
  fi
}

show_usage() {
  cat <<EOF
用法: scripts/l1.sh [start|stop|reset|reset-init|status|init]

  start       直接启动 docker-compose (docker-compose up -d)
  stop        停止所有服务 (docker-compose down)
  reset       stop -> 删除卷 -> start
  reset-init  reset -> 等待服务启动 -> init
  status      查看 docker-compose ps
  init        初始化生态系统 (zkstack ecosystem init --dev --verbose)
              日志保存到: logs/ecosystem-init.log

EOF
}

case "${1:-help}" in
  start)
    start_stack
    ;;
  stop)
    stop_stack
    ;;
  reset)
    reset_stack
    ;;
  reset-init)
    reset_and_init
    ;;
  status)
    compose ps
    ;;
  init)
    init_ecosystem
    ;;
  help|--help|-h)
    show_usage
    ;;
  *)
    printf '未知命令: %s\n\n' "${1:-}"
    show_usage
    exit 1
    ;;
esac

