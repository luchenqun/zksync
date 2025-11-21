#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD=$1

# 检测 docker-compose 命令
detect_docker_compose() {
  if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD=(docker-compose)
  elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD=(docker compose)
  else
    echo "错误: 无法找到 docker-compose 或 docker compose"
    exit 1
  fi
}

detect_docker_compose

compose() {
  (cd "$SCRIPT_DIR" && "${DOCKER_COMPOSE_CMD[@]}" "$@")
}

case ${CMD} in
start)
    echo "===== start ===="
    compose -f mud.yml down
    compose -f mud.yml up -d
    sleep 3
    echo "===== end ===="
    ;;
stop)
    echo "===== stop ===="
    compose -f mud.yml down
    sleep 3
    echo "===== end ===="
    ;;
reset)
    echo "===== reset ===="
    compose -f mud.yml down
    sleep 3
    cd "$SCRIPT_DIR/services" && rm -rf blockscout-db-data logs redis-data stats-db-data && cd "$SCRIPT_DIR"
    compose -f mud.yml up -d
    sleep 3
    echo "===== end ===="
    ;;
remove)
    echo "===== remove ===="
    cd "$SCRIPT_DIR/services" && rm -rf blockscout-db-data logs redis-data stats-db-data && cd "$SCRIPT_DIR"
    echo "===== end ===="
    ;;
*)
    echo "Usage: deploy.sh start | stop | reset"
    ;;
esac
