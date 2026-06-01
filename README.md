# Frontend Performance Diagnostic / 前端性能诊断助手

> 自动检测前端项目的 Core Web Vitals 问题、Bundle 体积、代码分割、重复依赖和资源优化，提供可执行的修复建议。

## Quick Start / 快速开始

### Claude Code 中使用（推荐）

```text
# 基础诊断
/frontend-perf

# 诊断 + 生成修复建议
/frontend-perf --fix

# 诊断 + 验证构建产物
/frontend-perf --verify

# 诊断 + 启动预览服务
/frontend-perf --serve

# 完整流程：诊断 → 验证 → 预览
/frontend-perf --verify --serve

# 专项诊断
/frontend-perf check bundle      # Bundle 分析
/frontend-perf check CWV         # Core Web Vitals
/frontend-perf check splitting   # 代码分割

# 高级功能
/frontend-perf --json            # 生成 JSON 报告
/frontend-perf --watch           # 监视模式自动诊断
/frontend-perf --monorepo        # Monorepo 全包诊断
```

> 💡 **Claude Code 斜杠命令不支持原生参数传递**。通过在 `SKILL.md` 中配置**自然语言意图映射**，AI 会自动理解您的需求并调用对应脚本。

### 直接执行脚本

```bash
# 1. 克隆 skill 到 Claude Code skills 目录
git clone https://github.com/wzm111/frontend-perf.git ~/.claude/skills/frontend-perf

# 2. 在项目目录下执行诊断
bash ~/.claude/skills/frontend-perf/scripts/frontend-perf.sh

# 3. 诊断 + 验证 + 预览（完整流程）
bash scripts/frontend-perf.sh . --verify --serve

# 4. 诊断特定目录
bash scripts/frontend-perf.sh /path/to/project

# 5. 带修复建议模式
bash scripts/frontend-perf.sh . --fix

# 6. JSON 报告
bash scripts/frontend-perf.sh . --json

# 7. 监视模式（文件变化自动重新诊断）
bash scripts/frontend-perf.sh . --watch --interval 5

# 8. Monorepo 全包诊断
bash scripts/frontend-perf.sh . --monorepo

# 9. 自定义配置文件
bash scripts/frontend-perf.sh . --config .frontend-perf.yml
```

---

## Features / 核心能力

### 1. Core Web Vitals 检查
- **LCP (Largest Contentful Paint)**
  - 检测缺少 `width`/`height` 的图片（导致 CLS 和延迟 LCP）
  - 检测首屏图片误用 `loading="lazy"`
  - 检测阻塞渲染的 CSS/JS（缺少 `async`/`defer`）
  - 未优化的首屏大图（>100KB 无 WebP/AVIF）

- **INP (Interaction to Next Paint)**
  - `useLayoutEffect` 中的阻塞性计算
  - 链式数组操作阻塞主线程
  - 第三方脚本阻塞

- **CLS (Cumulative Layout Shift)**
  - `@font-face` 缺少 `font-display`
  - `iframe`/`embed` 缺少尺寸
  - 未预留空间的动态内容

### 2. Bundle 分析
- **大依赖检测**：自动标记 `lodash`、`moment`、`jquery` 等重包
- **替代建议**：`lodash → lodash-es`、`moment → dayjs`、`axios → fetch`
- **Import 模式检查**：全量导入 vs 按需导入
- **构建产物体积**：自动检测 >500KB 的 JS 文件

### 3. 代码分割检查
- **路由懒加载**：检测 `React.lazy`、`next/dynamic`、Vue `() => import()`
- **组件级别动态导入**：检测重型组件（>20KB）
- **构建配置检查**：Vite `manualChunks`、Webpack `splitChunks`、Next.js `optimizePackageImports`

### 4. 重复依赖检测
- 解析 `package-lock.json`、`yarn.lock`、`pnpm-lock.yaml`
- 检测同一库的多个版本（尤其是主版本不同）
- 提供 `overrides`/`resolutions` 修复方案

