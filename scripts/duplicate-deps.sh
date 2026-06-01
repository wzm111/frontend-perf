#!/bin/bash
# 重复依赖检测脚本
# 检测 lock 文件中同一库的多个版本

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

echo -e "${CYAN}${BOLD}📋 重复依赖检测${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ──────────────────────────────────────────
# 1. package-lock.json analysis
# ──────────────────────────────────────────
if [[ -f "package-lock.json" ]]; then
  echo -e "${CYAN}${BOLD}▶ package-lock.json 分析${NC}"

  # Extract packages and versions using node
  if command -v node &> /dev/null; then
    node -e "
      const fs = require('fs');
      const lock = JSON.parse(fs.readFileSync('package-lock.json', 'utf8'));
      const packages = lock.packages || {};
      const versions = {};

      for (const [path, info] of Object.entries(packages)) {
        if (!info.name || path === '') continue;
        const name = info.name;
        const version = info.version;
        if (!versions[name]) versions[name] = new Set();
        versions[name].add(version);
      }

      const duplicates = Object.entries(versions)
        .filter(([name, vers]) => vers.size > 1)
        .sort((a, b) => b[1].size - a[1].size);

      if (duplicates.length === 0) {
        console.log('  ✅ 未检测到重复依赖');
      } else {
        console.log('  🔴 检测到以下重复依赖:\\n');
        duplicates.forEach(([name, vers]) => {
          const versArray = Array.from(vers).sort();
          console.log('  📦 ' + name);
          console.log('     版本: ' + versArray.join(', '));
          // Check if major versions differ
          const majors = versArray.map(v => v.split('.')[0]).filter(m => !isNaN(m));
          const uniqueMajors = [...new Set(majors)];
          if (uniqueMajors.length > 1) {
            console.log('     ⚠️  主版本号不同，可能导致兼容性问题');
          }
          console.log('');
        });
      }
    " 2>/dev/null || echo -e "  ${YELLOW}Node.js 解析失败，使用备用方法${NC}"
  fi

  # Fallback: grep-based detection
  if ! command -v node &> /dev/null; then
    echo -e "  ${YELLOW}使用文本分析方法...${NC}"
    # For lockfileVersion 2/3, check packages
    if grep -q '"packages"' package-lock.json; then
      grep -oE '"node_modules/[^"]+":\s*\{[^}]*"version"\s*:\s*"[^"]+"' package-lock.json 2>/dev/null | \
        grep -oE 'node_modules/[^"]+|version"\s*:\s*"[^"]+"' | \
        paste - - | sort | uniq -c | sort -rn | while read -r count pkg_ver; do
        if [[ "$count" -gt 1 ]]; then
          pkg=$(echo "$pkg_ver" | cut -f1)
          echo -e "  ${YELLOW}🟡${NC} ${pkg} 出现 ${count} 次"
          ISSUES_COUNT=$((ISSUES_COUNT + 1))
        fi
      done
    fi
  fi

  echo ""
fi

# ──────────────────────────────────────────
# 2. yarn.lock analysis
# ──────────────────────────────────────────
if [[ -f "yarn.lock" ]]; then
  echo -e "${CYAN}${BOLD}▶ yarn.lock 分析${NC}"

  # Extract package names and versions
  awk '/^[^"\/#@].*@[^@]*$/{pkg=$0} /^version /{print pkg, $0}' yarn.lock 2>/dev/null | \
    sed 's/@.*$//' | sort | uniq -c | sort -rn | while read -r count pkg_ver; do
    if [[ "$count" -gt 1 ]]; then
      pkg=$(echo "$pkg_ver" | awk '{print $1}')
      vers=$(echo "$pkg_ver" | awk '{print $3}')
      echo -e "  ${YELLOW}🟡${NC} ${pkg}: ${count} 个版本 (${vers})"
      ISSUES_COUNT=$((ISSUES_COUNT + 1))
    fi
  done

  if [[ "$ISSUES_COUNT" -eq 0 ]]; then
    echo -e "  ${GREEN}✅ 未检测到重复依赖${NC}"
  fi

  echo ""
fi

