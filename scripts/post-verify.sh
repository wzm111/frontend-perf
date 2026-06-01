#!/bin/bash
# Post-Diagnosis Verification / 诊断后验证脚本
# 对构建产物进行实际验证，确认诊断建议是否准确
#
# Usage: post-verify.sh [dir] [--lighthouse]

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
RUN_LIGHTHOUSE=false

cd "$TARGET_DIR"

# Parse arguments
for arg in "$@"; do
  if [[ "$arg" == "--lighthouse" || "$arg" == "-l" ]]; then
    RUN_LIGHTHOUSE=true
  fi
done

echo ""
echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║              🔍 诊断后验证 / Post-Diagnosis Verify          ║${NC}"
echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Detect build output directory ─────────────────────────
BUILD_DIRS=("dist" "build" ".next" "out" ".output")
BUILD_DIR=""
for dir in "${BUILD_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    BUILD_DIR="$dir"
    break
  fi
done

if [[ -z "$BUILD_DIR" ]]; then
  echo -e "  ${YELLOW}⚠️ 未找到构建产物目录${NC}"
  echo -e "  请先运行构建命令（如 npm run build）"
  exit 1
fi

echo -e "  ${BLUE}产物目录:${NC} ${BOLD}$BUILD_DIR${NC}"
echo ""

# ── 1. Build Artifact Analysis / 产物解析验证 ─────────────
echo -e "${CYAN}${BOLD}▶ 产物解析验证${NC}"
echo -e "${BLUE}────────────────────────────────────────${NC}"
echo ""

# 1.1 Check for tree-shaking effectiveness
echo -e "  ${CYAN}1.1 Tree-shaking 有效性检查${NC}"

# Detect heavy modules in JS output
JS_FILES=$(find "$BUILD_DIR" -name "*.js" -o -name "*.mjs" 2>/dev/null || true)
if [[ -n "$JS_FILES" ]]; then
  HEAVY_IN_BUNDLE=0

  # Check for full lodash in bundle
  if echo "$JS_FILES" | xargs grep -l 'lodash/LICENSE\|baseClone\|baseMerge\|baseDifference' 2>/dev/null | head -1 >/dev/null; then
    echo -e "    ${RED}🔴${NC} 构建产物中检测到 lodash 全量代码"
    echo -e "       ${YELLOW}→ Tree-shaking 未生效，lodash-es 未正确配置${NC}"
    HEAVY_IN_BUNDLE=1
  fi

  # Check for moment in bundle
  if echo "$JS_FILES" | xargs grep -l 'moment.js\|moment/min\|moment\.lang' 2>/dev/null | head -1 >/dev/null; then
    echo -e "    ${RED}🔴${NC} 构建产物中检测到 moment 代码"
    echo -e "       ${YELLOW}→ 建议替换为 dayjs${NC}"
    HEAVY_IN_BUNDLE=1
  fi

  # Check for jQuery in bundle
  if echo "$JS_FILES" | xargs grep -l 'jQuery\|jquery\.fn\|\.extend.*jQuery' 2>/dev/null | head -1 >/dev/null; then
    echo -e "    ${RED}🔴${NC} 构建产物中检测到 jQuery 代码"
    HEAVY_IN_BUNDLE=1
  fi

  if [[ "$HEAVY_IN_BUNDLE" -eq 0 ]]; then
    echo -e "    ${GREEN}✅${NC} 未检测到已知大体积依赖残留"
  fi

  # Check total JS bundle size
  total_js_size=$(find "$BUILD_DIR" -name "*.js" -o -name "*.mjs" | xargs stat -f%z 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo 0)
  if [[ "$total_js_size" -gt 1048576 ]]; then
    total_js_mb=$(echo "scale=2; $total_js_size / 1048576" | bc 2>/dev/null || echo "$((total_js_size / 1048576))")
    echo -e "    ${YELLOW}🟡${NC} 总 JS 体积: ${BOLD}${total_js_mb}MB${NC} (建议控制在 1MB 以下)"
  else
    total_js_kb=$((total_js_size / 1024))
    echo -e "    ${GREEN}✅${NC} 总 JS 体积: ${BOLD}${total_js_kb}KB${NC}"
  fi
fi
echo ""

# 1.2 Check code splitting effectiveness
echo -e "  ${CYAN}1.2 代码分割有效性检查${NC}"

