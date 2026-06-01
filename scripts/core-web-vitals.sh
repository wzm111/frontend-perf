#!/bin/bash
# Core Web Vitals 诊断脚本
# 检测 LCP/INP/CLS/TTFB 相关的前端性能问题

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

TARGET_DIR="${1:-.}"
ISSUES_FILE="/tmp/frontend-perf-cwv-$$.txt"
touch "$ISSUES_FILE"

cd "$TARGET_DIR"

echo -e "${CYAN}${BOLD}🔍 Core Web Vitals 诊断${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ──────────────────────────────────────────
# Detect framework
# ──────────────────────────────────────────
FRAMEWORK="Unknown"
BUILD_TOOL="Unknown"
[[ -f "next.config.js" || -f "next.config.ts" || -f "next.config.mjs" ]] && FRAMEWORK="Next.js"
[[ -f "nuxt.config.ts" || -f "nuxt.config.js" ]] && FRAMEWORK="Nuxt"
[[ -f "vite.config.ts" || -f "vite.config.js" ]] && BUILD_TOOL="Vite"
[[ -f "webpack.config.js" || -f "webpack.config.ts" ]] && BUILD_TOOL="Webpack"
[[ -f "astro.config.mjs" || -f "astro.config.ts" ]] && FRAMEWORK="Astro"
[[ -f "angular.json" ]] && FRAMEWORK="Angular"

echo -e "${CYAN}【框架检测】${NC} 框架: ${BOLD}$FRAMEWORK${NC}, 构建工具: ${BOLD}$BUILD_TOOL${NC}"
echo ""

# ──────────────────────────────────────────
# 1. LCP - Largest Contentful Paint
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ LCP (Largest Contentful Paint) 检查${NC}"

# Check for img tags without loading attribute or width/height
IMG_ISSUES=0

