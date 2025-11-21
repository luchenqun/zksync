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

# 是否启动 blockscout（默认不启动，需要 --scan 参数）
ENABLE_BLOCKSCOUT=false

# L2 链名称（如果指定，会自动启动对应的 L2 链）
L2_CHAIN_NAME=""

# 要初始化的链列表（用逗号分隔，如 zkchain,custom_zkchain）
INIT_CHAINS=""

# 在 reset 后要启动的 L2 链名称
START_L2_CHAIN=""

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

# 检查指定的链是否在初始化列表中
should_init_chain() {
  local chain_name="$1"
  if [[ -z "$INIT_CHAINS" ]]; then
    return 1
  fi
  # 将逗号分隔的字符串转换为数组
  IFS=',' read -ra chains <<< "$INIT_CHAINS"
  for chain in "${chains[@]}"; do
    # 去除前后空格
    chain=$(echo "$chain" | xargs)
    if [[ "$chain" == "$chain_name" ]]; then
      return 0
    fi
  done
  return 1
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
  log '停止 Blockscout 服务'
  "$BLOCKSCOUT_SCRIPT" stop

  log '停止 docker-compose 服务'
  compose down

  log '停止 L2 服务'
  stop_l2
}

start_stack() {
  log '启动 docker-compose 服务'
  compose up -d

  if [[ "$ENABLE_BLOCKSCOUT" == "true" ]]; then
    log '启动 Blockscout 服务'
    "$BLOCKSCOUT_SCRIPT" start
  fi

  # 如果指定了 L2 链名称，自动启动对应的 L2 链
  if [[ -n "$L2_CHAIN_NAME" ]]; then
    log "自动启动 L2 链: $L2_CHAIN_NAME"
    "$L2_SCRIPT" --chain "$L2_CHAIN_NAME" start
  fi
}

remove_volumes() {
  log '当前卷列表：'
  docker volume ls | grep zksync || true

  log '删除旧卷（如不存在将忽略错误）'
  docker volume rm -f "${VOLUMES[@]}" || true
}

reset_stack() {
  log '========== 重置生态系统 =========='

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
  # 只有启用了 --scan 参数才重新启动 Blockscout
  if [[ "$ENABLE_BLOCKSCOUT" == "true" ]]; then
    log '重置 Blockscout 服务'
    "$BLOCKSCOUT_SCRIPT" reset
  else
    log '移除 Blockscout 服务'
    "$BLOCKSCOUT_SCRIPT" remove
  fi

  # 如果指定了要初始化的链，执行相应的初始化流程
  if [[ -n "$INIT_CHAINS" ]]; then
    log '等待服务启动...'
    sleep 5

    # 初始化 zkchain
    if should_init_chain "zkchain"; then
      log '初始化 zkchain...'
      init_ecosystem

      log '部署 Gas Token...'
      cd "$REPO_ROOT"
      npm run deploy:gas-token
    fi

    # 初始化 custom_zkchain
    if should_init_chain "custom_zkchain"; then
      log '初始化 custom_zkchain...'
      "$L2_SCRIPT" init-custom-zkchain
    fi
  fi

  # 如果指定了要启动的 L2 链，自动启动
  if [[ -n "$START_L2_CHAIN" ]]; then
    log "自动启动 L2 链: $START_L2_CHAIN"
    "$L2_SCRIPT" --chain "$START_L2_CHAIN" start
  fi

  log '========== 重置完成 =========='
}

