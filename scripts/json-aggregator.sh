#!/bin/bash
# JSON Report Aggregator / JSON 报告聚合器
# 收集各诊断脚本的输出，生成结构化 JSON 报告
# Usage: json-aggregator.sh [target_dir] [output_file]

set -euo pipefail

TARGET_DIR="${1:-.}"
OUTPUT_FILE="${2:-frontend-perf-report.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Detect framework ──────────────────────
cd "$TARGET_DIR"
FRAMEWORK=""
BUILD_TOOL=""
[[ -f "next.config.js" || -f "next.config.ts" || -f "next.config.mjs" ]] && FRAMEWORK="Next.js"
[[ -f "nuxt.config.ts" || -f "nuxt.config.js" ]] && FRAMEWORK="Nuxt"
[[ -f "vite.config.ts" || -f "vite.config.js" ]] && BUILD_TOOL="Vite"
[[ -f "webpack.config.js" || -f "webpack.config.ts" ]] && BUILD_TOOL="Webpack"
[[ -f "astro.config.mjs" || -f "astro.config.ts" ]] && FRAMEWORK="Astro"
[[ -f "angular.json" ]] && FRAMEWORK="Angular"
[[ -f "svelte.config.js" ]] && FRAMEWORK="SvelteKit"
[[ -f "remix.config.js" || -f "remix.config.ts" ]] && FRAMEWORK="Remix"

PKG_NAME=""
if [[ -f "package.json" ]]; then
  PKG_NAME=$(node -e "console.log(require('./package.json').name || '')" 2>/dev/null || echo "")
fi

# ── Collect issues from each script ───────
ISSUES=""
ISSUE_COUNT=0

