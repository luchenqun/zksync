#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PID_DIR="$REPO_ROOT/.pids"

# 默认链名称
CHAIN_NAME="${CHAIN_NAME:-zkchain}"
EXPLORER_COMPOSE_FILE="$REPO_ROOT/chains/$CHAIN_NAME/configs/explorer-docker-compose.yml"
OBSERVABILITY_COMPOSE_FILE="$REPO_ROOT/era-observability/docker-compose.yml"

# 确保 PID 目录存在
mkdir -p "$PID_DIR"

# PID 文件路径
SERVER_PID_FILE="$PID_DIR/zkstack-server.pid"
PORTAL_PID_FILE="$PID_DIR/zkstack-portal.pid"
EXPLORER_PID_FILE="$PID_DIR/zkstack-explorer.pid"

# Docker 容器名称
PORTAL_CONTAINER_NAME="zksync-portal-app"
EXPLORER_CONTAINER_NAME="zksync-explorer-app"

detect_docker_compose() {
  if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD=(docker-compose)
  elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD=(docker compose)
  else
    log "错误: 无法找到 docker-compose 或 docker compose，请先安装 Docker"
    exit 1
  fi
}

detect_docker_compose

# 检查进程是否运行
is_running() {
  local pid_file="$1"
  if [[ -f "$pid_file" ]]; then
    local pid=$(cat "$pid_file" 2>/dev/null || echo "")
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    else
      # PID 文件存在但进程不存在，删除过期的 PID 文件
      rm -f "$pid_file"
      return 1
    fi
  fi
  return 1
}

# 启动 L2 服务器
start_server() {
  if is_running "$SERVER_PID_FILE"; then
    log "L2 服务器已在运行 (PID: $(cat "$SERVER_PID_FILE"))"
    return 0
  fi

  log "启动 L2 服务器 (zkstack server --chain $CHAIN_NAME)..."
  cd "$REPO_ROOT"
  
  # 使用追加模式写入日志，避免覆盖旧日志
  nohup zkstack server --chain "$CHAIN_NAME" >> "$REPO_ROOT/logs/server.log" 2>&1 &
  local pid=$!
  echo "$pid" > "$SERVER_PID_FILE"
  log "L2 服务器已启动 (PID: $pid)"
  
  # 等待更长时间，确保进程稳定启动
  sleep 3
  if ! kill -0 "$pid" 2>/dev/null; then
    log "错误: L2 服务器启动失败，请查看日志: $REPO_ROOT/logs/server.log"
    log "检查日志最后几行:"
    tail -20 "$REPO_ROOT/logs/server.log" | strings || tail -20 "$REPO_ROOT/logs/server.log"
    rm -f "$SERVER_PID_FILE"
    return 1
  fi
  
  log "L2 服务器运行正常"
}

# 停止 L2 服务器
stop_server() {
  # 先尝试通过 PID 文件停止
  if is_running "$SERVER_PID_FILE"; then
    local pid=$(cat "$SERVER_PID_FILE")
    log "停止 L2 服务器 (PID: $pid)..."
    kill "$pid" 2>/dev/null || true
    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
      log "强制停止 L2 服务器..."
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$SERVER_PID_FILE"
  fi

  # 检查是否有残留的 zksync_server 进程
  local remaining_pids=$(pgrep -f "zksync_server.*$CHAIN_NAME" 2>/dev/null || true)
  if [[ -n "$remaining_pids" ]]; then
    log "发现残留的 zksync_server 进程，正在停止..."
    echo "$remaining_pids" | xargs kill 2>/dev/null || true
    sleep 1
    echo "$remaining_pids" | xargs kill -9 2>/dev/null || true
  fi

  # 检查是否有残留的 zkstack server 进程
  local zkstack_pids=$(pgrep -f "zkstack server.*$CHAIN_NAME" 2>/dev/null || true)
  if [[ -n "$zkstack_pids" ]]; then
    log "发现残留的 zkstack server 进程，正在停止..."
    echo "$zkstack_pids" | xargs kill 2>/dev/null || true
    sleep 1
    echo "$zkstack_pids" | xargs kill -9 2>/dev/null || true
  fi

  log "L2 服务器已停止"
}