restart_stack() {
  log '========== 重启服务 =========='
  stop_stack
  log '等待 2 秒...'
  sleep 2
  start_stack
  log '========== 重启完成 =========='
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
用法: scripts/l1.sh [选项] [命令]

选项:
  --scan                    启动 Blockscout 区块浏览器
  --chain <链名称>          启动 L1 后自动启动指定的 L2 链（用于 start/restart）
  --init <链列表>           在 reset 命令后初始化指定的链（用逗号分隔）
                            支持的链: zkchain, custom_zkchain
                            - zkchain: 初始化生态系统并部署 gas token
                            - custom_zkchain: 初始化 custom_zkchain
  --start-l2 <链名称>       在 reset 命令后自动启动指定的 L2 链
                            支持的链: zkchain, custom_zkchain

命令:
  start       直接启动 docker-compose (docker-compose up -d)
  stop        停止所有服务 (docker-compose down)
  restart     重启所有服务 (stop -> start)
  reset       stop -> 删除卷 -> start
  status      查看 docker-compose ps
  init        初始化生态系统 (zkstack ecosystem init --dev --verbose)
              日志保存到: logs/ecosystem-init.log

示例:
  ./scripts/l1.sh start                                                # 启动 L1
  ./scripts/l1.sh start --scan                                         # 启动 L1 和 Blockscout
  ./scripts/l1.sh start --chain zkchain                                # 启动 L1 和 zkchain
  ./scripts/l1.sh restart --scan --chain zkchain                       # 重启 L1、Blockscout 和 zkchain
  ./scripts/l1.sh reset                                                # 重置 L1（不初始化）
  ./scripts/l1.sh reset --init=zkchain                                 # 重置并初始化 zkchain
  ./scripts/l1.sh reset --init=custom_zkchain                          # 重置并初始化 custom_zkchain
  ./scripts/l1.sh reset --init=zkchain,custom_zkchain                  # 重置并初始化两条链
  ./scripts/l1.sh reset --init=zkchain,custom_zkchain --scan           # 重置、初始化两条链并启动 Blockscout
  ./scripts/l1.sh reset --init=zkchain --start-l2=zkchain --scan       # 完整流程：重置、初始化、启动 L2 和 Blockscout

EOF
}

# 从 npm_config 环境变量读取参数（支持 npm run reset --init=zkchain --scan --start-l2=zkchain）
[[ -n "${npm_config_chain:-}" ]] && L2_CHAIN_NAME="$npm_config_chain"
[[ -n "${npm_config_blockscout:-}" ]] && ENABLE_BLOCKSCOUT=true
[[ -n "${npm_config_scan:-}" ]] && ENABLE_BLOCKSCOUT=true
[[ -n "${npm_config_init:-}" ]] && INIT_CHAINS="$npm_config_init"
[[ -n "${npm_config_start_l2:-}" ]] && START_L2_CHAIN="$npm_config_start_l2"

# 解析参数
CMD=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --scan)
      ENABLE_BLOCKSCOUT=true
      shift
      ;;
    --init=*)
      INIT_CHAINS="${1#*=}"
      shift
      ;;
    --init)
      if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
        INIT_CHAINS="$2"
        shift 2
      else
        log "错误: --init 需要指定链名称（如 zkchain,custom_zkchain）"
        show_usage
        exit 1
      fi
      ;;
    --chain)
      if [[ -z "${2:-}" ]]; then
        log "错误: --chain 需要指定链名称"
        show_usage
        exit 1
      fi
      L2_CHAIN_NAME="$2"
      shift 2
      ;;
    --start-l2=*)
      START_L2_CHAIN="${1#*=}"
      shift
      ;;
    --start-l2)
      if [[ -z "${2:-}" ]]; then
        log "错误: --start-l2 需要指定链名称"
        show_usage
        exit 1
      fi
      START_L2_CHAIN="$2"
      shift 2
      ;;
    start|stop|restart|reset|status|init|help|--help|-h)
      CMD="$1"
      shift
      ;;
    *)
      if [[ -z "$CMD" ]]; then
        printf '未知参数: %s\n\n' "$1"
        show_usage
        exit 1
      fi
      shift
      ;;
  esac
done

# 如果没有命令，默认为 help
CMD="${CMD:-help}"

case "$CMD" in
  start)
    start_stack
    ;;
  stop)
    stop_stack
    ;;
  restart)
    restart_stack
    ;;
  reset)
    reset_stack
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
    printf '未知命令: %s\n\n' "$CMD"
    show_usage
    exit 1
    ;;
esac

