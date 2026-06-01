#!/bin/bash
# Bundle 分析与依赖优化诊断
# 检测大体积依赖、import 方式、构建配置

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

TARGET_DIR="${1:-.}"
ISSUES_COUNT=0

cd "$TARGET_DIR"

echo -e "${CYAN}${BOLD}📦 Bundle 分析与依赖优化诊断${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ──────────────────────────────────────────
# Known heavy packages and alternatives
# ──────────────────────────────────────────
declare -A HEAVY_PACKAGES
declare -A PACKAGE_ALTERNATIVES
declare -A PACKAGE_SAVINGS

HEAVY_PACKAGES=(
  ["lodash"]="lodash"
  ["moment"]="moment"
  ["jquery"]="jquery"
  ["@material-ui/core"]="@material-ui"
  ["echarts"]="echarts"
  ["antd"]="antd"
  ["three"]="three"
  ["axios"]="axios"
  ["uuid"]="uuid"
  ["core-js"]="core-js"
  ["highlight.js"]="highlight.js"
  ["@fortawesome/fontawesome-free"]="fontawesome-free"
  ["chart.js"]="chart.js"
  ["jsdom"]="jsdom"
  ["@sentry/browser"]="@sentry"
  ["styled-components"]="styled-components"
  ["@emotion/styled"]="@emotion"
  ["date-fns"]="date-fns"
)

PACKAGE_ALTERNATIVES=(
  ["lodash"]="lodash-es / es-toolkit / radash"
  ["moment"]="dayjs / date-fns"
  ["jquery"]="Vanilla JS"
  ["@material-ui/core"]="@mui/material (v5+)"
  ["echarts"]="echarts/core + tree-shaken modules"
  ["antd"]="antd + babel-plugin-import / unplugin"
  ["three"]="Tree-shaken three imports"
  ["axios"]="Native fetch / ky"
  ["uuid"]="crypto.randomUUID()"
  ["core-js"]="core-js-pure + needed polyfills only"
  ["highlight.js"]="highlight.js/lib/core + langs"
  ["@fortawesome/fontawesome-free"]="@fortawesome/react-fontawesome + individual icons"
  ["chart.js"]="Tree-shaken chart.js/auto"
  ["jsdom"]="Remove from browser bundle (server-only)"
  ["@sentry/browser"]="@sentry/react with tree-shaking"
  ["styled-components"]="styled-components + babel-plugin / Linaria"
  ["@emotion/styled"]="@emotion/babel-plugin for CSS extraction"
  ["date-fns"]="date-fns/esm + named imports only"
)

PACKAGE_SAVINGS=(
  ["lodash"]="~65KB"
  ["moment"]="~230KB"
  ["jquery"]="~85KB"
  ["@material-ui/core"]="~30KB"
  ["echarts"]="~200KB"
  ["antd"]="varies"
  ["three"]="varies"
  ["axios"]="~13KB"
  ["uuid"]="~12KB"
  ["core-js"]="varies"
  ["highlight.js"]="~100KB"
  ["@fortawesome/fontawesome-free"]="~50KB"
  ["chart.js"]="~50KB"
  ["jsdom"]="~200KB"
  ["@sentry/browser"]="~20KB"
  ["styled-components"]="~10KB"
  ["@emotion/styled"]="~5KB"
  ["date-fns"]="~40KB"
)

# ──────────────────────────────────────────
# 1. Check package.json dependencies
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ 依赖包体积分析${NC}"

if [[ ! -f "package.json" ]]; then
  echo -e "  ${YELLOW}未找到 package.json${NC}"
  exit 0
fi

# Extract dependency names
deps=$(cat package.json | grep -E '"dependencies"' -A 200 | sed -n '/dependencies/,/^[[:space:]]*}/p' | grep -oE '"[^"]+"\s*:' | sed 's/"//g; s/://g; s/ //g' | grep -vE 'dependencies|devDependencies|peerDependencies|optionalDependencies|scripts|name|version|private|type|main|module' || true)
dev_deps=$(cat package.json | grep -E '"devDependencies"' -A 200 | sed -n '/devDependencies/,/^[[:space:]]*}/p' | grep -oE '"[^"]+"\s*:' | sed 's/"//g; s/://g; s/ //g' | grep -vE 'dependencies|devDependencies|peerDependencies|optionalDependencies|scripts|name|version|private|type|main|module' || true)

FOUND_HEAVY=0
for pkg in "${!HEAVY_PACKAGES[@]}"; do
  pkg_pattern="${HEAVY_PACKAGES[$pkg]}"
  if echo "$deps" | grep -qx "$pkg" 2>/dev/null || echo "$dev_deps" | grep -qx "$pkg" 2>/dev/null; then
    FOUND_HEAVY=1
    alt="${PACKAGE_ALTERNATIVES[$pkg]}"
    saving="${PACKAGE_SAVINGS[$pkg]}"

    if [[ "$pkg" == "lodash" || "$pkg" == "moment" || "$pkg" == "jquery" || "$pkg" == "jsdom" ]]; then
      echo -e "  ${RED}🔴 [Bundle]${NC} ${BOLD}$pkg${NC} 已安装"
      echo -e "     建议替换: ${GREEN}$alt${NC} (节省 $saving)"
    else
      echo -e "  ${YELLOW}🟡 [Bundle]${NC} ${BOLD}$pkg${NC} 已安装"
      echo -e "     优化建议: ${GREEN}$alt${NC} (节省 $saving)"
    fi
    ISSUES_COUNT=$((ISSUES_COUNT + 1))
  fi
