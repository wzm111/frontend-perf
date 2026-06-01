#!/bin/bash
# 资源优化诊断脚本
# 检测图片、字体、CSS 等未优化资源

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

echo -e "${CYAN}${BOLD}🖼️  资源优化诊断${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ──────────────────────────────────────────
# 1. Image optimization check
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ 图片资源检查${NC}"

# Find all images
IMAGES=$(find . -type f \( \
  -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o \
  -iname "*.gif" -o -iname "*.bmp" -o -iname "*.tiff" \
\) -not -path "*/node_modules/*" -not -path "*/.next/*" -not -path "*/dist/*" -not -path "*/build/*" 2>/dev/null || true)

if [[ -z "$IMAGES" ]]; then
  echo -e "  ${YELLOW}未检测到图片资源${NC}"
else
  img_count=$(echo "$IMAGES" | wc -l | tr -d ' ')
  echo -e "  检测到 ${BOLD}$img_count${NC} 个图片文件"
  echo ""

  # Check large images (> 100KB)
  echo "  大图片检测 (>100KB):"
  echo "$IMAGES" | while read -r img; do
    size=$(stat -f%z "$img" 2>/dev/null || stat -c%s "$img" 2>/dev/null || echo 0)
    if [[ "$size" -gt 102400 ]]; then
      size_human=$(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size}B")
      echo -e "    ${RED}🔴${NC} ${size_human}  ${img}"
      # Check if WebP/AVIF alternative exists
      base="${img%.*}"
      if [[ ! -f "${base}.webp" && ! -f "${base}.avif" ]]; then
        echo -e "       ${YELLOW}→ 未找到 WebP/AVIF 替代格式${NC}"
        ISSUES_COUNT=$((ISSUES_COUNT + 1))
      fi
    fi
  done | sort -k2 -rn

  # Check for missing srcset
  echo ""
  echo "  响应式图片检查 (srcset):"
  find . -type f \( -name "*.html" -o -name "*.jsx" -o -name "*.tsx" -o -name "*.vue" -o -name "*.svelte" -o -name "*.astro" \) \
    -not -path "*/node_modules/*" 2>/dev/null | while read -r file; do
    grep -n '<img' "$file" 2>/dev/null | grep -v 'srcSet\|srcset' | grep -v 'next/image' | while read -r line; do
      lineno=$(echo "$line" | cut -d':' -f1)
      # Skip if it's a small icon
      content=$(echo "$line" | cut -d':' -f2-)
      if echo "$content" | grep -qiE 'icon|favicon|logo.*small|avatar.*small'; then
        continue
      fi
      echo -e "    ${YELLOW}🟡${NC} $file:$lineno 缺少 srcset (响应式图片)"
      ISSUES_COUNT=$((ISSUES_COUNT + 1))
    done
  done

  # Check for SVG optimization
  echo ""
  echo "  SVG 优化检查:"
  SVGS=$(find . -type f -iname "*.svg" -not -path "*/node_modules/*" 2>/dev/null || true)
  if [[ -n "$SVGS" ]]; then
    svg_count=$(echo "$SVGS" | wc -l | tr -d ' ')
    echo -e "    检测到 ${BOLD}$svg_count${NC} 个 SVG 文件"

    # Check for unoptimized SVGs (verbose with whitespace)
    echo "$SVGS" | while read -r svg; do
      # Check if SVG has unnecessary whitespace/precision
      if grep -q '  ' "$svg" 2>/dev/null || grep -q 'decimals="[5-9]"' "$svg" 2>/dev/null; then
        size=$(du -h "$svg" 2>/dev/null | cut -f1)
        echo -e "    ${YELLOW}🟡${NC} ${size} ${svg} (可能未优化)"
      fi
    done
  fi
fi

echo ""

# ──────────────────────────────────────────
# 2. Font optimization check
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ 字体资源检查${NC}"

FONTS=$(find . -type f \( \
  -iname "*.woff" -o -iname "*.woff2" -o -iname "*.ttf" -o \
  -iname "*.otf" -o -iname "*.eot" \
\) -not -path "*/node_modules/*" -not -path "*/.next/*" -not -path "*/dist/*" 2>/dev/null || true)