add_issue() {
  local severity="$1"
  local category="$2"
  local file="$3"
  local line="$4"
  local message="$5"
  local fix="${6:-}"

  # Escape for JSON
  message=$(echo "$message" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')
  fix=$(echo "$fix" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')

  if [[ "$ISSUE_COUNT" -gt 0 ]]; then
    ISSUES="${ISSUES},"
  fi

  ISSUES="${ISSUES}{\n    \"severity\": \"$severity\",\n    \"category\": \"$category\",\n    \"file\": \"$file\",\n    \"line\": $line,\n    \"message\": \"$message\""

  if [[ -n "$fix" ]]; then
    ISSUES="${ISSUES},\n    \"fix\": \"$fix\""
  fi

  ISSUES="${ISSUES}\n  }"
  ISSUE_COUNT=$((ISSUE_COUNT + 1))
}

# ── Run core-web-vitals and parse ─────────
CWV_OUTPUT=$(bash "$SCRIPT_DIR/core-web-vitals.sh" "$TARGET_DIR" 2>/dev/null || true)

# Parse CWV issues from output
# Pattern: emoji [Category] file:line message
while IFS= read -r line; do
  # Match: 🔴 [CLS/LCP] path/to/file:lineno message
  if echo "$line" | grep -qE '\[CLS\]|\[LCP\]|\[INP\]'; then
    severity="warning"
    if echo "$line" | grep -q '🔴'; then
      severity="critical"
    fi

    file_line=$(echo "$line" | grep -oE '[^[:space:]]+:[0-9]+' | head -1)
    file_path="${file_line%:*}"
    line_no="${file_line##*:}"
    line_no=${line_no:-0}
    message=$(echo "$line" | sed 's/^.*\]//' | sed 's/内容:.*$//' | sed 's/^ *//')

    category=$(echo "$line" | grep -oE '\[[A-Z]+\]' | tr -d '[]' | head -1)

    add_issue "$severity" "$category" "$file_path" "$line_no" "$message"
  fi
done <<< "$CWV_OUTPUT"

# ── Run bundle-analyzer and parse ─────────
BUNDLE_OUTPUT=$(bash "$SCRIPT_DIR/bundle-analyzer.sh" "$TARGET_DIR" 2>/dev/null || true)

while IFS= read -r line; do
  if echo "$line" | grep -qE '\[Bundle\]'; then
    severity="warning"
    if echo "$line" | grep -q '🔴'; then
      severity="critical"
    fi

    file_line=$(echo "$line" | grep -oE '[^[:space:]]+:[0-9]+' | head -1)
    file_path="${file_line%:*}"
    line_no="${file_line##*:}"
    line_no=${line_no:-0}
    message=$(echo "$line" | sed 's/^.*\[Bundle\]//' | sed 's/修复:.*$//' | sed 's/^ *//')
    fix=$(echo "$line" | grep -oE '修复:.*$' | sed 's/修复://' | sed 's/^ *//')

    add_issue "$severity" "Bundle" "$file_path" "$line_no" "$message" "$fix"
  elif echo "$line" | grep -q '已安装.*体积大'; then
    pkg=$(echo "$line" | grep -oE '[^[:space:]]+ 已安装' | sed 's/ 已安装//')
    add_issue "warning" "Bundle" "package.json" 0 "$pkg is installed (heavy dependency)"
  fi
done <<< "$BUNDLE_OUTPUT"

# ── Run code-splitting and parse ──────────
SPLIT_OUTPUT=$(bash "$SCRIPT_DIR/code-splitting.sh" "$TARGET_DIR" 2>/dev/null || true)

while IFS= read -r line; do
  if echo "$line" | grep -qE '\[Code Split\]'; then
    file_line=$(echo "$line" | grep -oE '[^[:space:]]+:[0-9]+' | head -1)
    file_path="${file_line%:*}"
    line_no="${file_line##*:}"
    line_no=${line_no:-0}
    message=$(echo "$line" | sed 's/^.*\[Code Split\]//' | sed 's/^ *//')
    add_issue "warning" "CodeSplit" "$file_path" "$line_no" "$message"
  fi
done <<< "$SPLIT_OUTPUT"

# ── Run duplicate-deps and parse ──────────
DUPES_OUTPUT=$(bash "$SCRIPT_DIR/duplicate-deps.sh" "$TARGET_DIR" 2>/dev/null || true)

while IFS= read -r line; do
  if echo "$line" | grep -q '检测到.*重复'; then
    add_issue "warning" "DuplicateDeps" "lock file" 0 "Duplicate dependencies detected"
  fi
done <<< "$DUPES_OUTPUT"

# ── Run resource-optimizer and parse ──────
RESOURCE_OUTPUT=$(bash "$SCRIPT_DIR/resource-optimizer.sh" "$TARGET_DIR" 2>/dev/null || true)

while IFS= read -r line; do
  if echo "$line" | grep -qE '\[Image\]|\[Font\]|\[CSS\]'; then
    severity="warning"
    if echo "$line" | grep -q '🔴'; then
      severity="critical"
    fi
    category=$(echo "$line" | grep -oE '\[[A-Za-z]+\]' | tr -d '[]' | head -1)
    file_line=$(echo "$line" | grep -oE '[^[:space:]]+:[0-9]+' | head -1)
    file_path="${file_line%:*}"
    line_no="${file_line##*:}"
    line_no=${line_no:-0}
    message=$(echo "$line" | sed 's/^.*\]'// | sed 's/^ *//')
    add_issue "$severity" "$category" "$file_path" "$line_no" "$message"
  fi
done <<< "$RESOURCE_OUTPUT"

# ── Calculate score ───────────────────────
CRITICAL_COUNT=$(echo "$ISSUES" | grep -c '"severity": "critical"' || echo 0)
WARNING_COUNT=$(echo "$ISSUES" | grep -c '"severity": "warning"' || echo 0)

SCORE="A"
if [[ "$CRITICAL_COUNT" -gt 3 || "$WARNING_COUNT" -gt 10 ]]; then
  SCORE="D"
elif [[ "$CRITICAL_COUNT" -gt 1 || "$WARNING_COUNT" -gt 5 ]]; then
  SCORE="C"
elif [[ "$CRITICAL_COUNT" -gt 0 || "$WARNING_COUNT" -gt 2 ]]; then
  SCORE="B"
fi

# ── Build JSON ────────────────────────────
cat > "$OUTPUT_FILE" <<JSON
{
  "generatedAt": "$TIMESTAMP",
  "project": "$PKG_NAME",
  "framework": "$FRAMEWORK",
  "build_tool": "$BUILD_TOOL",
  "summary": {
    "score": "$SCORE",
    "total_issues": $ISSUE_COUNT,
    "critical": $CRITICAL_COUNT,
    "warning": $WARNING_COUNT
  },
  "issues": [
$ISSUES
  ]
}
JSON

echo "JSON report generated: $OUTPUT_FILE"
