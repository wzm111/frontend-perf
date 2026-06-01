#!/bin/bash
# 代码分割检查脚本
# 检测路由懒加载、组件动态导入、构建配置

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

echo -e "${CYAN}${BOLD}⚡ 代码分割检查${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ──────────────────────────────────────────
# Detect framework
# ──────────────────────────────────────────
FRAMEWORK="Unknown"
[[ -f "next.config.js" || -f "next.config.ts" ]] && FRAMEWORK="Next.js"
[[ -f "nuxt.config.ts" || -f "nuxt.config.js" ]] && FRAMEWORK="Nuxt"
[[ -f "vite.config.ts" || -f "vite.config.js" ]] && FRAMEWORK="React/Vue (Vite)"
[[ -f "angular.json" ]] && FRAMEWORK="Angular"
[[ -f "astro.config.mjs" ]] && FRAMEWORK="Astro"
[[ -f "remix.config.js" || -f "remix.config.ts" ]] && FRAMEWORK="Remix"

echo -e "${CYAN}【框架检测】${NC} ${BOLD}$FRAMEWORK${NC}"
echo ""

# ──────────────────────────────────────────
# 1. Router-level lazy loading check
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ 路由级别懒加载检查${NC}"

# React Router / Vite / General
REACT_ROUTER_FILES=$(find . -type f \( -name "*.tsx" -o -name "*.jsx" -o -name "*.ts" -o -name "*.js" \) \
  -not -path "*/node_modules/*" 2>/dev/null | xargs grep -l 'createBrowserRouter\|BrowserRouter\|Routes\|Route' 2>/dev/null || true)

if [[ -n "$REACT_ROUTER_FILES" ]]; then
  echo -e "  ${CYAN}React Router 路由文件:${NC}"
  echo "$REACT_ROUTER_FILES" | while read -r file; do
    echo "    - $file"
  done

  # Check for lazy imports in router files
  HAS_LAZY=$(echo "$REACT_ROUTER_FILES" | xargs grep -l 'React.lazy\|lazy(' 2>/dev/null || true)
  if [[ -n "$HAS_LAZY" ]]; then
    echo -e "  ${GREEN}✅ 检测到 React.lazy 动态导入${NC}"
  else
    echo -e "  ${YELLOW}🟡 未检测到路由级别懒加载 (React.lazy)${NC}"
    echo -e "     建议: 将路由组件改为 ${MAGENTA}const Page = lazy(() => import('./pages/Page'))${NC}"
    ISSUES_COUNT=$((ISSUES_COUNT + 1))
  fi

  # Check for Suspense
  HAS_SUSPENSE=$(echo "$REACT_ROUTER_FILES" | xargs grep -l 'Suspense' 2>/dev/null || true)
  if [[ -n "$HAS_SUSPENSE" ]]; then
    echo -e "  ${GREEN}✅ 检测到 Suspense${NC}"
  else
    echo -e "  ${YELLOW}🟡 未检测到 Suspense，lazy 加载需要配合 Suspense 使用${NC}"
    ISSUES_COUNT=$((ISSUES_COUNT + 1))
  fi
else
  echo -e "  ${YELLOW}未检测到 React Router 配置${NC}"
fi

# Next.js - check for next/dynamic
if [[ "$FRAMEWORK" == "Next.js" ]]; then
  echo ""
  echo -e "  ${CYAN}Next.js 动态导入检查:${NC}"

  NEXT_DYNAMIC=$(find . -type f \( -name "*.tsx" -o -name "*.jsx" \) \
    -not -path "*/node_modules/*" 2>/dev/null | xargs grep -l 'next/dynamic\|dynamic(' 2>/dev/null || true)

  if [[ -n "$NEXT_DYNAMIC" ]]; then
    count=$(echo "$NEXT_DYNAMIC" | wc -l | tr -d ' ')
    echo -e "    ${GREEN}✅ 检测到 $count 个文件使用 next/dynamic${NC}"
  else
    echo -e "    ${YELLOW}🟡 未检测到 next/dynamic 使用${NC}"
    echo -e "       建议: 重型组件使用 ${MAGENTA}const Heavy = dynamic(() => import('../components/Heavy'))${NC}"
    ISSUES_COUNT=$((ISSUES_COUNT + 1))
  fi
fi

# Vue Router
VUE_ROUTER_FILES=$(find . -type f \( -name "*.vue" -o -name "*.ts" -o -name "*.js" \) \
  -not -path "*/node_modules/*" 2>/dev/null | xargs grep -l 'createRouter\|VueRouter' 2>/dev/null || true)

if [[ -n "$VUE_ROUTER_FILES" ]]; then
  echo ""
  echo -e "  ${CYAN}Vue Router 检查:${NC}"

  HAS_VUE_LAZY=$(echo "$VUE_ROUTER_FILES" | xargs grep -lE '\(\)\s*=>\s*import' 2>/dev/null || true)
  if [[ -n "$HAS_VUE_LAZY" ]]; then
    echo -e "    ${GREEN}✅ 检测到路由懒加载 (() => import())${NC}"
  else
    echo -e "    ${YELLOW}🟡 未检测到 Vue 路由懒加载${NC}"
    echo -e "       建议: ${MAGENTA}component: () => import('./views/Page.vue')${NC}"
    ISSUES_COUNT=$((ISSUES_COUNT + 1))
  fi
fi

