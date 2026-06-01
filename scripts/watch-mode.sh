#!/bin/bash
# Watch Mode / 监视模式
# 监听源码变化，自动重新运行性能诊断
# Usage: watch-mode.sh [dir] [--interval SECONDS]
#
# Dependencies: fswatch (macOS) or inotifywait (Linux)
# Fallback: polling with find + md5

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

TARGET_DIR="${1:-.}"
POLL_INTERVAL=5
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
for arg in "$@"; do
  if [[ "$arg" == "--interval" || "$arg" == "-i" ]]; then
    next_arg="${2:-}"
    if [[ "$next_arg" =~ ^[0-9]+$ ]]; then
      POLL_INTERVAL="$next_arg"
    fi
  fi
done

echo ""
echo -e "${CYAN}${BOLD}👁️  Watch Mode / 监视模式${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BLUE}目标目录:${NC} ${BOLD}$(cd "$TARGET_DIR" && pwd)${NC}"
echo -e "  ${BLUE}检查间隔:${NC} ${BOLD}${POLL_INTERVAL}s${NC}"
echo ""

# ── Detect watch tool ─────────────────────
WATCH_TOOL=""
if command -v fswatch &>/dev/null; then
  WATCH_TOOL="fswatch"
elif command -v inotifywait &>/dev/null; then
  WATCH_TOOL="inotifywait"
else
  WATCH_TOOL="polling"
fi

echo -e "  ${BLUE}监视工具:${NC} ${BOLD}$WATCH_TOOL${NC}"
echo ""

# ── State tracking ────────────────────────
LAST_HASH=""
RUN_COUNT=0

get_state_hash() {
  # Hash of all relevant source files
  find "$TARGET_DIR" \
    -type f \
    \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \
       -o -name "*.vue" -o -name "*.svelte" -o -name "*.css" -o -name "*.scss" \
       -o -name "*.html" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    -not -path "*/.next/*" \
    2>/dev/null | sort | xargs stat -f "%m %N" 2>/dev/null | md5 2>/dev/null || \
    find "$TARGET_DIR" \
      -type f \
      \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \
         -o -name "*.vue" -o -name "*.svelte" -o -name "*.css" -o -name "*.scss" \
         -o -name "*.html" -o -name "*.json" \) \
      -not -path "*/node_modules/*" \
      -not -path "*/.git/*" \
      -not -path "*/dist/*" \
      -not -path "*/build/*" \
      2>/dev/null | sort | xargs md5sum 2>/dev/null | md5sum 2>/dev/null | cut -d' ' -f1 || \
    echo "$(date +%s)"
}

run_diagnosis() {
  RUN_COUNT=$((RUN_COUNT + 1))
  echo ""
  echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}${BOLD}  第 ${RUN_COUNT} 次诊断 — $(date '+%Y-%m-%d %H:%M:%S')${NC}"
  echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════${NC}"
  echo ""

  bash "$SCRIPT_DIR/frontend-perf.sh" "$TARGET_DIR" || true

  echo ""
  echo -e "${GREEN}✅ 诊断完成，等待文件变化...${NC}"
  echo -e "${YELLOW}  按 Ctrl+C 退出监视模式${NC}"
  echo ""
}

# ── Initial run ───────────────────────────
echo -e "${CYAN}首次诊断运行中...${NC}"
LAST_HASH=$(get_state_hash)
run_diagnosis

# ── Watch loop ────────────────────────────
cleanup() {
  echo ""
  echo -e "${CYAN}正在退出监视模式...${NC}"
  exit 0
}
trap cleanup INT TERM

if [[ "$WATCH_TOOL" == "fswatch" ]]; then
  # macOS fswatch
  fswatch -r -l "$POLL_INTERVAL" \
    -e ".git" -e "node_modules" -e "dist" -e "build" -e ".next" \
    "$TARGET_DIR" 2>/dev/null | while read -r changed; do
    NEW_HASH=$(get_state_hash)
    if [[ "$NEW_HASH" != "$LAST_HASH" ]]; then
      LAST_HASH="$NEW_HASH"
      run_diagnosis
    fi
  done

elif [[ "$WATCH_TOOL" == "inotifywait" ]]; then
  # Linux inotifywait
  while true; do
    inotifywait -r -q -e modify,create,delete,move \
      --exclude 'node_modules|\.git|dist|build|\.next' \
      "$TARGET_DIR" 2>/dev/null || true

    sleep 0.5
    NEW_HASH=$(get_state_hash)
    if [[ "$NEW_HASH" != "$LAST_HASH" ]]; then
      LAST_HASH="$NEW_HASH"
      run_diagnosis
    fi
  done

else
  # Polling fallback
  echo -e "${YELLOW}⚠️ 未安装 fswatch 或 inotifywait，使用轮询模式${NC}"
  echo -e "  建议安装: ${MAGENTA}brew install fswatch${NC} (macOS)"
  echo -e "            ${MAGENTA}apt-get install inotify-tools${NC} (Linux)"
  echo ""

  while true; do
    sleep "$POLL_INTERVAL"
    NEW_HASH=$(get_state_hash)
    if [[ "$NEW_HASH" != "$LAST_HASH" ]]; then
      LAST_HASH="$NEW_HASH"
      run_diagnosis
    fi
  done
fi
