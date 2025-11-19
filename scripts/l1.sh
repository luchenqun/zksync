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

stop_stack() {
  log '停止 docker-compose 服务'
  compose down
}

start_stack() {
  log '启动 docker-compose 服务'
  compose up -d
}

remove_volumes() {
  log '当前卷列表：'
  docker volume ls | grep zksync || true

  log '删除旧卷（如不存在将忽略错误）'
  docker volume rm -f "${VOLUMES[@]}" || true
}

reset_stack() {
  stop_stack
  remove_volumes
  start_stack
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
  log '初始化生态系统 (zkstack ecosystem init --dev --verbose)'
  log "日志将保存到: $INIT_LOG_FILE"
  cd "$REPO_ROOT"
  zkstack ecosystem init --dev --verbose 2>&1 | tee "$INIT_LOG_FILE"
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

