#!/bin/bash
# Frontend Performance Diagnostic / 前端性能诊断助手
# 主入口脚本 - 执行完整的性能诊断流程
# Usage: frontend-perf [dir] [options]
#
# Options:
#   --fix, -f           诊断 + 生成修复建议
#   --verify, -v        诊断 + 产物验证 + Lighthouse
#   --serve, -s         诊断 + 启动预览服务
#   --json, -j          输出 JSON 报告
#   --watch, -w         监视模式（文件变化自动重新诊断）
#   --monorepo, -m      Monorepo 模式（遍历所有 workspace）
#   --config FILE, -c   指定配置文件（默认: .frontend-perf.yml）
#   --interval SEC      Watch 模式检查间隔（秒，默认: 5）

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
TARGET_DIR="."
FIX_MODE=false
VERIFY_MODE=false
SERVE_MODE=false
JSON_MODE=false
WATCH_MODE=false
MONOREPO_MODE=false
CONFIG_FILE=".frontend-perf.yml"
WATCH_INTERVAL=5

# Parse arguments using getopts-style loop
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix|-f)
      FIX_MODE=true
      shift
      ;;
    --verify|-v)
      VERIFY_MODE=true
      shift
      ;;
    --serve|-s)
      SERVE_MODE=true
      shift
      ;;
    --json|-j)
      JSON_MODE=true
      shift
      ;;
    --watch|-w)
      WATCH_MODE=true
      shift
      ;;
    --monorepo|-m)
      MONOREPO_MODE=true
      shift
      ;;
    --config|-c)
      if [[ $# -gt 1 ]]; then
        CONFIG_FILE="$2"
        shift 2
      else
        echo -e "${RED}错误: --config 需要指定配置文件路径${NC}"
        exit 1
      fi
      ;;
    --interval)
      if [[ $# -gt 1 ]]; then
        WATCH_INTERVAL="$2"
        shift 2
      else
        echo -e "${RED}错误: --interval 需要指定秒数${NC}"
        exit 1
      fi
      ;;
    --help|-h)
      echo "前端性能诊断助手"
      echo ""
      echo "Usage: frontend-perf [dir] [options]"
      echo ""
      echo "Options:"
      echo "  --fix, -f           诊断 + 生成修复建议"
      echo "  --verify, -v        诊断 + 产物验证 + Lighthouse"
      echo "  --serve, -s         诊断 + 启动预览服务"
      echo "  --json, -j          输出 JSON 报告 (frontend-perf-report.json)"
      echo "  --watch, -w         监视模式（文件变化自动重新诊断）"
      echo "  --monorepo, -m      Monorepo 模式（遍历 workspace packages）"
      echo "  --config FILE, -c   指定配置文件（默认: .frontend-perf.yml）"
      echo "  --interval SEC      Watch 模式检查间隔（秒）"
      echo "  --help, -h          显示帮助"
      echo ""
      echo "Examples:"
      echo "  frontend-perf . --fix --verify           # 诊断+修复+验证"
      echo "  frontend-perf . --json                   # 输出 JSON 报告"
      echo "  frontend-perf . --watch --interval 3     # 3秒间隔监视"
      echo "  frontend-perf . --monorepo               # 诊断所有 workspace 包"
      exit 0
      ;;
    -*)
      echo -e "${RED}错误: 未知参数 $1${NC}"
      echo "使用 --help 查看帮助"
      exit 1
      ;;
    *)
      TARGET_DIR="$1"
      shift
      ;;
  esac
done

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve absolute target directory
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
  echo -e "${RED}错误: 目录不存在: $TARGET_DIR${NC}"
  exit 1
}

# ── Load Configuration ───────────────────
load_config() {
  local config_path="$1"
  if [[ -f "$config_path" ]]; then
    echo -e "  ${BLUE}配置加载:${NC} ${BOLD}$config_path${NC}"
    # Source config variables (config-loader outputs variable assignments)
    eval "$(bash "$SCRIPT_DIR/config-loader.sh" "$config_path" 2>/dev/null)" || true
  else
    echo -e "  ${YELLOW}未找到配置文件，使用默认阈值${NC}"
    # Default thresholds
    THRESHOLD_MAX_BUNDLE_SIZE=500000
    THRESHOLD_MAX_IMAGE_SIZE=102400
    THRESHOLD_MAX_VIDEO_SIZE=5242880
    THRESHOLD_MAX_CSS_SIZE=102400
    THRESHOLD_LCP=2500
    THRESHOLD_CLS=0.1
    THRESHOLD_INP=200
    THRESHOLD_TTFB=600
    RULES_IGNORE="node_modules/ dist/ build/ .next/ coverage/ test/ tests/"
  fi

  # Export for child scripts
  export THRESHOLD_MAX_BUNDLE_SIZE
  export THRESHOLD_MAX_IMAGE_SIZE
  export THRESHOLD_MAX_VIDEO_SIZE
  export THRESHOLD_MAX_CSS_SIZE
  export THRESHOLD_LCP
  export THRESHOLD_CLS
  export THRESHOLD_INP
  export THRESHOLD_TTFB
  export RULES_IGNORE
}