# ──────────────────────────────────────────
# 3. pnpm-lock.yaml analysis
# ──────────────────────────────────────────
if [[ -f "pnpm-lock.yaml" ]]; then
  echo -e "${CYAN}${BOLD}▶ pnpm-lock.yaml 分析${NC}"

  # pnpm lock format is different, try basic detection
  if command -v node &> /dev/null; then
    node -e "
      try {
        const fs = require('fs');
        const content = fs.readFileSync('pnpm-lock.yaml', 'utf8');
        // Simple regex-based extraction for pnpm lockfile
        const pkgRegex = /(\/[^@\n]+)@([^:\n]+):/g;
        const versions = {};
        let match;
        while ((match = pkgRegex.exec(content)) !== null) {
          const name = match[1].replace(/^\//, '');
          const version = match[2];
          if (!versions[name]) versions[name] = new Set();
          versions[name].add(version);
        }
        const duplicates = Object.entries(versions).filter(([n, v]) => v.size > 1);
        if (duplicates.length === 0) {
          console.log('  ✅ 未检测到重复依赖');
        } else {
          console.log('  🔴 检测到重复依赖:\\n');
          duplicates.forEach(([name, vers]) => {
            console.log('  📦 ' + name + ': ' + Array.from(vers).sort().join(', '));
          });
        }
      } catch (e) {
        console.log('  ⚠️ 解析失败: ' + e.message);
      }
    " 2>/dev/null || echo -e "  ${YELLOW}Node.js 解析失败${NC}"
  else
    echo -e "  ${YELLOW}未安装 Node.js，无法解析 pnpm-lock.yaml${NC}"
  fi

  echo ""
fi

# ──────────────────────────────────────────
# 4. Common problematic duplicates
# ──────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ 常见重复依赖检查${NC}"

COMMON_DUPES=("react" "react-dom" "@types/react" "typescript" "webpack" "lodash" "@babel/runtime" "core-js")

for dup in "${COMMON_DUPES[@]}"; do
  count=0

  if [[ -f "package-lock.json" ]]; then
    count=$(grep -c "\"${dup}\"" package-lock.json 2>/dev/null || echo 0)
  elif [[ -f "yarn.lock" ]]; then
    count=$(grep -c "^${dup}@" yarn.lock 2>/dev/null || echo 0)
  elif [[ -f "pnpm-lock.yaml" ]]; then
    count=$(grep -c "/${dup}@" pnpm-lock.yaml 2>/dev/null || echo 0)
  fi

  if [[ "$count" -gt 2 ]]; then
    echo -e "  ${YELLOW}🟡${NC} ${dup} 在 lock 文件中出现 ${count} 次 (可能重复)"
    ISSUES_COUNT=$((ISSUES_COUNT + 1))
  fi
done

echo ""

# ──────────────────────────────────────────
# 5. Resolution fix suggestions
# ──────────────────────────────────────────
if [[ "$ISSUES_COUNT" -gt 0 ]]; then
  echo -e "${CYAN}${BOLD}▶ 修复建议${NC}"
  echo ""
  echo -e "  ${CYAN}npm (package.json overrides):${NC}"
  echo -e "  ${MAGENTA}\"overrides\": {${NC}"
  echo -e "  ${MAGENTA}  \"react\": \"^18.0.0\",${NC}"
  echo -e "  ${MAGENTA}  \"react-dom\": \"^18.0.0\",${NC}"
  echo -e "  ${MAGENTA}  \"lodash\": \"^4.17.21\"${NC}"
  echo -e "  ${MAGENTA}}${NC}"
  echo ""
  echo -e "  ${CYAN}Yarn (package.json resolutions):${NC}"
  echo -e "  ${MAGENTA}\"resolutions\": {${NC}"
  echo -e "  ${MAGENTA}  \"react\": \"^18.0.0\",${NC}"
  echo -e "  ${MAGENTA}  \"react-dom\": \"^18.0.0\"${NC}"
  echo -e "  ${MAGENTA}}${NC}"
  echo ""
  echo -e "  ${CYAN}pnpm (package.json pnpm.overrides):${NC}"
  echo -e "  ${MAGENTA}\"pnpm\": {${NC}"
  echo -e "  ${MAGENTA}  \"overrides\": {${NC}"
  echo -e "  ${MAGENTA}    \"react\": \"^18.0.0\"${NC}"
  echo -e "  ${MAGENTA}  }${NC}"
  echo -e "  ${MAGENTA}}${NC}"
  echo ""
  echo -e "  执行 ${YELLOW}npm ls <package>${NC} 或 ${YELLOW}yarn why <package>${NC} 查看重复原因"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "重复依赖检测完成，发现问题: ${BOLD}${ISSUES_COUNT}${NC}"
