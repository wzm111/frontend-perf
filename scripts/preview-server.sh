#!/bin/bash
# Preview Server / 本地预览服务
# 启动 HTTP 服务预览构建产物，支持集成 Lighthouse 验证
#
# Usage: preview-server.sh [dir] [--lighthouse] [--port PORT]

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
PORT=3456

cd "$TARGET_DIR"

# Parse arguments
for ((i=1; i<=$#; i++)); do
  arg="${!i}"
  if [[ "$arg" == "--lighthouse" || "$arg" == "-l" ]]; then
    RUN_LIGHTHOUSE=true
  elif [[ "$arg" == "--port" || "$arg" == "-p" ]]; then
    next=$((i+1))
    if [[ $next -le $# ]]; then
      PORT="${!next}"
    fi
  fi
done

# ── Detect build output directory ─────────────────────────
BUILD_DIRS=("dist" "build" ".next" "out" ".output")
BUILD_DIR=""
BUILD_TYPE="static"

for dir in "${BUILD_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    BUILD_DIR="$dir"
    break
  fi
done

# Special handling for Next.js .next
if [[ -d ".next" ]]; then
  BUILD_DIR=".next"
  BUILD_TYPE="next"
  # Check if static export exists
  if [[ -d ".next/static" ]]; then
    BUILD_DIR=".next"
  fi
fi

if [[ -z "$BUILD_DIR" ]]; then
  echo -e "${RED}错误: 未找到构建产物目录${NC}"
  echo -e "请先运行构建命令: npm run build"
  exit 1
fi

# ── Header ────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║          🌐 本地预览服务 / Preview Server                    ║${NC}"
echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Find available HTTP server ────────────────────────────
SERVER_CMD=""
SERVER_ARGS=""
SERVER_NAME=""

# Priority: serve > python3 > python2 > node built-in
if command -v serve &>/dev/null; then
  SERVER_CMD="serve"
  SERVER_ARGS="$BUILD_DIR -l $PORT -s"
  SERVER_NAME="serve"
elif npx serve --version &>/dev/null 2>&1; then
  SERVER_CMD="npx"
  SERVER_ARGS="serve $BUILD_DIR -l $PORT -s"
  SERVER_NAME="npx serve"
elif command -v python3 &>/dev/null; then
  SERVER_CMD="python3"
  SERVER_ARGS="-m http.server $PORT --directory $BUILD_DIR"
  SERVER_NAME="python3 http.server"
elif command -v python &>/dev/null; then
  SERVER_CMD="python"
  if python -c "import http.server" &>/dev/null 2>&1; then
    SERVER_ARGS="-m http.server $PORT --directory $BUILD_DIR"
    SERVER_NAME="python http.server"
  else
    SERVER_ARGS="-m SimpleHTTPServer $PORT"
    SERVER_NAME="python SimpleHTTPServer"
  fi
fi

# Fallback: built-in node server
if [[ -z "$SERVER_CMD" ]]; then
  if command -v node &>/dev/null; then
    # Create a temporary node server script
    cat > "/tmp/frontend-perf-server-$$.js" <<'NODESERVER'
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.FP_PORT || 3456;
const ROOT = process.env.FP_DIR || 'dist';

const MIME_TYPES = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.mjs': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.webp': 'image/webp',
  '.avif': 'image/avif',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.eot': 'application/vnd.ms-fontobject',
  '.wasm': 'application/wasm',
};

const server = http.createServer((req, res) => {
  let filePath = path.join(ROOT, req.url === '/' ? 'index.html' : req.url);

  // Try SPA fallback for non-API routes
  if (!fs.existsSync(filePath) && !req.url.startsWith('/api')) {
    const altPath = path.join(ROOT, 'index.html');
    if (fs.existsSync(altPath)) {
      filePath = altPath;
    }
  }

  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
      return;
    }
    res.writeHead(200, {
      'Content-Type': contentType,
      'Cache-Control': 'no-cache',
    });
    res.end(data);
  });
});

server.listen(PORT, () => {
  console.log(`Server running at http://localhost:${PORT}/`);
});

