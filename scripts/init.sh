#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARENT_DIR="$(cd "$REPO_ROOT/.." && pwd)"
ZKSYNC_ERA_DIR="$PARENT_DIR/zksync-era"
TARGET_FILE="$ZKSYNC_ERA_DIR/etc/env/file_based/genesis.yaml"

REPLACEMENTS=(
  "0x010005f73e7c299ed73db937843643bdc276cbc2cc8596287e1e0cf3afc60252=>0x010005f7f5052fbdb6a0f6f70b12ad8865b1617a6a5698c20ef34132ea0ff0e2"
  "0x934d46a331e4c617767cade322bc4d262899c0dc5568d2019d4e11301c0cc032=>0x0224369ff870c1f27831063206eb30bcc33d802563bc4fe394c31f9577f2c5a9"
  "0x4df2f475a7b24cf76a9bafca7b39a081028537c6f01993ceb5cf394eda16cca1=>0x6d6b2b0cbb8e8348ad40225efff43f0690118ba8445fab10563763e1a41b5cf0"
)

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

show_usage() {
  cat <<EOF
用法: $0 [选项]

选项:
  --replace-hashes    执行哈希替换（默认：不执行）
  -h, --help          显示此帮助信息

功能:
  1. 检查上一级目录是否存在 zksync-era
  2. 如果不存在，克隆 zksync-era 仓库并初始化子模块
  3. 如果指定了 --replace-hashes，执行哈希替换

EOF
}

detect_sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    SED_INPLACE=(-i)
  else
    SED_INPLACE=(-i '')
  fi
}

clone_zksync_era() {
  if [[ -d "$ZKSYNC_ERA_DIR" ]]; then
    log "zksync-era 目录已存在: $ZKSYNC_ERA_DIR"
    return 0
  fi

  log "上一级目录不存在 zksync-era，开始克隆..."
  log "目标目录: $ZKSYNC_ERA_DIR"

  cd "$PARENT_DIR"
  git clone git@github.com:matter-labs/zksync-era.git

  log "进入 zksync-era 目录并初始化子模块..."
  cd zksync-era
  git submodule update --init --recursive

  log "zksync-era 克隆和子模块初始化完成"
}

process_file() {
  local file="$1"
  local pair old new before after pattern=""
  for pair in "${REPLACEMENTS[@]}"; do
    old="${pair%%=>*}"
    pattern+="${old}|"
  done
  pattern="${pattern%|}"

  if ! LC_ALL=C grep -qE "$pattern" "$file"; then
    return 1
  fi

  before=$(shasum "$file" | cut -d' ' -f1)
  for pair in "${REPLACEMENTS[@]}"; do
    old="${pair%%=>*}"
    new="${pair##*=>}"
    sed "${SED_INPLACE[@]}" "s/$old/$new/g" "$file"
  done
  after=$(shasum "$file" | cut -d' ' -f1)

  [[ "$before" != "$after" ]]
}

main() {
  local replace_hashes=false

  # 从 npm_config 环境变量读取参数（支持 npm run init --replace-hashes）
  [[ -n "${npm_config_replace_hashes:-}" ]] && replace_hashes=true

  # 解析参数
  while [[ $# -gt 0 ]]; do
    case $1 in
      --replace-hashes)
        replace_hashes=true
        shift
        ;;
      -h|--help)
        show_usage
        exit 0
        ;;
      *)
        log "错误: 未知参数: $1"
        show_usage
        exit 1
        ;;
    esac
  done

  # 检查并克隆 zksync-era
  clone_zksync_era

  # 如果指定了 --replace-hashes，执行哈希替换
  if [[ "$replace_hashes" == "true" ]]; then
    if [[ ! -f "$TARGET_FILE" ]]; then
      log "错误: 文件不存在 $TARGET_FILE"
      exit 1
    fi

    if process_file "$TARGET_FILE"; then
      log "已更新: ${TARGET_FILE#$PARENT_DIR/}"
      log "完成替换"
    else
      log "文件中未检测到需要替换的内容"
    fi
  else
    log "跳过哈希替换（使用 --replace-hashes 参数来执行替换）"
  fi
}

main "$@"