# Find all HTML/JSX/TSX/Vue files
find . -type f \( \
  -name "*.html" -o \
  -name "*.jsx" -o -name "*.tsx" -o \
  -name "*.vue" -o -name "*.svelte" -o \
  -name "*.astro" -o -name "*.js" -o -name "*.ts" \
\) -not -path "*/node_modules/*" -not -path "*/.next/*" -not -path "*/dist/*" 2>/dev/null | while read -r file; do

  # Check img tags without width or height (causes CLS + hurts LCP)
  grep -n 'img[^>]*\(src=\|src:)' "$file" 2>/dev/null | while read -r line; do
    lineno=$(echo "$line" | cut -d':' -f1)
    content=$(echo "$line" | cut -d':' -f2-)

    # Skip if it's a Next.js Image component
    if echo "$content" | grep -q 'next/image\|from.*next/image'; then
      continue
    fi

    # Skip commented lines
    if echo "$content" | grep -qE '^\s*(//|/\*|\*)'; then
      continue
    fi

    # Check for width/height attributes or style
    has_width=$(echo "$content" | grep -cE '(width[=:]|w=|style=.*width)' || true)
    has_height=$(echo "$content" | grep -cE '(height[=:]|h=|style=.*height)' || true)
    has_aspect=$(echo "$content" | grep -cE '(aspect-ratio|className.*aspect)' || true)

    if [[ "$has_width" -eq 0 && "$has_height" -eq 0 && "$has_aspect" -eq 0 ]]; then
      # Check if it's above-the-fold (hero) image - likely LCP element
      if echo "$content" | grep -qiE 'hero|banner|logo|header|background'; then
        echo -e "  ${RED}🔴 [CLS/LCP]${NC} $file:$lineno 图片缺少 width/height，可能导致布局偏移"
        echo -e "     内容: ${YELLOW}$(echo "$content" | head -c 80)${NC}"
      else
        echo -e "  ${YELLOW}🟡 [CLS]${NC} $file:$lineno 图片可能缺少 width/height"
        echo -e "     内容: $(echo "$content" | head -c 80)"
      fi
      echo "IMG_ISSUE|$file|$lineno|missing_dimensions" >> "$ISSUES_FILE"
    fi

    # Check for loading="lazy" on likely above-the-fold images
    has_lazy=$(echo "$content" | grep -cE 'loading\s*=\s*["'\''"]lazy' || true)
    if [[ "$has_lazy" -gt 0 ]]; then
      if echo "$content" | grep -qiE 'hero|banner|logo|header'; then
        echo -e "  ${YELLOW}🟡 [LCP]${NC} $file:$lineno 首屏图片不应使用 loading=\"lazy\"，会延迟 LCP"
        echo "IMG_ISSUE|$file|$lineno|hero_with_lazy" >> "$ISSUES_FILE"
      fi
    fi
  done

done

# Check for render-blocking resources in HTML files
find . -name "*.html" -not -path "*/node_modules/*" -not -path "*/.next/*" -not -path "*/dist/*" 2>/dev/null | while read -r file; do
  # Check CSS in head without media query or preload
  grep -n '<link.*rel="stylesheet"' "$file" 2>/dev/null | grep -v 'media=' | grep -v 'preload' | while read -r line; do
    lineno=$(echo "$line" | cut -d':' -f1)
    echo -e "  ${YELLOW}🟡 [LCP]${NC} $file:$lineno CSS 可能阻塞渲染，建议添加 media 查询或预加载"
  done

  # Check scripts in head without async/defer/type=module
  grep -n '<script.*src=' "$file" 2>/dev/null | grep -v 'async' | grep -v 'defer' | grep -v 'type="module"' | while read -r line; do
    lineno=$(echo "$line" | cut -d':' -f1)
    echo -e "  ${YELLOW}🟡 [LCP]${NC} $file:$lineno script 可能阻塞渲染，建议添加 async/defer"
  done
done

echo ""

# ──────────────────────────────────────────
# 2. CLS - Cumulative Layout Shift
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ CLS (Cumulative Layout Shift) 检查${NC}"

# Check for font-display missing
find . -type f \( -name "*.css" -o -name "*.scss" -o -name "*.less" -o -name "*.styl" \) \
  -not -path "*/node_modules/*" 2>/dev/null | while read -r file; do
  grep -n '@font-face' "$file" 2>/dev/null | while read -r line; do
    lineno=$(echo "$line" | cut -d':' -f1)
    # Check a few lines after @font-face for font-display
    next_lines=$(sed -n "${lineno},$(($lineno + 5))p" "$file" 2>/dev/null)
    if ! echo "$next_lines" | grep -q 'font-display'; then
      echo -e "  ${YELLOW}🟡 [CLS]${NC} $file:$lineno @font-face 缺少 font-display，可能导致 FOIT/FOUT"
    fi
  done
done

# Check for iframe/embed without dimensions
find . -type f \( -name "*.html" -o -name "*.jsx" -o -name "*.tsx" -o -name "*.vue" \) \
  -not -path "*/node_modules/*" -not -path "*/.next/*" 2>/dev/null | while read -r file; do
  grep -nE '<(iframe|embed|object)' "$file" 2>/dev/null | while read -r line; do
    lineno=$(echo "$line" | cut -d':' -f1)
    content=$(echo "$line" | cut -d':' -f2-)
    if ! echo "$content" | grep -qE '(width[=:]|height[=:])'; then
      echo -e "  ${YELLOW}🟡 [CLS]${NC} $file:$lineno iframe/embed 缺少 width/height，可能导致布局偏移"
    fi
  done
done

echo ""

# ──────────────────────────────────────────
# 3. INP - Interaction to Next Paint
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ INP (Interaction to Next Paint) 检查${NC}"

# Check for heavy computations in useEffect/useLayoutEffect
find . -type f \( -name "*.jsx" -o -name "*.tsx" -o -name "*.js" -o -name "*.ts" \) \
  -not -path "*/node_modules/*" 2>/dev/null | while read -r file; do
  grep -n 'useLayoutEffect' "$file" 2>/dev/null | while read -r line; do
    lineno=$(echo "$line" | cut -d':' -f1)
    # Check if useLayoutEffect contains heavy operations
    next_content=$(sed -n "${lineno},$(($lineno + 20))p" "$file" 2>/dev/null)
    if echo "$next_content" | grep -qE '(for\s*\(|while\s*\(|\.map\(|\.filter\(|\.reduce\(|JSON\.parse\(.)'; then
      echo -e "  ${YELLOW}🟡 [INP]${NC} $file:$lineno useLayoutEffect 包含可能阻塞主线程的计算"
    fi
  done

done

# Check for large dataset operations without yielding
find . -type f \( -name "*.jsx" -o -name "*.tsx" -o -name "*.js" -o -name "*.ts" \) \
  -not -path "*/node_modules/*" 2>/dev/null | while read -r file; do
  grep -nE '\.map\(.*\).*\.map\(|\.filter\(.*\).*\.filter\(' "$file" 2>/dev/null | while read -r line; do
    lineno=$(echo "$line" | cut -d':' -f1)
    echo -e "  ${YELLOW}🟡 [INP]${NC} $file:$lineno 链式数组操作可能阻塞主线程，建议使用 Web Worker 或分片处理"
  done
done

echo ""

# ──────────────────────────────────────────
# 4. Third-party scripts
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ 第三方脚本检查${NC}"

find . -name "*.html" -not -path "*/node_modules/*" 2>/dev/null | while read -r file; do
  grep -nE '(google-analytics|googletagmanager|gtag|facebook|analytics|hotjar|sentry|clarity)' "$file" 2>/dev/null | while read -r line; do
    lineno=$(echo "$line" | cut -d':' -f1)
    content=$(echo "$line" | cut -d':' -f2-)
    if ! echo "$content" | grep -qE '(async|defer)'; then
      echo -e "  ${YELLOW}🟡 [LCP/INP]${NC} $file:$lineno 第三方脚本缺少 async/defer，可能阻塞渲染"
    fi
  done
done

echo ""

# ──────────────────────────────────────────
# 5. Framework-specific checks
# ──────────────────────────────────────────
if [[ "$FRAMEWORK" == "Next.js" ]]; then
  echo -e "${CYAN}${BOLD}▶ Next.js 专项检查${NC}"

  # Check for next/image usage vs raw img
  find . -type f \( -name "*.jsx" -o -name "*.tsx" \) -not -path "*/node_modules/*" 2>/dev/null | while read -r file; do
    grep -n '<img' "$file" 2>/dev/null | while read -r line; do
      lineno=$(echo "$line" | cut -d':' -f1)
      echo -e "  ${YELLOW}🟡 [LCP]${NC} $file:$lineno 使用原生 img 标签，建议替换为 next/image 以获得自动优化"
    done
  done

  # Check for next/script usage
  if grep -r 'googletagmanager\|gtag\|analytics' --include="*.tsx" --include="*.jsx" . 2>/dev/null | grep -v 'next/script' | head -1 >/dev/null; then
    echo -e "  ${YELLOW}🟡 [LCP]${NC} 检测到第三方脚本未使用 next/script，建议迁移以获得加载策略控制"
  fi
fi

if [[ "$BUILD_TOOL" == "Vite" ]]; then
  echo -e "${CYAN}${BOLD}▶ Vite 专项检查${NC}"

  if [[ -f "vite.config.ts" || -f "vite.config.js" ]]; then
    VITE_CONFIG=$(cat vite.config.ts 2>/dev/null || cat vite.config.js 2>/dev/null)

    # Check for build.rollupOptions.output.manualChunks
    if ! echo "$VITE_CONFIG" | grep -q 'manualChunks'; then
      echo -e "  ${YELLOW}🟡 [LCP]${NC} vite.config 缺少 manualChunks 配置，建议按 vendor/page 分割代码"
    fi
  fi
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Core Web Vitals 诊断完成${NC}"

# Cleanup
rm -f "$ISSUES_FILE"