# Angular
if [[ "$FRAMEWORK" == "Angular" ]]; then
  echo ""
  echo -e "  ${CYAN}Angular 懒加载检查:${NC}"

  ANGULAR_LAZY=$(find . -type f \( -name "*.ts" \) -not -path "*/node_modules/*" 2>/dev/null | xargs grep -l 'loadChildren' 2>/dev/null || true)
  if [[ -n "$ANGULAR_LAZY" ]]; then
    echo -e "    ${GREEN}✅ 检测到 loadChildren 懒加载${NC}"
  else
    echo -e "    ${YELLOW}🟡 未检测到 Angular 懒加载模块${NC}"
    echo -e "       建议: 使用 ${MAGENTA}loadChildren: () => import('./module')${NC}"
    ISSUES_COUNT=$((ISSUES_COUNT + 1))
  fi
fi

echo ""

# ──────────────────────────────────────────
# 2. Component-level dynamic imports
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ 组件级别动态导入检查${NC}"

# Find all static imports that could be dynamic
find . -type f \( -name "*.tsx" -o -name "*.jsx" -o -name "*.ts" -o -name "*.js" \) \
  -not -path "*/node_modules/*" 2>/dev/null | while read -r file; do

  # Skip router config files (already checked)
  if echo "$file" | grep -qE 'router|route|App\.(tsx|jsx)'; then
    continue
  fi

  # Check for imports from potentially heavy modules
  grep -nE "from\s+['\"](echarts|three|@tinymce|@monaco-editor|pdfjs|xlsx|jszip|fabric|konva|zdog|p5|babylonjs)['\"]" "$file" 2>/dev/null | while read -r line; do
    lineno=$(echo "$line" | cut -d':' -f1)
    content=$(echo "$line" | cut -d':' -f2-)

    # Skip if already dynamic import
    if echo "$content" | grep -qE 'await\s+import\(|import\(|React\.lazy|dynamic\('; then
      continue
    fi

    module_name=$(echo "$content" | grep -oE "['\"][^'\"]+['\"]" | head -1 | tr -d "'\"")
    echo -e "  ${YELLOW}🟡 [Split]${NC} $file:$lineno"
    echo -e "     重型模块静态导入: ${MAGENTA}$module_name${NC}"
    echo -e "     建议: 使用动态导入延迟加载"
    ISSUES_COUNT=$((ISSUES_COUNT + 1))
  done

done

echo ""

# ──────────────────────────────────────────
# 3. Heavy component detection (by file size)
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ 大型组件检测 (文件体积 > 20KB)${NC}"

find . -type f \( -name "*.tsx" -o -name "*.jsx" -o -name "*.vue" -o -name "*.svelte" \) \
  -size +20k -not -path "*/node_modules/*" 2>/dev/null | sort -k2 -rn | while read -r file; do
  size=$(du -h "$file" 2>/dev/null | cut -f1)
  echo -e "  ${YELLOW}🟡${NC} ${size}  ${file}"

done | head -20

echo ""

# ──────────────────────────────────────────
# 4. Build config for code splitting
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ 构建配置代码分割${NC}"

# Vite manualChunks
if [[ -f "vite.config.ts" || -f "vite.config.js" ]]; then
  VITE_CONFIG=$(cat vite.config.* 2>/dev/null || true)

  if echo "$VITE_CONFIG" | grep -q 'manualChunks'; then
    echo -e "  ${GREEN}✅ Vite 已配置 manualChunks${NC}"
    # Show the config
    echo "$VITE_CONFIG" | grep -A 10 'manualChunks' | sed 's/^/    /'
  else
    echo -e "  ${YELLOW}🟡 Vite 未配置 manualChunks${NC}"
    echo -e "     建议添加:"
    echo -e "     ${MAGENTA}build: {${NC}"
    echo -e "     ${MAGENTA}  rollupOptions: {${NC}"
    echo -e "     ${MAGENTA}    output: {${NC}"
    echo -e "     ${MAGENTA}      manualChunks: {${NC}"
    echo -e "     ${MAGENTA}        'vendor-react': ['react', 'react-dom'],${NC}"
    echo -e "     ${MAGENTA}        'vendor-ui': ['@mui/material'],${NC}"
    echo -e "     ${MAGENTA}      }${NC}"
    echo -e "     ${MAGENTA}    }${NC}"
    echo -e "     ${MAGENTA}  }${NC}"
    echo -e "     ${MAGENTA}}${NC}"
    ISSUES_COUNT=$((ISSUES_COUNT + 1))
  fi
fi

# Webpack splitChunks
if [[ -f "webpack.config.js" || -f "webpack.config.ts" ]]; then
  WP_CONFIG=$(cat webpack.config.* 2>/dev/null || true)

  if echo "$WP_CONFIG" | grep -q 'splitChunks'; then
    echo -e "  ${GREEN}✅ Webpack 已配置 splitChunks${NC}"
  else
    echo -e "  ${YELLOW}🟡 Webpack 未配置 splitChunks${NC}"
    echo -e "     建议配置 optimization.splitChunks"
    ISSUES_COUNT=$((ISSUES_COUNT + 1))
  fi
fi

# Next.js experimental features
if [[ "$FRAMEWORK" == "Next.js" ]]; then
  NEXT_CONFIG=$(cat next.config.* 2>/dev/null || true)

  if echo "$NEXT_CONFIG" | grep -q 'optimizePackageImports'; then
    echo -e "  ${GREEN}✅ 已启用 optimizePackageImports${NC}"
  else
    echo -e "  ${YELLOW}🟡 未启用 optimizePackageImports${NC}"
    echo -e "     建议: ${MAGENTA}experimental: { optimizePackageImports: ['lodash', 'date-fns'] }${NC}"
  fi
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "代码分割检查完成，发现问题: ${BOLD}${ISSUES_COUNT}${NC}"