# Count chunk files
CHUNK_COUNT=$(find "$BUILD_DIR" -name "*.js" -o -name "*.mjs" -o -name "*.css" | wc -l | tr -d ' ')
echo -e "    产物文件数: ${BOLD}${CHUNK_COUNT}${NC}"

# Check for chunk naming patterns
if find "$BUILD_DIR" -name "vendor*" -o -name "chunk-*" -o -name "[0-9]*.js" 2>/dev/null | head -1 >/dev/null; then
  echo -e "    ${GREEN}✅${NC} 检测到代码分割产生的 chunk 文件"

  # List chunks
  echo -e "    Chunk 列表:"
  find "$BUILD_DIR" \( -name "vendor*" -o -name "chunk-*" -o -name "[0-9]*.js" \) -not -name "node_modules" 2>/dev/null | while read -r chunk; do
    size=$(du -h "$chunk" 2>/dev/null | cut -f1)
    echo -e "      ${size}  $(basename "$chunk")"
  done | head -10
else
  echo -e "    ${YELLOW}🟡${NC} 未检测到明显的代码分割 chunk 文件"
  echo -e "       ${YELLOW}→ 建议配置 manualChunks / splitChunks${NC}"
fi
echo ""

# 1.3 Check HTML for async/defer scripts
echo -e "  ${CYAN}1.3 脚本加载策略验证${NC}"

HTML_FILES=$(find "$BUILD_DIR" -name "*.html" 2>/dev/null || true)
if [[ -n "$HTML_FILES" ]]; then
  SYNC_SCRIPTS=0
  echo "$HTML_FILES" | while read -r html; do
    # Find scripts without async/defer/module
    grep -oE '<script[^>]*src="[^"]+"[^>]*>' "$html" 2>/dev/null | grep -v 'async' | grep -v 'defer' | grep -v 'type="module"' | while read -r script; do
      SYNC_SCRIPTS=1
      src=$(echo "$script" | grep -oE 'src="[^"]+"' | sed 's/src="//;s/"//')
      echo -e "    ${YELLOW}🟡${NC} 同步加载: $src"
    done
  done

  if [[ "$SYNC_SCRIPTS" -eq 0 ]]; then
    echo -e "    ${GREEN}✅${NC} 所有外部脚本均使用 async/defer/module"
  fi
else
  echo -e "    ${YELLOW}🟡${NC} 未找到 HTML 文件（可能是 SPA 框架如 Next.js）"
fi
echo ""

# 1.4 Check for optimized images in build output
echo -e "  ${CYAN}1.4 产物图片格式检查${NC}"