// Handle graceful shutdown
process.on('SIGINT', () => {
  console.log('\nShutting down server...');
  server.close(() => process.exit(0));
});
process.on('SIGTERM', () => {
  server.close(() => process.exit(0));
});
NODESERVER
    SERVER_CMD="node"
    SERVER_ARGS="/tmp/frontend-perf-server-$$.js"
    SERVER_NAME="Node.js built-in"
    export FP_PORT="$PORT"
    export FP_DIR="$BUILD_DIR"
  else
    echo -e "${RED}错误: 未找到可用的 HTTP 服务器${NC}"
    echo -e "请安装以下任一项:"
    echo -e "  ${MAGENTA}npm install -g serve${NC}"
    echo -e "  ${MAGENTA}Python 3 (自带 http.server)${NC}"
    echo -e "  ${MAGENTA}Node.js (备用方案)${NC}"
    exit 1
  fi
fi

# ── Check port availability ───────────────────────────────
if lsof -i :$PORT &>/dev/null; then
  echo -e "  ${YELLOW}⚠️ 端口 $PORT 已被占用${NC}"
  # Find next available port
  ORIG_PORT=$PORT
  while lsof -i :$PORT &>/dev/null; do
    PORT=$((PORT + 1))
  done
  echo -e "  ${YELLOW}→ 自动切换到端口 $PORT${NC}"

  # Update server args with new port
  if [[ "$SERVER_NAME" == "serve" || "$SERVER_NAME" == "npx serve" ]]; then
    SERVER_ARGS="${SERVER_ARGS//$ORIG_PORT/$PORT}"
  elif [[ "$SERVER_NAME" == "python3 http.server" || "$SERVER_NAME" == "python http.server" ]]; then
    SERVER_ARGS="${SERVER_ARGS//$ORIG_PORT/$PORT}"
  elif [[ "$SERVER_NAME" == "python SimpleHTTPServer" ]]; then
    SERVER_ARGS="${SERVER_ARGS//$ORIG_PORT/$PORT}"
  elif [[ "$SERVER_NAME" == "Node.js built-in" ]]; then
    export FP_PORT="$PORT"
  fi
fi

# ── Show info ─────────────────────────────────────────────
echo -e "  ${BLUE}产物目录:${NC} ${BOLD}$BUILD_DIR${NC}"
echo -e "  ${BLUE}框架类型:${NC} ${BOLD}$BUILD_TYPE${NC}"
echo -e "  ${BLUE}服务工具:${NC} ${BOLD}$SERVER_NAME${NC}"
echo -e "  ${BLUE}访问地址:${NC} ${BOLD}${GREEN}http://localhost:$PORT/${NC}"
echo ""

# ── Start server ──────────────────────────────────────────
echo -e "  ${CYAN}正在启动预览服务...${NC}"
echo ""

# Start server in background
if [[ "$SERVER_NAME" == "Node.js built-in" ]]; then
  export FP_PORT="$PORT"
  export FP_DIR="$BUILD_DIR"
fi

$SERVER_CMD $SERVER_ARGS &
SERVER_PID=$!

# Wait for server to be ready
sleep 2

# Check if server is running
if ! kill -0 $SERVER_PID 2>/dev/null; then
  echo -e "  ${RED}❌ 服务启动失败${NC}"
  exit 1
fi

echo -e "  ${GREEN}✅ 服务已启动!${NC}"
echo -e "  ${GREEN}   访问: http://localhost:$PORT/${NC}"
echo ""