if [[ -z "$FONTS" ]]; then
  echo -e "  ${YELLOW}未检测到本地字体文件${NC}"
else
  font_count=$(echo "$FONTS" | wc -l | tr -d ' ')
  echo -e "  检测到 ${BOLD}$font_count${NC} 个字体文件"
  echo ""

  # Check large fonts (> 40KB)
  echo "  大字体检测 (>40KB):"
  echo "$FONTS" | while read -r font; do
    size=$(stat -f%z "$font" 2>/dev/null || stat -c%s "$font" 2>/dev/null || echo 0)
    if [[ "$size" -gt 40960 ]]; then
      size_human=$(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size}B")
      echo -e "    ${YELLOW}🟡${NC} ${size_human}  ${font}"
      echo -e "       ${YELLOW}→ 建议: 子集化字体 (使用 fonttools/pyftsubset 或 glyphhanger)${NC}"
      ISSUES_COUNT=$((ISSUES_COUNT + 1))
    fi
  done | sort -k2 -rn

  # Check for font-display in CSS
  echo ""
  echo "  font-display 检查:"
  CSS_FILES=$(find . -type f \( -name "*.css" -o -name "*.scss" -o -name "*.less" \) \
    -not -path "*/node_modules/*" 2>/dev/null || true)

  if [[ -n "$CSS_FILES" ]]; then
    FOUND_FONT_DISPLAY=0
    echo "$CSS_FILES" | while read -r css; do
      if grep -q 'font-display' "$css" 2>/dev/null; then
        FOUND_FONT_DISPLAY=1
      fi
    done

    if [[ "$FOUND_FONT_DISPLAY" -eq 0 ]]; then
      echo -e "    ${YELLOW}🟡${NC} 未检测到 font-display 设置"
      echo -e "       ${GREEN}建议: 添加 font-display: swap 避免 FOIT${NC}"
      ISSUES_COUNT=$((ISSUES_COUNT + 1))
    else
      echo -e "    ${GREEN}✅ 已配置 font-display${NC}"
    fi
  fi

  # Check for font preloading
  HTML_FILES=$(find . -name "*.html" -not -path "*/node_modules/*" 2>/dev/null || true)
  if [[ -n "$HTML_FILES" ]]; then
    FOUND_PRELOAD=0
    echo "$HTML_FILES" | while read -r html; do
      if grep -q 'rel="preload".*font' "$html" 2>/dev/null || grep -q 'as="font"' "$html" 2>/dev/null; then
        FOUND_PRELOAD=1
      fi
    done

    if [[ "$FOUND_PRELOAD" -eq 0 ]]; then
      echo -e "    ${YELLOW}🟡${NC} 未检测到字体预加载"
      echo -e "       ${GREEN}建议: <link rel=\"preload\" href=\"/font.woff2\" as=\"font\" type=\"font/woff2\" crossorigin>${NC}"
    else
      echo -e "    ${GREEN}✅ 已配置字体预加载${NC}"
    fi
  fi
fi

echo ""

# ──────────────────────────────────────────
# 3. CSS optimization check
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ CSS 优化检查${NC}"

# Check for unused CSS (look for PurgeCSS or similar)
PACKAGE_JSON=$(cat package.json 2>/dev/null || true)

if echo "$PACKAGE_JSON" | grep -qE 'purgecss|unplugin-purge|postcss-purgecss|css-purge'; then
  echo -e "  ${GREEN}✅ 已配置 CSS 清除工具${NC}"
else
  echo -e "  ${YELLOW}🟡 未检测到 CSS 清除工具${NC}"
  echo -e "     建议: 安装 ${MAGENTA}purgecss${NC} 或 ${MAGENTA}unplugin-purge${NC} 移除未使用 CSS"
  ISSUES_COUNT=$((ISSUES_COUNT + 1))
fi

# Check for critical CSS
if echo "$PACKAGE_JSON" | grep -qE 'critical|critters|penthouse'; then
  echo -e "  ${GREEN}✅ 已配置关键 CSS 提取${NC}"