# 启动 Portal
start_portal() {
  if is_running "$PORTAL_PID_FILE"; then
    log "Portal 已在运行 (PID: $(cat "$PORTAL_PID_FILE"))"
    return 0
  fi

  remove_portal_container

  log "启动 Portal (zkstack portal)..."
  cd "$REPO_ROOT"
  nohup zkstack portal > "$REPO_ROOT/logs/portal.log" 2>&1 &
  local pid=$!
  echo "$pid" > "$PORTAL_PID_FILE"
  log "Portal 已启动 (PID: $pid)"
  sleep 2
  if ! kill -0 "$pid" 2>/dev/null; then
    log "错误: Portal 启动失败，请查看日志: $REPO_ROOT/logs/portal.log"
    rm -f "$PORTAL_PID_FILE"
    return 1
  fi
}

# 停止 Portal
stop_portal() {
  if ! is_running "$PORTAL_PID_FILE"; then
    log "Portal 未运行"
    remove_portal_container
    return 0
  fi

  local pid=$(cat "$PORTAL_PID_FILE")
  log "停止 Portal (PID: $pid)..."
  kill "$pid" 2>/dev/null || true
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    log "强制停止 Portal..."
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PORTAL_PID_FILE"
  log "Portal 已停止"

  remove_portal_container
}

remove_portal_container() {
  if docker ps -a --format '{{.Names}}' | grep -Fxq "$PORTAL_CONTAINER_NAME"; then
    log "移除残留 Portal 容器 ($PORTAL_CONTAINER_NAME)..."
    docker rm -f "$PORTAL_CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
}

# 启动 Explorer 后端
start_explorer_backend() {
  log "启动 Explorer 后端 (docker-compose)..."
  ensure_explorer_database
  cd "$REPO_ROOT"
  "${DOCKER_COMPOSE_CMD[@]}" -f "$EXPLORER_COMPOSE_FILE" up -d
  log "Explorer 后端已启动"
}

# 停止 Explorer 后端
stop_explorer_backend() {
  log "停止 Explorer 后端..."
  cd "$REPO_ROOT"
  "${DOCKER_COMPOSE_CMD[@]}" -f "$EXPLORER_COMPOSE_FILE" down
  log "Explorer 后端已停止"
}

# 清理 Explorer 容器
remove_explorer_container() {
  if docker ps -a --format '{{.Names}}' | grep -q "^${EXPLORER_CONTAINER_NAME}$"; then
    log "清理残留的 Explorer 容器: $EXPLORER_CONTAINER_NAME"
    docker rm -f "$EXPLORER_CONTAINER_NAME" 2>/dev/null || true
  fi
}

ensure_explorer_database() {
  local root_compose="$REPO_ROOT/docker-compose.yml"
  local db_name="zksync_explorer_localhost_${CHAIN_NAME}"

  if [[ ! -f "$root_compose" ]]; then
    log "警告: 未找到 $root_compose，无法自动确认 explorer 数据库是否存在"
    return 0
  fi

  log "确保 Postgres 服务运行 (docker-compose postgres)..."
  "${DOCKER_COMPOSE_CMD[@]}" -f "$root_compose" up -d postgres >/dev/null

  log "检查数据库 $db_name 是否存在..."
  if ! ${DOCKER_COMPOSE_CMD[@]} -f "$root_compose" exec -T postgres psql -U postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname='${db_name}'" | grep -q 1; then
    log "数据库 $db_name 不存在，正在创建..."
    ${DOCKER_COMPOSE_CMD[@]} -f "$root_compose" exec -T postgres psql -U postgres -c \
      "CREATE DATABASE \"${db_name}\";" >/dev/null || {
        log "错误: 创建数据库 $db_name 失败，请手动检查 Postgres 服务"
        exit 1
      }
    log "数据库 $db_name 创建完成"
  else
    log "数据库 $db_name 已存在"
  fi
}