# ── Lighthouse check ──────────────────────────────────────
if [[ "$RUN_LIGHTHOUSE" == true ]]; then
  echo -e "  ${CYAN}${BOLD}▶ 运行 Lighthouse...${NC}"
  echo ""

  # Check lighthouse availability
  LIGHTHOUSE_CMD=""
  if command -v lighthouse &>/dev/null; then
    LIGHTHOUSE_CMD="lighthouse"
  elif npx lighthouse --version &>/dev/null 2>&1; then
    LIGHTHOUSE_CMD="npx lighthouse"
  else
    echo -e "  ${YELLOW}⚠️ 未安装 lighthouse，尝试安装...${NC}"
    if npm install -g lighthouse &>/dev/null 2>&1; then
      LIGHTHOUSE_CMD="lighthouse"
      echo -e "  ${GREEN}✅ lighthouse 安装成功${NC}"
    else
      echo -e "  ${YELLOW}⚠️ 跳过 Lighthouse${NC}"
      LIGHTHOUSE_CMD=""
    fi
  fi

  if [[ -n "$LIGHTHOUSE_CMD" ]]; then
    LH_OUTPUT="/tmp/lh-preview-$$.json"
    LH_HTML="/tmp/lh-preview-$$.html"

    # Wait a bit more for server to fully start
    sleep 1

    $LIGHTHOUSE_CMD "http://localhost:$PORT/" \
      --chrome-flags="--headless --no-sandbox --disable-gpu" \
      --output=json,html \
      --output-path="/tmp/lh-preview-$$" \
      --only-categories=performance,accessibility,best-practices,seo \
      --preset=desktop \
      2>/dev/null || {
        echo -e "  ${YELLOW}⚠️ Lighthouse 运行失败${NC}"
        echo -e "     可能原因: Chrome 未安装、页面加载超时"
    }

    if [[ -f "$LH_OUTPUT" ]]; then
      echo -e "  ${GREEN}✅ Lighthouse 报告生成${NC}"

      if command -v node &>/dev/null; then
        node -e "
          const fs = require('fs');
          const data = JSON.parse(fs.readFileSync('$LH_OUTPUT', 'utf8'));

          function score(v) {
            const s = Math.round((v || 0) * 100);
            if (s >= 90) return '\x1b[32m' + s + '\x1b[0m';
            if (s >= 50) return '\x1b[33m' + s + '\x1b[0m';
            return '\x1b[31m' + s + '\x1b[0m';
          }

          const perf = data.categories?.performance?.score;
          const a11y = data.categories?.accessibility?.score;
          const bp = data.categories?.['best-practices']?.score;
          const seo = data.categories?.seo?.score;
          const lcp = data.audits?.['largest-contentful-paint']?.displayValue;
          const cls = data.audits?.['cumulative-layout-shift']?.displayValue;
          const tbt = data.audits?.['total-blocking-time']?.displayValue;
          const fcp = data.audits?.['first-contentful-paint']?.displayValue;
          const si = data.audits?.['speed-index']?.displayValue;

          console.log('  ┌──────────────────────────────────────────────────┐');
          console.log('  │           Lighthouse 完整报告                     │');
          console.log('  ├──────────────────────────────────────────────────┤');
          console.log('  │  Performance      │  ' + score(perf) + '/100' + '                     │');
          console.log('  │  Accessibility    │  ' + score(a11y) + '/100' + '                     │');
          console.log('  │  Best Practices   │  ' + score(bp) + '/100' + '                     │');
          console.log('  │  SEO              │  ' + score(seo) + '/100' + '                     │');
          console.log('  ├──────────────────────────────────────────────────┤');
          console.log('  │  LCP              │  ' + (lcp || 'N/A') + '                        │');
          console.log('  │  CLS              │  ' + (cls || 'N/A') + '                          │');
          console.log('  │  TBT              │  ' + (tbt || 'N/A') + '                        │');
          console.log('  │  FCP              │  ' + (fcp || 'N/A') + '                        │');
          console.log('  │  Speed Index      │  ' + (si || 'N/A') + '                        │');
          console.log('  └──────────────────────────────────────────────────┘');
        "
      fi

      echo ""
      echo -e "  ${CYAN}报告文件:${NC}"
      echo -e "    JSON: ${MAGENTA}$LH_OUTPUT${NC}"
      if [[ -f "$LH_HTML" ]]; then
        echo -e "    HTML: ${MAGENTA}$LH_HTML${NC}"
      fi
      echo ""

      # Cleanup
      rm -f "$LH_OUTPUT" "$LH_HTML"
    fi
  fi
fi

# ── Server status ─────────────────────────────────────────
echo -e "  ${CYAN}${BOLD}▶ 服务状态${NC}"
echo -e "  ${GREEN}✅${NC} 预览服务运行中: ${BOLD}http://localhost:$PORT/${NC}"
echo ""
echo -e "  ${YELLOW}按 Ctrl+C 停止服务${NC}"
echo ""

# Wait for user interrupt
trap 'echo ""; echo -e "  ${CYAN}正在停止服务...${NC}"; kill $SERVER_PID 2>/dev/null || true; wait $SERVER_PID 2>/dev/null || true; echo -e "  ${GREEN}✅ 服务已停止${NC}"; echo ""; rm -f /tmp/frontend-perf-server-$$.js; exit 0' INT TERM

wait $SERVER_PID
