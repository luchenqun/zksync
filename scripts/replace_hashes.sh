#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_FILE="$REPO_ROOT/zksync-era/etc/env/file_based/genesis.yaml"

REPLACEMENTS=(
  "0x010005f73e7c299ed73db937843643bdc276cbc2cc8596287e1e0cf3afc60252=>0x010005f7f5052fbdb6a0f6f70b12ad8865b1617a6a5698c20ef34132ea0ff0e2"
  "0x934d46a331e4c617767cade322bc4d262899c0dc5568d2019d4e11301c0cc032=>0x0224369ff870c1f27831063206eb30bcc33d802563bc4fe394c31f9577f2c5a9"
  "0x4df2f475a7b24cf76a9bafca7b39a081028537c6f01993ceb5cf394eda16cca1=>0x6d6b2b0cbb8e8348ad40225efff43f0690118ba8445fab10563763e1a41b5cf0"
)

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

detect_sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    SED_INPLACE=(-i)
  else
    SED_INPLACE=(-i '')
  fi
}

detect_sed_inplace

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
  if [[ ! -f "$TARGET_FILE" ]]; then
    log "错误: 文件不存在 $TARGET_FILE"
    exit 1
  fi

  if process_file "$TARGET_FILE"; then
    log "已更新: ${TARGET_FILE#$REPO_ROOT/}"
    log "完成替换"
  else
    log "文件中未检测到需要替换的内容"
  fi
}

main "$@"

