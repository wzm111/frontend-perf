#!/bin/bash
# Frontend Performance Diagnostic / 前端性能诊断助手
# 主入口脚本 - 执行完整的性能诊断流程
# Usage: frontend-perf [dir] [--fix]

set -euo pipefail

# ── Colors ──────────────────────────────
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# ── Arguments ───────────────────────────
TARGET_DIR="${1:-.}"
FIX_MODE=false
VERIFY_MODE=false
SERVE_MODE=false

# Parse arguments
for arg in "$@"; do
  if [[ "$arg" == "--fix" || "$arg" == "-f" ]]; then
    FIX_MODE=true
  elif [[ "$arg" == "--verify" || "$arg" == "-v" ]]; then
    VERIFY_MODE=true
  elif [[ "$arg" == "--serve" || "$arg" == "-s" ]]; then
    SERVE_MODE=true
  fi
done

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Header ──────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║     🚀 Frontend Performance Diagnostic / 前端性能诊断助手    ║${NC}"
echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BLUE}目标目录:${NC} ${BOLD}$(cd "$TARGET_DIR" && pwd)${NC}"
echo -e "  ${BLUE}修复模式:${NC} ${BOLD}$([[ "$FIX_MODE" == true ]] && echo -e "${RED}已启用${NC}" || echo -e "${GREEN}未启用${NC}")${NC}"
echo -e "  ${BLUE}验证模式:${NC} ${BOLD}$([[ "$VERIFY_MODE" == true ]] && echo -e "${YELLOW}已启用${NC}" || echo -e "${GREEN}未启用${NC}")${NC}"
echo -e "  ${BLUE}预览服务:${NC} ${BOLD}$([[ "$SERVE_MODE" == true ]] && echo -e "${YELLOW}已启用${NC}" || echo -e "${GREEN}未启用${NC}")${NC}"
echo ""

# ── Pre-checks ──────────────────────────
if [[ ! -d "$TARGET_DIR" ]]; then
  echo -e "${RED}错误: 目录不存在: $TARGET_DIR${NC}"
  exit 1
fi

# Check if it's a frontend project
FRONTEND_SIGS=("package.json" "vite.config" "next.config" "webpack.config" "nuxt.config" "angular.json" "svelte.config" "astro.config" "remix.config")
IS_FRONTEND=false
for sig in "${FRONTEND_SIGS[@]}"; do
  if ls "$TARGET_DIR"/${sig}* 1>/dev/null 2>&1; then
    IS_FRONTEND=true
    break
  fi
done

if [[ "$IS_FRONTEND" == false ]]; then
  echo -e "${YELLOW}⚠️  未检测到前端项目特征 (package.json / vite.config / next.config 等)${NC}"
  echo -e "   继续执行通用检查..."
  echo ""
fi

# ── Run Diagnostics ─────────────────────
TOTAL_ISSUES=0

run_check() {
  local script="$1"
  local name="$2"
  local color="$3"

  echo ""
  echo -e "${color}${BOLD}▶▶▶ $name ◀◀◀${NC}"
  echo -e "${BLUE}────────────────────────────────────────${NC}"

  if [[ -x "$script" ]]; then
    "$script" "$TARGET_DIR" || true
  elif [[ -f "$script" ]]; then
    bash "$script" "$TARGET_DIR" || true
  else
    echo -e "  ${YELLOW}脚本未找到: $script${NC}"
  fi
}

# 1. Core Web Vitals
run_check "$SCRIPT_DIR/core-web-vitals.sh" "Core Web Vitals 诊断" "$CYAN"

# 2. Bundle Analysis
run_check "$SCRIPT_DIR/bundle-analyzer.sh" "Bundle 分析" "$MAGENTA"

# 3. Code Splitting
run_check "$SCRIPT_DIR/code-splitting.sh" "代码分割检查" "$YELLOW"

# 4. Duplicate Dependencies
run_check "$SCRIPT_DIR/duplicate-deps.sh" "重复依赖检测" "$BLUE"

# 5. Resource Optimization
run_check "$SCRIPT_DIR/resource-optimizer.sh" "资源优化" "$GREEN"

# ── Summary ─────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║                      📊 诊断总结                            ║${NC}"
echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Framework summary
cd "$TARGET_DIR"
FRAMEWORK=""
[[ -f "next.config.js" || -f "next.config.ts" ]] && FRAMEWORK="Next.js"
[[ -f "vite.config.ts" || -f "vite.config.js" ]] && FRAMEWORK="Vite + ${FRAMEWORK}"
[[ -f "nuxt.config.ts" || -f "nuxt.config.js" ]] && FRAMEWORK="Nuxt"
[[ -f "angular.json" ]] && FRAMEWORK="Angular"
[[ -f "svelte.config.js" ]] && FRAMEWORK="SvelteKit"
[[ -f "astro.config.mjs" ]] && FRAMEWORK="Astro"