# ── Detect Monorepo ──────────────────────
detect_monorepo() {
  local dir="$1"
  cd "$dir"

  # Check for workspace config files
  if [[ -f "pnpm-workspace.yaml" ]]; then
    echo "pnpm"
    return 0
  elif [[ -f "lerna.json" ]]; then
    echo "lerna"
    return 0
  elif [[ -f "package.json" ]]; then
    # Check for workspaces field in package.json
    if node -e "
      const pkg = require('./package.json');
      if (pkg.workspaces) {
        if (Array.isArray(pkg.workspaces)) process.stdout.write(pkg.workspaces.join('\\n'));
        else if (pkg.workspaces.packages) process.stdout.write(pkg.workspaces.packages.join('\\n'));
        else process.exit(1);
      } else {
        process.exit(1);
      }
    " 2>/dev/null; then
      echo "npm"
      return 0
    fi
  fi

  echo "none"
  return 0
}

get_workspace_packages() {
  local dir="$1"
  local type="$2"
  cd "$dir"

  case "$type" in
    pnpm)
      # Parse pnpm-workspace.yaml
      if command -v node &>/dev/null; then
        node -e "
          const fs = require('fs');
          const yaml = fs.readFileSync('pnpm-workspace.yaml', 'utf8');
          const match = yaml.match(/packages:\\s*\\n((?:\\s*-\\s+.*\\n?)*)/);
          if (match) {
            match[1].split('\\n').forEach(line => {
              const m = line.match(/-\\s+(.+)/);
              if (m) console.log(m[1].trim());
            });
          }
        " 2>/dev/null | while read -r pattern; do
          # Expand glob patterns
          for pkg_dir in $pattern; do
            if [[ -d "$pkg_dir" && -f "$pkg_dir/package.json" ]]; then
              echo "$pkg_dir"
            fi
          done
        done
      fi
      ;;
    lerna|npm)
      # Parse package.json workspaces or lerna packages
      node -e "
        const fs = require('fs');
        let patterns = [];
        if (fs.existsSync('lerna.json')) {
          const lerna = JSON.parse(fs.readFileSync('lerna.json', 'utf8'));
          patterns = lerna.packages || ['packages/*'];
        } else {
          const pkg = require('./package.json');
          patterns = Array.isArray(pkg.workspaces) ? pkg.workspaces : (pkg.workspaces?.packages || []);
        }
        patterns.forEach(p => console.log(p));
      " 2>/dev/null | while read -r pattern; do
        for pkg_dir in $pattern; do
          if [[ -d "$pkg_dir" && -f "$pkg_dir/package.json" ]]; then
            echo "$pkg_dir"
          fi
        done
      done
      ;;
  esac
}

# ── Watch Mode ───────────────────────────
if [[ "$WATCH_MODE" == true ]]; then
  bash "$SCRIPT_DIR/watch-mode.sh" "$TARGET_DIR" --interval "$WATCH_INTERVAL"
  exit 0
fi