done

if [[ "$FOUND_HEAVY" -eq 0 ]]; then
  echo -e "  ${GREEN}✅ 未检测到已知大体积依赖${NC}"
fi

echo ""

# ──────────────────────────────────────────
# 2. Check import patterns in source code
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ Import 模式检查${NC}"

# Full lodash import
find . -type f \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \) \
  -not -path "*/node_modules/*" 2>/dev/null | while read -r file; do

  # Check for "import _ from 'lodash'" or "import lodash from 'lodash'"
  grep -nE "import\s+_\s+from\s+['\"]lodash['\"]|import\s+lodash\s+from\s+['\"]lodash['\"]" "$file" 2>/dev/null | while read -r line; do
    lineno=$(echo "$line" | cut -d':' -f1)
    echo -e "  ${RED}🔴 [Bundle]${NC} $file:$lineno 全量导入 lodash"
    echo -e "     修复: 改为按需导入 ${GREEN}import { debounce } from 'lodash-es'${NC}"
    echo -e "     或: ${GREEN}import debounce from 'lodash/debounce'${NC}"
    ISSUES_COUNT=$((ISSUES_COUNT + 1))
  done

  # Check for "import moment from 'moment'"
  grep -nE "import\s+moment\s+from\s+['\"]moment['\"]|import\s+\*\s+as\s+moment\s+from\s+['\"]moment['\"]" "$file" 2>/dev/null | while read -r line; do
    lineno=$(echo "$line" | cut -d':' -f1)
    echo -e "  ${RED}🔴 [Bundle]${NC} $file:$lineno 使用 moment (已废弃且体积大)"
    echo -e "     修复: 替换为 ${GREEN}import dayjs from 'dayjs'${NC} (API 兼容)"
    ISSUES_COUNT=$((ISSUES_COUNT + 1))
  done

  # Check for "import * as _ from 'lodash'"
  grep -nE "import\s+\*\s+as\s+_\s+from\s+['\"]lodash['\"]" "$file" 2>/dev/null | while read -r line; do
    lineno=$(echo "$line" | cut -d':' -f1)
    echo -e "  ${RED}🔴 [Bundle]${NC} $file:$lineno 命名空间导入 lodash"
    echo -e "     修复: 改为按需导入"
    ISSUES_COUNT=$((ISSUES_COUNT + 1))
  done

  # Check for jQuery import
  grep -nE "import\s+\$\s+from\s+['\"]jquery['\"]|import\s+jQuery\s+from\s+['\"]jquery['\"]" "$file" 2>/dev/null | while read -r line; do
    lineno=$(echo "$line" | cut -d':' -f1)
    echo -e "  ${YELLOW}🟡 [Bundle]${NC} $file:$lineno 使用 jQuery"
    echo -e "     建议: 考虑使用原生 DOM API 或现代框架替代"
    ISSUES_COUNT=$((ISSUES_COUNT + 1))
  done

  # Check for full echarts import
  grep -nE "import\s+\*\s+as\s+echarts\s+from\s+['\"]echarts['\"]|import\s+echarts\s+from\s+['\"]echarts['\"]" "$file" 2>/dev/null | while read -r line; do
    lineno=$(echo "$line" | cut -d':' -f1)
    echo -e "  ${YELLOW}🟡 [Bundle]${NC} $file:$lineno 全量导入 echarts"
    echo -e "     修复: ${GREEN}import * as echarts from 'echarts/core'${NC} + 按需注册组件"
    ISSUES_COUNT=$((ISSUES_COUNT + 1))
  done

done

echo ""

# ──────────────────────────────────────────
# 3. Build config checks
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ 构建配置检查${NC}"

# Vite config
if [[ -f "vite.config.ts" || -f "vite.config.js" || -f "vite.config.mjs" ]]; then
  VITE_FILE=$(ls vite.config.* 2>/dev/null | head -1)
  VITE_CONFIG=$(cat "$VITE_FILE" 2>/dev/null || true)

  echo -e "  ${CYAN}Vite 配置 ($VITE_FILE):${NC}"

  if echo "$VITE_CONFIG" | grep -q 'manualChunks'; then
    echo -e "    ${GREEN}✅ 已配置 manualChunks${NC}"
  else
    echo -e "    ${YELLOW}🟡 未配置 manualChunks，建议添加代码分割${NC}"
  fi

  if echo "$VITE_CONFIG" | grep -q 'minify'; then
    echo -e "    ${GREEN}✅ 已配置 minify${NC}"
  else
    echo -e "    ${YELLOW}🟡 未显式配置 minify${NC}"
  fi

  if echo "$VITE_CONFIG" | grep -q 'build.rollupOptions'; then
    echo -e "    ${GREEN}✅ 已配置 rollupOptions${NC}"
  fi