clean_explorer_data() {
  log "========== 清理 Explorer 数据 =========="
  stop_explorer
  stop_explorer_backend

  local root_compose="$REPO_ROOT/docker-compose.yml"
  local db_name="zksync_explorer_localhost_${CHAIN_NAME}"

  if [[ ! -f "$root_compose" ]]; then
    log "未找到 $root_compose，无法清理数据库"
    return 1
  fi

  log "确保 Postgres 服务运行 (docker-compose postgres)..."
  "${DOCKER_COMPOSE_CMD[@]}" -f "$root_compose" up -d postgres >/dev/null

  log "终止数据库 $db_name 的所有连接"
  ${DOCKER_COMPOSE_CMD[@]} -f "$root_compose" exec -T postgres psql -U postgres -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$db_name';" >/dev/null 2>&1 || true

  log "删除数据库 $db_name (如不存在将忽略)..."
  ${DOCKER_COMPOSE_CMD[@]} -f "$root_compose" exec -T postgres psql -U postgres -c \
    "DROP DATABASE IF EXISTS \"$db_name\";" >/dev/null 2>&1 || {
      log "警告: 删除数据库 $db_name 失败"
      return 1
    }

  log "创建全新的数据库 $db_name"
  ${DOCKER_COMPOSE_CMD[@]} -f "$root_compose" exec -T postgres psql -U postgres -c \
    "CREATE DATABASE \"$db_name\";" >/dev/null 2>&1 || {
      log "警告: 创建数据库 $db_name 失败"
      return 1
    }

  log "Explorer 数据已清理，可重新启动相关服务"
}

start_observability() {
  if [[ ! -f "$OBSERVABILITY_COMPOSE_FILE" ]]; then
    log "未找到 $OBSERVABILITY_COMPOSE_FILE，跳过启动 observability"
    return
  fi
  log "启动 Era Observability..."
  "${DOCKER_COMPOSE_CMD[@]}" -f "$OBSERVABILITY_COMPOSE_FILE" up -d
  log "Era Observability 已启动"
}

stop_observability() {
  if [[ ! -f "$OBSERVABILITY_COMPOSE_FILE" ]]; then
    return
  fi
  log "停止 Era Observability..."
  "${DOCKER_COMPOSE_CMD[@]}" -f "$OBSERVABILITY_COMPOSE_FILE" down
  log "Era Observability 已停止"
}

observability_status() {
  if [[ ! -f "$OBSERVABILITY_COMPOSE_FILE" ]]; then
    log "Observability: 未配置 (缺少 era-observability/docker-compose.yml)"
    return
  fi
  log "Observability 服务状态:"
  "${DOCKER_COMPOSE_CMD[@]}" -f "$OBSERVABILITY_COMPOSE_FILE" ps
}

# 启动 Explorer 前端
start_explorer() {
  if is_running "$EXPLORER_PID_FILE"; then
    log "Explorer 前端已在运行 (PID: $(cat "$EXPLORER_PID_FILE"))"
    return 0
  fi

  # 清理可能残留的容器
  remove_explorer_container

  log "启动 Explorer 前端 (zkstack explorer run)..."
  cd "$REPO_ROOT"
  nohup zkstack explorer run > "$REPO_ROOT/logs/explorer.log" 2>&1 &
  local pid=$!
  echo "$pid" > "$EXPLORER_PID_FILE"
  log "Explorer 前端已启动 (PID: $pid)"
  sleep 2
  if ! kill -0 "$pid" 2>/dev/null; then
    log "错误: Explorer 前端启动失败，请查看日志: $REPO_ROOT/logs/explorer.log"
    rm -f "$EXPLORER_PID_FILE"
    return 1
  fi
}

# 停止 Explorer 前端
stop_explorer() {
  if ! is_running "$EXPLORER_PID_FILE"; then
    log "Explorer 前端未运行"
  else
    local pid=$(cat "$EXPLORER_PID_FILE")
    log "停止 Explorer 前端 (PID: $pid)..."
    kill "$pid" 2>/dev/null || true
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
      log "强制停止 Explorer 前端..."
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$EXPLORER_PID_FILE"
    log "Explorer 前端进程已停止"
  fi

  # 清理容器
  remove_explorer_container
  log "Explorer 前端已完全停止"
}

# 启动所有服务
start_all() {
  log "========== 启动所有服务 =========="
  start_server
  start_portal
  start_explorer_backend
  sleep 3  # 等待后端服务启动
  start_explorer
  log "========== 所有服务已启动 =========="
  status_all
}

# 停止所有服务
stop_all() {
  log "========== 停止所有服务 =========="
  stop_explorer
  stop_explorer_backend
  stop_portal
  stop_server
  log "========== 所有服务已停止 =========="
}

# 重启所有服务
restart_all() {
  log "========== 重启所有服务 =========="
  stop_all
  sleep 2
  start_all
}