### 5. 资源优化
- **图片**：大图片检测、缺少 `srcset`、WebP/AVIF 替代格式
- **字体**：大字体检测、`font-display: swap`、预加载
- **CSS**：PurgeCSS 检查、关键 CSS 提取、styled-components 优化
- **视频**：>5MB 视频检测

---

### 6. 诊断后验证
- **产物解析验证**：解析构建产物确认 tree-shaking 是否生效（检测 lodash/moment 是否仍残留）
- **代码分割验证**：确认 chunk 文件是否正确生成
- **脚本加载策略验证**：确认 HTML 中脚本是否使用 async/defer/module
- **图片格式验证**：确认产物中是否存在 WebP/AVIF 格式
- **Lighthouse 跑分**：启动临时服务运行 Lighthouse，获取真实 LCP/CLS/TBT/FCP 分数

### 7. 本地预览服务
- **自动检测 HTTP 服务器**：serve / python3 / python2 / Node.js 内置，按优先级自动选择
- **端口自动切换**：默认 3456，被占用时自动递增
- **SPA 回退**：未知路由自动返回 index.html
- **集成 Lighthouse**：`--lighthouse` 参数启动服务后自动跑分
- **完整报告输出**：Performance / Accessibility / Best Practices / SEO 四项评分
- **优雅退出**：Ctrl+C 停止服务

---

## Usage / 使用方法

### Claude Code
- **手动调用**：输入 `/frontend-perf`
- **自动触发**：打开 `vite.config.ts`、`next.config.js` 等构建配置文件时自动激活
- **指定目录**：`/frontend-perf analyze my-project/`

### 命令行执行

```bash
# 完整诊断
cd /path/to/project
bash ~/.claude/skills/frontend-perf/scripts/frontend-perf.sh

# 诊断 + 验证 + 预览（完整流程）
bash scripts/frontend-perf.sh . --verify --serve

# 诊断 + 验证（构建后运行）
bash scripts/frontend-perf.sh . --verify

# 仅启动预览服务
bash scripts/frontend-perf.sh . --serve

# 单项检查
bash scripts/core-web-vitals.sh .          # 仅 CWV
bash scripts/bundle-analyzer.sh .          # 仅 Bundle
bash scripts/code-splitting.sh .           # 仅代码分割
bash scripts/duplicate-deps.sh .           # 仅重复依赖
bash scripts/resource-optimizer.sh .       # 仅资源优化

# 诊断后验证
bash scripts/post-verify.sh .              # 仅产物解析验证
bash scripts/post-verify.sh . --lighthouse # 产物解析 + Lighthouse

# 启动预览服务
bash scripts/preview-server.sh .                    # 仅启动服务
bash scripts/preview-server.sh . --lighthouse       # 服务 + Lighthouse
bash scripts/preview-server.sh . --lighthouse --port 8080  # 指定端口

# JSON 报告
bash scripts/frontend-perf.sh . --json              # 生成 frontend-perf-report.json
bash scripts/json-aggregator.sh . report.json       # 指定输出文件名

# 监视模式
bash scripts/watch-mode.sh .                        # 默认 5 秒间隔
bash scripts/watch-mode.sh . --interval 3           # 3 秒间隔

# Monorepo 诊断
bash scripts/frontend-perf.sh . --monorepo          # 诊断所有 workspace packages
```

---

## Architecture / 架构

```
frontend-perf/
├── .frontend-perf.yml                   # 配置文件模板
├── SKILL.md                             # Claude Code Skill 入口
├── README.md                            # 文档
└── scripts/
    ├── frontend-perf.sh                 # 主入口（全部检查 + 验证 + 预览）
    ├── config-loader.sh                 # 配置文件加载器
    ├── json-aggregator.sh               # JSON 报告聚合器
    ├── watch-mode.sh                    # 监视模式
    ├── core-web-vitals.sh               # Core Web Vitals 诊断
    ├── bundle-analyzer.sh               # Bundle 分析 + 依赖优化
    ├── code-splitting.sh                # 代码分割检查
    ├── duplicate-deps.sh                # 重复依赖检测
    ├── resource-optimizer.sh            # 资源优化诊断
    ├── post-verify.sh                   # 诊断后验证（产物解析 + Lighthouse）
    └── preview-server.sh                # 本地预览服务 + Lighthouse
```