fi

# Next.js config
if [[ -f "next.config.js" || -f "next.config.ts" || -f "next.config.mjs" ]]; then
  NEXT_FILE=$(ls next.config.* 2>/dev/null | head -1)
  NEXT_CONFIG=$(cat "$NEXT_FILE" 2>/dev/null || true)

  echo -e "  ${CYAN}Next.js 配置 ($NEXT_FILE):${NC}"

  if echo "$NEXT_CONFIG" | grep -q 'optimizePackageImports'; then
    echo -e "    ${GREEN}✅ 已配置 optimizePackageImports${NC}"
  else
    echo -e "    ${YELLOW}🟡 未配置 optimizePackageImports (Next.js 13.5+ 特性)${NC}"
  fi

  if echo "$NEXT_CONFIG" | grep -q 'experimental.*reactCompiler\|reactCompiler'; then
    echo -e "    ${GREEN}✅ 已启用 React Compiler${NC}"
  else
    echo -e "    ${YELLOW}🟡 未启用 React Compiler (Next.js 15+ 实验性特性)${NC}"
  fi

  if echo "$NEXT_CONFIG" | grep -q '@next/bundle-analyzer'; then
    echo -e "    ${GREEN}✅ 已配置 Bundle Analyzer${NC}"
  else
    echo -e "    ${YELLOW}🟡 建议安装 @next/bundle-analyzer 分析构建产物${NC}"
  fi
fi

# Webpack config
if [[ -f "webpack.config.js" || -f "webpack.config.ts" ]]; then
  WP_FILE=$(ls webpack.config.* 2>/dev/null | head -1)
  WP_CONFIG=$(cat "$WP_FILE" 2>/dev/null || true)

  echo -e "  ${CYAN}Webpack 配置 ($WP_FILE):${NC}"

  if echo "$WP_CONFIG" | grep -q 'splitChunks'; then
    echo -e "    ${GREEN}✅ 已配置 splitChunks${NC}"
  else
    echo -e "    ${YELLOW}🟡 未配置 splitChunks${NC}"
  fi

  if echo "$WP_CONFIG" | grep -q 'BundleAnalyzerPlugin'; then
    echo -e "    ${GREEN}✅ 已配置 BundleAnalyzerPlugin${NC}"
  else
    echo -e "    ${YELLOW}🟡 建议安装 webpack-bundle-analyzer${NC}"
  fi
fi

# Check for bundle analyzer in devDependencies
if echo "$dev_deps" | grep -qE 'bundle-analyzer|rollup-plugin-visualizer'; then
  echo -e "  ${GREEN}✅ 已安装 Bundle 分析工具${NC}"
else
  echo -e "  ${YELLOW}🟡 未安装 Bundle 分析工具${NC}"
  echo -e "     建议安装: ${MAGENTA}webpack-bundle-analyzer${NC} (Webpack) 或 ${MAGENTA}rollup-plugin-visualizer${NC} (Vite/Rollup)"
fi

echo ""

# ──────────────────────────────────────────
# 4. Build artifact size check
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ 构建产物体积检查${NC}"

BUILD_DIRS=("dist" "build" ".next" "out" ".output")
FOUND_BUILD=""

for dir in "${BUILD_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    FOUND_BUILD="$dir"
    break
  fi
done

if [[ -n "$FOUND_BUILD" ]]; then
  total_size=$(du -sh "$FOUND_BUILD" 2>/dev/null | cut -f1)
  echo -e "  产物目录: ${BOLD}$FOUND_BUILD${NC}"
  echo -e "  总体积: ${BOLD}$total_size${NC}"
  echo ""
  echo "  最大文件 TOP 10:"
  find "$FOUND_BUILD" -type f -exec du -h {} + 2>/dev/null | sort -rh | head -10 | sed 's/^/    /'

  # Check for large JS files (> 500KB unminified roughly translates to > 150KB gzipped)
  large_js=$(find "$FOUND_BUILD" -name "*.js" -size +500k 2>/dev/null || true)
  if [[ -n "$large_js" ]]; then
    echo ""
    echo -e "  ${RED}🔴 以下 JS 文件体积过大 (>500KB):${NC}"
    echo "$large_js" | while read -r f; do
      size=$(du -h "$f" 2>/dev/null | cut -f1)
      echo -e "    ${RED}${size}${NC}  ${f}"
    done
  fi

  # Check for large CSS files
  large_css=$(find "$FOUND_BUILD" -name "*.css" -size +100k 2>/dev/null || true)
  if [[ -n "$large_css" ]]; then
    echo ""
    echo -e "  ${YELLOW}🟡 以下 CSS 文件体积较大 (>100KB):${NC}"
    echo "$large_css" | while read -r f; do
      size=$(du -h "$f" 2>/dev/null | cut -f1)
      echo "    ${size}  ${f}"
    done
  fi
else
  echo -e "  ${YELLOW}未找到构建产物目录 (dist/build/.next/out/.output)${NC}"
  echo -e "  请先运行构建命令再分析"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Bundle 分析完成，发现问题: ${BOLD}${ISSUES_COUNT}${NC}"