# 查看所有服务状态
status_all() {
  log "========== 服务状态 =========="
  
  if is_running "$SERVER_PID_FILE"; then
    log "✓ L2 服务器: 运行中 (PID: $(cat "$SERVER_PID_FILE"))"
  else
    log "✗ L2 服务器: 未运行"
  fi
  
  if is_running "$PORTAL_PID_FILE"; then
    log "✓ Portal: 运行中 (PID: $(cat "$PORTAL_PID_FILE"))"
  else
    log "✗ Portal: 未运行"
  fi
  
  local explorer_name="${CHAIN_NAME}-explorer"
  if docker ps --format '{{.Names}}' | grep -q "$explorer_name"; then
    log "✓ Explorer 后端: 运行中"
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep "$explorer_name" || true
  else
    log "✗ Explorer 后端: 未运行"
  fi
  
  if is_running "$EXPLORER_PID_FILE"; then
    log "✓ Explorer 前端: 运行中 (PID: $(cat "$EXPLORER_PID_FILE"))"
  else
    log "✗ Explorer 前端: 未运行"
  fi
  
  log "=============================="
  observability_status
}

# 确保日志目录存在
mkdir -p "$REPO_ROOT/logs"

show_usage() {
  cat <<EOF
用法: scripts/l2.sh [选项] [命令]

选项:
  --chain <name>  指定链名称 (默认: zkchain)
                  也可以通过环境变量 CHAIN_NAME 设置

命令:
  start       启动所有服务
  stop        停止所有服务
  restart     重启所有服务
  status      查看所有服务状态
  clean       清理 Explorer 数据（删除并重建 explorer 数据库）
  
  或者单独控制:
  start-server           启动 L2 服务器
  stop-server            停止 L2 服务器
  start-portal           启动 Portal
  stop-portal            停止 Portal
  start-explorer-backend 启动 Explorer 后端
  stop-explorer-backend  停止 Explorer 后端
  start-explorer         启动 Explorer 前端
  stop-explorer          停止 Explorer 前端
  start-observability    启动监控 (era-observability)
  stop-observability     停止监控

服务说明:
  - L2 服务器: zkstack server --chain <chain_name>
  - Portal: zkstack portal
  - Explorer 后端: docker-compose (chains/<chain_name>/configs/explorer-docker-compose.yml)
  - Explorer 前端: zkstack explorer run

当前链名称: $CHAIN_NAME

日志文件:
  - L2 服务器: logs/server.log
  - Portal: logs/portal.log
  - Explorer 前端: logs/explorer.log

示例:
  ./scripts/l2.sh start                    # 使用默认链 zkchain
  ./scripts/l2.sh --chain mychain start    # 使用指定链 mychain
  CHAIN_NAME=mychain ./scripts/l2.sh start # 通过环境变量指定链

EOF
}

# 解析参数（在设置默认值之后）
CMD=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --chain)
      if [[ -z "${2:-}" ]]; then
        log "错误: --chain 需要指定链名称"
        exit 1
      fi
      CHAIN_NAME="$2"
      EXPLORER_COMPOSE_FILE="$REPO_ROOT/chains/$CHAIN_NAME/configs/explorer-docker-compose.yml"
      shift 2
      ;;
    *)
      # 不是选项，作为命令处理
      CMD="$1"
      shift
      break
      ;;
  esac
done

# 如果没有命令，默认为 help
CMD="${CMD:-help}"

# 重新设置 EXPLORER_COMPOSE_FILE（确保使用最新的 CHAIN_NAME）
EXPLORER_COMPOSE_FILE="$REPO_ROOT/chains/$CHAIN_NAME/configs/explorer-docker-compose.yml"

case "$CMD" in
  start)
    start_all
    ;;
  stop)
    stop_all
    ;;
  restart)
    restart_all
    ;;
  status)
    status_all
    ;;
  start-server)
    start_server
    ;;
  stop-server)
    stop_server
    ;;
  start-portal)
    start_portal
    ;;
  stop-portal)
    stop_portal
    ;;
  start-explorer-backend)
    start_explorer_backend
    ;;
  stop-explorer-backend)
    stop_explorer_backend
    ;;
  start-explorer)
    start_explorer
    ;;
  stop-explorer)
    stop_explorer
    ;;
  start-observability)
    start_observability
    ;;
  stop-observability)
    stop_observability
    ;;
  clean)
    clean_explorer_data
    ;;
  help|--help|-h)
    show_usage
    ;;
  *)
    printf '错误: 未知命令: %s\n\n' "$CMD"
    show_usage
    exit 1
    ;;
esac