---

## Supported Frameworks / 支持框架

| 框架 | 检测特征 | 专项检查 |
|------|---------|---------|
| **Next.js** | `next.config.*` | `next/dynamic`, `next/image`, `optimizePackageImports` |
| **Vite** | `vite.config.*` | `manualChunks`, `rollupOptions`, `minify` |
| **Nuxt** | `nuxt.config.*` | 路由懒加载, NuxtImg |
| **Angular** | `angular.json` | `loadChildren`, budgets |
| **Astro** | `astro.config.*` | Islands, client directives |
| **Remix** | `remix.config.*` | Route-level splitting |
| **SvelteKit** | `svelte.config.*` | 动态导入 |
| **Webpack** | `webpack.config.*` | `splitChunks`, BundleAnalyzerPlugin |

---

## Output Format / 输出格式

```
## 📊 Performance Diagnosis Summary
- **Project**: React + Vite
- **Overall Score**: C
- **Issues Found**: 3 Critical, 2 Warning, 1 Suggestion

## 🔴 Critical Issues
- [src/App.tsx:1] [Bundle] Full lodash import (~70KB)
  Fix: import { debounce } from 'lodash-es'
  Estimated saving: ~65KB

## 🟡 Warnings
- [src/App.tsx:10] [CLS] Image missing width/height

## 💡 Optimizations
- [vite.config.ts] Missing manualChunks config

## ✅ Already Optimized
- No render-blocking scripts detected
```

---

## Auto-Fix / 自动修复

### 导入替换
```diff
- import _ from 'lodash';
+ import { debounce } from 'lodash-es';

- import moment from 'moment';
+ import dayjs from 'dayjs';
```

### 图片优化
```diff
- <img src="hero.jpg" alt="Hero" />
+ <img
+   src="hero.webp"
+   width="800"
+   height="600"
+   loading="lazy"
+   alt="Hero"
+ />
```

### 动态导入
```diff
- import { BigChart } from './BigChart';
+ const BigChart = lazy(() => import('./BigChart'));
```

### 构建配置
```typescript
// vite.config.ts
export default defineConfig({
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          'vendor-react': ['react', 'react-dom'],
          'vendor-ui': ['@mui/material'],
        },
      },
    },
  },
});
```

---

## Priority Matrix / 优先级矩阵

| Priority | Category | Impact | Effort |
|---------|---------|--------|--------|
| P0 | Full lodash/moment import | High | Low |
| P0 | Images without dimensions | High | Low |
| P1 | Missing code splitting | High | Medium |
| P1 | Large dependencies | Medium | Low |
| P2 | Missing WebP/AVIF | Medium | Low |
| P2 | Font optimization | Low | Low |
| P3 | Critical CSS extraction | Medium | High |

---

## Heavy Package Replacements / 大依赖替换表

| 🔴 Heavy | ✅ Replacement | Size Saving |
|---------|---------------|-------------|
| `lodash` | `lodash-es` / `es-toolkit` | ~65KB |
| `moment` | `dayjs` / `date-fns` | ~230KB |
| `jquery` | Vanilla JS | ~85KB |
| `axios` | Native `fetch` / `ky` | ~13KB |
| `uuid` | `crypto.randomUUID()` | ~12KB |
| `echarts` (full) | `echarts/core` + modules | ~200KB |
| `highlight.js` | `highlight.js/lib/core` | ~100KB |
| `chart.js` | Tree-shaken imports | ~50KB |
| `jsdom` | Remove from browser bundle | ~200KB |

---

## Configuration / 配置文件

在项目根目录创建 `.frontend-perf.yml` 自定义诊断规则：

```yaml
thresholds:
  maxBundleSize: 500000      # 最大 JS Bundle 体积（字节）
  maxImageSize: 102400       # 最大单张图片体积（字节）
  maxVideoSize: 5242880      # 最大单个视频体积（字节）
  maxCssSize: 102400         # 最大单个 CSS 文件体积（字节）
  lcp: 2500                  # LCP 阈值（毫秒）
  inp: 200                   # INP 阈值（毫秒）
  cls: 0.1                   # CLS 阈值
  ttfb: 600                  # TTFB 阈值（毫秒）

rules:
  ignore:
    - src/legacy/**
    - test/**
    - **/*.test.ts
  customReplacements:
    - from: old-heavy-lib
      to: new-light-lib
```