IMAGES=$(find "$BUILD_DIR" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" -o -iname "*.avif" \) 2>/dev/null || true)
if [[ -n "$IMAGES" ]]; then
  png_jpg=$(echo "$IMAGES" | grep -icE '\.(png|jpg|jpeg)$' || echo 0)
  webp=$(echo "$IMAGES" | grep -ic '\.webp$' || echo 0)
  avif=$(echo "$IMAGES" | grep -ic '\.avif$' || echo 0)

  echo -e "    PNG/JPG: ${BOLD}$png_jpg${NC}  WebP: ${BOLD}$webp${NC}  AVIF: ${BOLD}$avif${NC}"

  if [[ "$webp" -eq 0 && "$avif" -eq 0 && "$png_jpg" -gt 0 ]]; then
    echo -e "    ${YELLOW}🟡${NC} 未检测到 WebP/AVIF 优化格式"
    echo -e "       ${YELLOW}→ 建议配置图片转换工具${NC}"
  elif [[ "$webp" -gt 0 || "$avif" -gt 0 ]]; then
    echo -e "    ${GREEN}✅${NC} 检测到现代图片格式 (WebP/AVIF)"
  fi
else
  echo -e "    ${GREEN}✅${NC} 构建产物中无图片资源"
fi
echo ""

# 1.5 Check for gzip/brotli compression
echo -e "  ${CYAN}1.5 压缩文件检查${NC}"

GZ_COUNT=$(find "$BUILD_DIR" -name "*.gz" 2>/dev/null | wc -l | tr -d ' ')
BR_COUNT=$(find "$BUILD_DIR" -name "*.br" 2>/dev/null | wc -l | tr -d ' ')

if [[ "$GZ_COUNT" -gt 0 ]]; then
  echo -e "    ${GREEN}✅${NC} 预压缩文件: Gzip=${BOLD}${GZ_COUNT}${NC}"
else
  echo -e "    ${YELLOW}🟡${NC} 未检测到预压缩 Gzip 文件"
fi

if [[ "$BR_COUNT" -gt 0 ]]; then
  echo -e "    ${GREEN}✅${NC} 预压缩文件: Brotli=${BOLD}${BR_COUNT}${NC}"
else
  echo -e "    ${YELLOW}🟡${NC} 未检测到预压缩 Brotli 文件"
fi
echo ""

# ── 2. Lighthouse Verification / Lighthouse 验证 ──────────
if [[ "$RUN_LIGHTHOUSE" == true ]]; then
  echo -e "${CYAN}${BOLD}▶ Lighthouse 性能验证${NC}"
  echo -e "${BLUE}────────────────────────────────────────${NC}"
  echo ""

  # Check if lighthouse is available
  LIGHTHOUSE_CMD=""
  if command -v lighthouse &>/dev/null; then
    LIGHTHOUSE_CMD="lighthouse"
  elif npx lighthouse --version &>/dev/null 2>&1; then
    LIGHTHOUSE_CMD="npx lighthouse"
  else
    echo -e "  ${YELLOW}⚠️ 未安装 lighthouse，尝试临时安装...${NC}"
    if npm install -g lighthouse &>/dev/null 2>&1; then
      LIGHTHOUSE_CMD="lighthouse"
    else
      echo -e "  ${RED}❌ 无法安装 lighthouse，跳过 Lighthouse 验证${NC}"
      echo -e "     手动安装: ${MAGENTA}npm install -g lighthouse${NC}"
    fi
  fi

  if [[ -n "$LIGHTHOUSE_CMD" ]]; then
    # Start a temporary HTTP server for Lighthouse
    TEMP_PORT=9876
    SERVER_PID=""

    # Try to find a free port
    while lsof -i :$TEMP_PORT &>/dev/null; do
      TEMP_PORT=$((TEMP_PORT + 1))
    done

    # Start HTTP server
    echo -e "  ${CYAN}启动临时 HTTP 服务 (端口 ${TEMP_PORT})...${NC}"

    if command -v python3 &>/dev/null; then
      python3 -m http.server "$TEMP_PORT" --directory "$BUILD_DIR" &>/dev/null &
      SERVER_PID=$!
    elif command -v python &>/dev/null; then
      python -m SimpleHTTPServer "$TEMP_PORT" &>/dev/null &
      SERVER_PID=$!
    elif command -v npx &>/dev/null; then
      npx serve "$BUILD_DIR" -l "$TEMP_PORT" &>/dev/null &
      SERVER_PID=$!
    else
      echo -e "  ${RED}❌ 无法启动临时 HTTP 服务${NC}"
      echo ""
      exit 1
    fi

    # Wait for server to start
    sleep 2

    # Run Lighthouse
    LH_OUTPUT="/tmp/lh-report-$$.json"
    echo -e "  ${CYAN}运行 Lighthouse...${NC}"

    $LIGHTHOUSE_CMD "http://localhost:$TEMP_PORT" \
      --chrome-flags="--headless --no-sandbox --disable-gpu" \
      --output=json \
      --output-path="$LH_OUTPUT" \
      --only-categories=performance \
      --preset=desktop \
      2>/dev/null || {
        echo -e "  ${YELLOW}⚠️ Lighthouse 运行失败，可能 Chrome 未安装${NC}"
        # Cleanup server
        if [[ -n "$SERVER_PID" ]]; then
          kill "$SERVER_PID" 2>/dev/null || true
        fi
        exit 0
      }

    # Stop server
    if [[ -n "$SERVER_PID" ]]; then
      kill "$SERVER_PID" 2>/dev/null || true
      wait "$SERVER_PID" 2>/dev/null || true
    fi

    # Parse Lighthouse results
    if [[ -f "$LH_OUTPUT" ]]; then
      echo -e "  ${GREEN}✅ Lighthouse 报告生成成功${NC}"
      echo ""

      # Extract scores using node
      if command -v node &>/dev/null; then
        node -e "
          const fs = require('fs');
          const data = JSON.parse(fs.readFileSync('$LH_OUTPUT', 'utf8'));

          const scores = {
            performance: Math.round(data.categories?.performance?.score * 100 || 0),
            lcp: data.audits?.['largest-contentful-paint']?.displayValue || 'N/A',
            lcp_score: data.audits?.['largest-contentful-paint']?.score || 0,
            cls: data.audits?.['cumulative-layout-shift']?.displayValue || 'N/A',
            cls_score: data.audits?.['cumulative-layout-shift']?.score || 0,
            tbt: data.audits?.['total-blocking-time']?.displayValue || 'N/A',
            tbt_score: data.audits?.['total-blocking-time']?.score || 0,
            fcp: data.audits?.['first-contentful-paint']?.displayValue || 'N/A',
            si: data.audits?.['speed-index']?.displayValue || 'N/A',
          };

          console.log(JSON.stringify(scores));
        " 2>/dev/null > "/tmp/lh-scores-$$.json"

        if [[ -f "/tmp/lh-scores-$$.json" ]]; then
          SCORES=$(cat "/tmp/lh-scores-$$.json")

          perf_score=$(echo "$SCORES" | node -e "console.log(JSON.parse(require('fs').readFileSync(0, 'utf8')).performance)")
          lcp=$(echo "$SCORES" | node -e "console.log(JSON.parse(require('fs').readFileSync(0, 'utf8')).lcp)")
          cls=$(echo "$SCORES" | node -e "console.log(JSON.parse(require('fs').readFileSync(0, 'utf8')).cls)")
          tbt=$(echo "$SCORES" | node -e "console.log(JSON.parse(require('fs').readFileSync(0, 'utf8')).tbt)")
          fcp=$(echo "$SCORES" | node -e "console.log(JSON.parse(require('fs').readFileSync(0, 'utf8')).fcp)")
          si=$(echo "$SCORES" | node -e "console.log(JSON.parse(require('fs').readFileSync(0, 'utf8')).si)")

          # Colorize score
          if [[ "$perf_score" -ge 90 ]]; then
            PERF_COLOR="${GREEN}"
          elif [[ "$perf_score" -ge 50 ]]; then
            PERF_COLOR="${YELLOW}"
          else
            PERF_COLOR="${RED}"
          fi

          echo -e "  ${BOLD}┌──────────────────────────────────────────────┐${NC}"
          echo -e "  ${BOLD}│           Lighthouse 性能评分                │${NC}"
          echo -e "  ${BOLD}├──────────────────────────────────────────────┤${NC}"
          echo -e "  ${BOLD}│  Performance  │  ${PERF_COLOR}${perf_score}${NC}/100${NC}               │${NC}"
          echo -e "  ${BOLD}│  LCP          │  ${lcp}                        │${NC}"
          echo -e "  ${BOLD}│  CLS          │  ${cls}                          │${NC}"
          echo -e "  ${BOLD}│  TBT          │  ${tbt}                        │${NC}"
          echo -e "  ${BOLD}│  FCP          │  ${fcp}                        │${NC}"
          echo -e "  ${BOLD}│  Speed Index  │  ${si}                        │${NC}"
          echo -e "  ${BOLD}└──────────────────────────────────────────────┘${NC}"
          echo ""

          # Verification verdict
          echo -e "  ${CYAN}${BOLD}验证结论:${NC}"
          if [[ "$perf_score" -ge 90 ]]; then
            echo -e "    ${GREEN}✅ 性能优秀${NC} (评分 ≥90)"
          elif [[ "$perf_score" -ge 50 ]]; then
            echo -e "    ${YELLOW}🟡 性能一般${NC} (评分 50-89)，建议继续优化"
          else
            echo -e "    ${RED}🔴 性能较差${NC} (评分 <50)，需要重点优化"
          fi

          rm -f "/tmp/lh-scores-$$.json"
        fi
      else
        echo -e "  ${YELLOW}⚠️ 未安装 Node.js，无法解析 Lighthouse JSON${NC}"
      fi

      rm -f "$LH_OUTPUT"
    else
      echo -e "  ${YELLOW}⚠️ Lighthouse 报告未生成${NC}"
    fi
  fi
else
  echo -e "  ${CYAN}ℹ️  跳过 Lighthouse 验证（添加 --lighthouse 启用）${NC}"
fi

echo ""
echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║                  诊断后验证完成 ✓                           ║${NC}"
echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