else
  echo -e "  ${YELLOW}🟡 未检测到关键 CSS 提取${NC}"
  echo -e "     建议: 使用 ${MAGENTA}critters${NC} (Vite/Webpack) 或 ${MAGENTA}Next.js 内置优化${NC}"
fi

# Check for styled-components without babel plugin
if echo "$PACKAGE_JSON" | grep -q 'styled-components'; then
  if echo "$PACKAGE_JSON" | grep -q 'babel-plugin-styled-components\|@swc/plugin-styled-components'; then
    echo -e "  ${GREEN}✅ styled-components 已配置编译优化${NC}"
  else
    echo -e "  ${YELLOW}🟡 styled-components 缺少 babel/swc 插件${NC}"
    echo -e "     建议: 安装 babel-plugin-styled-components 减少运行时开销"
    ISSUES_COUNT=$((ISSUES_COUNT + 1))
  fi
fi

echo ""

# ──────────────────────────────────────────
# 4. Video / Audio check
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ 视频/音频资源检查${NC}"

MEDIA=$(find . -type f \( -iname "*.mp4" -o -iname "*.webm" -o -iname "*.mov" -o -iname "*.avi" \) \
  -not -path "*/node_modules/*" -not -path "*/.next/*" -not -path "*/dist/*" 2>/dev/null || true)

if [[ -n "$MEDIA" ]]; then
  media_count=$(echo "$MEDIA" | wc -l | tr -d ' ')
  echo -e "  检测到 ${BOLD}$media_count${NC} 个视频文件"

  echo "$MEDIA" | while read -r vid; do
    size=$(stat -f%z "$vid" 2>/dev/null || stat -c%s "$vid" 2>/dev/null || echo 0)
    if [[ "$size" -gt 5242880 ]]; then  # > 5MB
      size_human=$(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size}B")
      echo -e "    ${YELLOW}🟡${NC} ${size_human} ${vid}"
      echo -e "       ${YELLOW}→ 建议: 压缩视频或使用流媒体 (HLS/DASH)${NC}"
      ISSUES_COUNT=$((ISSUES_COUNT + 1))
    fi
  done
else
  echo -e "  ${GREEN}✅ 未检测到本地视频资源${NC}"
fi

echo ""

# ──────────────────────────────────────────
# 5. Compression check
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ 压缩配置检查${NC}"

BUILD_DIRS=("dist" "build" ".next" "out")
for dir in "${BUILD_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    # Check for pre-compressed files
    gzip_count=$(find "$dir" -name "*.gz" 2>/dev/null | wc -l | tr -d ' ')
    br_count=$(find "$dir" -name "*.br" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$gzip_count" -gt 0 || "$br_count" -gt 0 ]]; then
      echo -e "  ${GREEN}✅ 构建产物包含预压缩文件 (.gz: $gzip_count, .br: $br_count)${NC}"
    else
      echo -e "  ${YELLOW}🟡 构建产物未预压缩${NC}"
      echo -e "     建议: Vite 配置 ${MAGENTA}build: { reportCompressedSize: true }${NC}"
      echo -e "     或 Webpack: ${MAGENTA}CompressionPlugin${NC}"
    fi
    break
  fi
done

echo ""

# ──────────────────────────────────────────
# 6. CDN / External resource check
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ 外部资源加载检查${NC}"

find . -type f \( -name "*.html" -o -name "*.jsx" -o -name "*.tsx" \) \
  -not -path "*/node_modules/*" 2>/dev/null | while read -r file; do

  # Check for external scripts without integrity
  grep -nE 'src="https?://' "$file" 2>/dev/null | while read -r line; do
    lineno=$(echo "$line" | cut -d':' -f1)
    content=$(echo "$line" | cut -d':' -f2-)
    if ! echo "$content" | grep -q 'integrity='; then
      echo -e "  ${YELLOW}🟡${NC} $file:$lineno 外部脚本缺少 integrity 属性 (SRI)"
    fi
  done

done

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "资源优化诊断完成，发现问题: ${BOLD}${ISSUES_COUNT}${NC}"