---

## JSON Report / JSON 报告

使用 `--json` 参数生成结构化 JSON 报告，便于 CI 解析和自动化处理：

```bash
bash scripts/frontend-perf.sh . --json
```

输出文件：`frontend-perf-report.json`

```json
{
  "generatedAt": "2024-01-15T10:30:00Z",
  "project": "my-app",
  "framework": "React + Vite",
  "summary": {
    "score": "B",
    "total_issues": 8,
    "critical": 2,
    "warning": 6
  },
  "issues": [
    {
      "severity": "critical",
      "category": "Bundle",
      "file": "src/App.tsx",
      "line": 1,
      "message": "Full lodash import",
      "fix": "import { debounce } from 'lodash-es'"
    }
  ]
}
```

---

## Watch Mode / 监视模式

使用 `--watch` 参数启动监视模式，源码变化时自动重新诊断：

```bash
# 默认 5 秒检查间隔
bash scripts/frontend-perf.sh . --watch

# 自定义间隔
bash scripts/frontend-perf.sh . --watch --interval 3
```

依赖工具优先级：`fswatch` (macOS) → `inotifywait` (Linux) → 轮询降级

---

## Monorepo Support / Monorepo 支持

使用 `--monorepo` 参数自动检测并诊断所有 workspace packages：

```bash
bash scripts/frontend-perf.sh . --monorepo
```

支持的 workspace 类型：

| 类型  | 检测文件                    | 说明                                      |
|-------|-----------------------------|-------------------------------------------|
| pnpm  | `pnpm-workspace.yaml`       | 最优先检测                                |
| npm   | `package.json` workspaces   | 检测 package.json 中的 workspaces 字段    |
| lerna | `lerna.json`                | 兼容 lerna 项目                           |

---

## CI/CD Integration / CI 集成

`frontend-perf` 是纯 CLI 工具，可在任意 CI/CD 平台集成。以下为常见平台的配置示例：

### GitHub Actions

```yaml
name: Frontend Performance Diagnosis
on:
  pull_request:
    branches: [main, master]
jobs:
  perf:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npm ci
      - run: npm run build
      - run: |
          git clone --depth 1 https://github.com/wzm111/frontend-perf.git /tmp/frontend-perf
          bash /tmp/frontend-perf/scripts/frontend-perf.sh . --json --verify
      - uses: actions/upload-artifact@v4
        with:
          name: perf-report
          path: frontend-perf-report.json
```

### GitLab CI

```yaml
frontend-perf:
  stage: test
  image: node:20
  script:
    - npm ci
    - npm run build
    - git clone --depth 1 https://github.com/wzm111/frontend-perf.git /tmp/frontend-perf
    - bash /tmp/frontend-perf/scripts/frontend-perf.sh . --json
  artifacts:
    paths:
      - frontend-perf-report.json
```

### 阿里云云效 / 腾讯云 Coding / 通用 Shell

```bash
# 在构建阶段后执行
npm run build

# 安装诊断工具
git clone --depth 1 https://github.com/wzm111/frontend-perf.git /tmp/frontend-perf

# 运行诊断 + JSON 报告
bash /tmp/frontend-perf/scripts/frontend-perf.sh . --json --verify

# 上传报告到构建产物（各平台命令不同）
# 阿里云: 云效自动收集 frontend-perf-report.json
# 腾讯云 Coding: 在 artifacts 中配置
```

### Jenkins

```groovy
stage('Performance Diagnosis') {
  steps {
    sh 'npm run build'
    sh 'git clone --depth 1 https://github.com/wzm111/frontend-perf.git /tmp/frontend-perf'
    sh 'bash /tmp/frontend-perf/scripts/frontend-perf.sh . --json'
    archiveArtifacts artifacts: 'frontend-perf-report.json'
  }
}
```

---

## License / 许可证

MIT