# ── Monorepo Mode ────────────────────────
if [[ "$MONOREPO_MODE" == true ]]; then
  WS_TYPE=$(detect_monorepo "$TARGET_DIR")

  if [[ "$WS_TYPE" == "none" ]]; then
    echo -e "${YELLOW}未检测到 workspace 配置 (pnpm-workspace.yaml / lerna.json / package.json workspaces)${NC}"
    echo -e "${YELLOW}将以普通模式运行诊断${NC}"
    MONOREPO_MODE=false
  else
    echo -e "  ${GREEN}✅ 检测到 $WS_TYPE workspace${NC}"
    echo ""

    # Collect packages
    PACKAGES=()
    while IFS= read -r pkg; do
      [[ -n "$pkg" ]] && PACKAGES+=("$pkg")
    done < <(get_workspace_packages "$TARGET_DIR" "$WS_TYPE")

    if [[ ${#PACKAGES[@]} -eq 0 ]]; then
      echo -e "${YELLOW}未找到 workspace packages，将以普通模式运行${NC}"
      MONOREPO_MODE=false
    else
      echo -e "  ${BLUE}发现 ${#PACKAGES[@]} 个 workspace packages:${NC}"
      for pkg in "${PACKAGES[@]}"; do
        pkg_name=$(cd "$TARGET_DIR/$pkg" && node -e "console.log(require('./package.json').name || '')" 2>/dev/null || basename "$pkg")
        echo -e "    • ${BOLD}${pkg_name}${NC} ($pkg)"
      done
      echo ""

      # Run diagnosis for each package
      PKG_INDEX=0
      for pkg in "${PACKAGES[@]}"; do
        PKG_INDEX=$((PKG_INDEX + 1))
        PKG_DIR="$TARGET_DIR/$pkg"

        echo ""
        echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}${BOLD}║  Package ${PKG_INDEX}/${#PACKAGES[@]}: ${pkg}"
        echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""

        if [[ ! -d "$PKG_DIR" ]]; then
          echo -e "  ${YELLOW}跳过: 目录不存在 $PKG_DIR${NC}"
          continue
        fi

        # Run diagnosis for this package
        bash "$SCRIPT_DIR/frontend-perf.sh" "$PKG_DIR" \
          $( [[ "$FIX_MODE" == true ]] && echo "--fix" ) \
          $( [[ "$VERIFY_MODE" == true ]] && echo "--verify" ) \
          $( [[ "$SERVE_MODE" == true ]] && echo "--serve" ) \
          $( [[ "$JSON_MODE" == true ]] && echo "--json" ) \
          --config "$CONFIG_FILE" \
          || true
      done

      # Aggregate JSON reports for monorepo
      if [[ "$JSON_MODE" == true ]]; then
        echo -e "${CYAN}${BOLD}正在聚合所有 package 的 JSON 报告...${NC}"
        # Move individual reports to sub-directories
        for pkg in "${PACKAGES[@]}"; do
          pkg_name=$(basename "$pkg")
          if [[ -f "$TARGET_DIR/$pkg/frontend-perf-report.json" ]]; then
            mv "$TARGET_DIR/$pkg/frontend-perf-report.json" "$TARGET_DIR/frontend-perf-report-${pkg_name}.json" 2>/dev/null || true
          fi
        done
      fi

      echo ""
      echo -e "${GREEN}${BOLD}✅ Monorepo 诊断完成，共 ${#PACKAGES[@]} 个 package${NC}"
      exit 0
    fi
  fi
fi

# ── Header ──────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║     🚀 Frontend Performance Diagnostic / 前端性能诊断助手    ║${NC}"
echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BLUE}目标目录:${NC} ${BOLD}$TARGET_DIR${NC}"
echo -e "  ${BLUE}修复模式:${NC} ${BOLD}$([[ "$FIX_MODE" == true ]] && echo -e "${RED}已启用${NC}" || echo -e "${GREEN}未启用${NC}")${NC}"
echo -e "  ${BLUE}验证模式:${NC} ${BOLD}$([[ "$VERIFY_MODE" == true ]] && echo -e "${YELLOW}已启用${NC}" || echo -e "${GREEN}未启用${NC}")${NC}"
echo -e "  ${BLUE}预览服务:${NC} ${BOLD}$([[ "$SERVE_MODE" == true ]] && echo -e "${YELLOW}已启用${NC}" || echo -e "${GREEN}未启用${NC}")${NC}"
echo -e "  ${BLUE}JSON 报告:${NC} ${BOLD}$([[ "$JSON_MODE" == true ]] && echo -e "${YELLOW}已启用${NC}" || echo -e "${GREEN}未启用${NC}")${NC}"
echo ""

# ── Load config ──────────────────────────
CONFIG_PATH="$TARGET_DIR/$CONFIG_FILE"
if [[ ! -f "$CONFIG_PATH" ]]; then
  # Try root of skill repo for fallback
  CONFIG_PATH="$CONFIG_FILE"
fi
load_config "$CONFIG_PATH"
echo ""

# ── Pre-checks ──────────────────────────
cd "$TARGET_DIR"

# Check if it's a frontend project
FRONTEND_SIGS=("package.json" "vite.config" "next.config" "webpack.config" "nuxt.config" "angular.json" "svelte.config" "astro.config" "remix.config")
IS_FRONTEND=false
for sig in "${FRONTEND_SIGS[@]}"; do
  if ls ./${sig}* 1>/dev/null 2>&1; then
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
FRAMEWORK=""
[[ -f "next.config.js" || -f "next.config.ts" || -f "next.config.mjs" ]] && FRAMEWORK="Next.js"
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

# Show threshold values used
if [[ -n "${THRESHOLD_MAX_BUNDLE_SIZE:-}" ]]; then
  echo ""
  echo -e "  ${BLUE}配置阈值:${NC}"
  echo -e "    Max Bundle: ${BOLD}$(echo "scale=1; $THRESHOLD_MAX_BUNDLE_SIZE/1024" | bc 2>/dev/null || echo "?")KB${NC}"
  echo -e "    Max Image:  ${BOLD}$(echo "scale=1; $THRESHOLD_MAX_IMAGE_SIZE/1024" | bc 2>/dev/null || echo "?")KB${NC}"
  echo -e "    LCP:        ${BOLD}${THRESHOLD_LCP}ms${NC}"
  echo -e "    CLS:        ${BOLD}${THRESHOLD_CLS}${NC}"
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

# ── Post-Diagnosis Verification ──────────
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

# ── Preview Server ───────────────────────
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

# ── JSON Report ──────────────────────────
if [[ "$JSON_MODE" == true ]]; then
  echo ""
  echo -e "${CYAN}${BOLD}▶▶▶ 生成 JSON 报告 ◀◀◀${NC}"
  echo -e "${BLUE}────────────────────────────────────────${NC}"
  echo ""

  if [[ -f "$SCRIPT_DIR/json-aggregator.sh" ]]; then
    bash "$SCRIPT_DIR/json-aggregator.sh" "$TARGET_DIR" "frontend-perf-report.json" || {
      echo -e "  ${YELLOW}JSON 报告生成失败${NC}"
    }
  else
    echo -e "  ${YELLOW}JSON 聚合器脚本未找到${NC}"
  fi
  echo ""
fi