if [[ -n "$FRAMEWORK" ]]; then
  echo -e "  ${BLUE}检测框架:${NC} ${BOLD}$FRAMEWORK${NC}"
fi

# Build tool
BUILD_TOOL=""
[[ -f "vite.config.ts" || -f "vite.config.js" ]] && BUILD_TOOL="Vite"
[[ -f "webpack.config.js" || -f "webpack.config.ts" ]] && BUILD_TOOL="Webpack"
[[ -f "rollup.config.js" ]] && BUILD_TOOL="Rollup"

if [[ -n "$BUILD_TOOL" ]]; then
  echo -e "  ${BLUE}构建工具:${NC} ${BOLD}$BUILD_TOOL${NC}"
fi

# Package manager
if [[ -f "pnpm-lock.yaml" ]]; then
  echo -e "  ${BLUE}包管理器:${NC} ${BOLD}pnpm${NC}"
elif [[ -f "yarn.lock" ]]; then
  echo -e "  ${BLUE}包管理器:${NC} ${BOLD}Yarn${NC}"
elif [[ -f "package-lock.json" ]]; then
  echo -e "  ${BLUE}包管理器:${NC} ${BOLD}npm${NC}"
fi

echo ""

# Quick fixes summary (always show)
echo -e "  ${CYAN}${BOLD}🔧 常用修复命令:${NC}"
echo ""
echo -e "  1. 替换 moment → dayjs:"
echo -e "     ${MAGENTA}npm uninstall moment && npm install dayjs${NC}"
echo ""
echo -e "  2. 替换 lodash → lodash-es:"
echo -e "     ${MAGENTA}npm uninstall lodash && npm install lodash-es${NC}"
echo ""
echo -e "  3. 安装 Bundle 分析器:"
if [[ -f "next.config.js" || -f "next.config.ts" ]]; then
  echo -e "     ${MAGENTA}npm install -D @next/bundle-analyzer${NC}"
elif [[ -f "vite.config.ts" || -f "vite.config.js" ]]; then
  echo -e "     ${MAGENTA}npm install -D rollup-plugin-visualizer${NC}"
elif [[ -f "webpack.config.js" ]]; then
  echo -e "     ${MAGENTA}npm install -D webpack-bundle-analyzer${NC}"
fi
echo ""

# Fix mode instructions
if [[ "$FIX_MODE" == true ]]; then
  echo -e "  ${RED}${BOLD}⚠️ 自动修复模式已启用${NC}"
  echo -e "  ${YELLOW}当前版本仅生成修复建议，请手动应用。${NC}"
  echo -e "  ${YELLOW}未来版本将支持自动应用补丁。${NC}"
  echo ""
fi

echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║              诊断完成 ✓ 查看上方详细结果                     ║${NC}"
echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Post-Diagnosis Verification / 诊断后验证 ──────────────
if [[ "$VERIFY_MODE" == true ]]; then
  echo ""
  echo -e "${CYAN}${BOLD}▶▶▶ 启动诊断后验证 ◀◀◀${NC}"
  echo -e "${BLUE}────────────────────────────────────────${NC}"
  echo ""

  if [[ -f "$SCRIPT_DIR/post-verify.sh" ]]; then
    bash "$SCRIPT_DIR/post-verify.sh" "$TARGET_DIR" --lighthouse || true
  else
    echo -e "  ${YELLOW}验证脚本未找到${NC}"
  fi
else
  echo ""
  echo -e "  ${CYAN}提示:${NC} 添加 ${MAGENTA}--verify${NC} 参数可执行诊断后验证"
  echo -e "       示例: ${MAGENTA}bash scripts/frontend-perf.sh . --verify${NC}"
  echo ""
fi

# ── Preview Server / 本地预览服务 ────────────────────────
if [[ "$SERVE_MODE" == true ]]; then
  echo ""
  echo -e "${CYAN}${BOLD}▶▶▶ 启动本地预览服务 ◀◀◀${NC}"
  echo -e "${BLUE}────────────────────────────────────────${NC}"
  echo ""

  if [[ -f "$SCRIPT_DIR/preview-server.sh" ]]; then
    bash "$SCRIPT_DIR/preview-server.sh" "$TARGET_DIR" --lighthouse || true
  else
    echo -e "  ${YELLOW}预览服务脚本未找到${NC}"
  fi
else
  echo -e "  ${CYAN}提示:${NC} 添加 ${MAGENTA}--serve${NC} 参数可启动预览服务"
  echo -e "       示例: ${MAGENTA}bash scripts/frontend-perf.sh . --serve${NC}"
  echo ""
fi
