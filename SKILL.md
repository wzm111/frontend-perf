---
name: frontend-perf
description: Frontend performance diagnostic assistant. Detects Core Web Vitals issues, bundle bloat, missing code splitting, duplicate dependencies, and unoptimized assets. Supports Vite, Next.js, Webpack, Rollup, and Nuxt. Auto-activates on /frontend-perf or when build configs (vite.config.ts, next.config.js, webpack.config.js, etc.) are detected. Provides prioritized fix list with auto-fix patches.
user-invocable: true
---

# Frontend Performance Diagnostic / 前端性能诊断助手

## Purpose
Diagnose frontend performance issues with actionable fixes. Focus on Core Web Vitals (LCP, INP, CLS), bundle size, code splitting, duplicate dependencies, and asset optimization.

## When to Activate
- User types `/frontend-perf`
- User asks for "frontend perf check", "check my bundle", "analyze performance"
- Build config files detected: `vite.config.*`, `next.config.*`, `webpack.config.*`, `rollup.config.*`, `nuxt.config.*`, `astro.config.*`, `remix.config.*`
- Package manager lock files detected alongside frontend source files
- User asks about "performance", "bundle size", "lazy loading", "CLS", "LCP", "web vitals"

## Slash Command Parameter Mapping / 斜杠命令参数映射

Claude Code slash commands don't accept CLI-style arguments. Instead, infer the user's intent from their message and pass the equivalent flags to the script.

| User Says / 用户说 | Maps To / 映射为 | Script Call |
|---|---|---|
| `/frontend-perf` | 基础诊断 | `bash scripts/frontend-perf.sh .` |
| `/frontend-perf check bundle` | Bundle 分析 | `bash scripts/bundle-analyzer.sh .` |
| `/frontend-perf check CWV` | Core Web Vitals | `bash scripts/core-web-vitals.sh .` |
| `/frontend-perf --fix` / "fix my code" | 诊断 + 生成修复补丁 | `bash scripts/frontend-perf.sh . --fix` |
| `/frontend-perf --verify` / "verify after build" | 诊断 + 产物验证 | `bash scripts/frontend-perf.sh . --verify` |
| `/frontend-perf --serve` / "start preview" | 诊断 + 启动预览 | `bash scripts/frontend-perf.sh . --serve` |
| `/frontend-perf --verify --serve` / "full check with preview" | 诊断 + 验证 + 预览 | `bash scripts/frontend-perf.sh . --verify --serve` |
| `/frontend-perf --json` / "generate report" | 输出 JSON 报告 | `bash scripts/frontend-perf.sh . --json` |
| `/frontend-perf --watch` / "watch mode" | 监视模式自动诊断 | `bash scripts/frontend-perf.sh . --watch` |
| `/frontend-perf --monorepo` / "check all packages" | Monorepo 全包诊断 | `bash scripts/frontend-perf.sh . --monorepo` |
| "check my code splitting" | 代码分割 | `bash scripts/code-splitting.sh .` |
| "check duplicate dependencies" | 重复依赖 | `bash scripts/duplicate-deps.sh .` |
| "optimize my assets" | 资源优化 | `bash scripts/resource-optimizer.sh .` |
| "run lighthouse" / "get lighthouse score" | 启动预览 + Lighthouse | `bash scripts/preview-server.sh . --lighthouse` |

**Implementation rule:** When user invokes `/frontend-perf` followed by any descriptive text, parse the intent and append corresponding flags to the script call. Never tell the user to type bash commands manually — execute them via the shell tool.

## Tech Stack Detection

| 检测特征 | 框架/构建工具 | 专项检查 |
|---------|-------------|---------|
| `vite.config.*` / `vitest.config.*` | Vite | Vite-specific splitChunks, manualChunks, build.rollupOptions |
| `next.config.*` | Next.js | Image optimization, SSR/TTFB, next/dynamic, @next/bundle-analyzer |
| `nuxt.config.*` | Nuxt | NuxtImg, lazy components, Nitro prerender |
| `webpack.config.*` / `craco.config.*` | Webpack / CRA | splitChunks optimization, BundleAnalyzerPlugin |
| `rollup.config.*` | Rollup | output.manualChunks, treeshake |
| `astro.config.*` | Astro | Islands architecture, client: directives |
| `remix.config.*` / `react-router.config.*` | Remix | Route-level code splitting, defer |
| `angular.json` | Angular | Lazy-loaded modules, budgets |
| `svelte.config.*` | SvelteKit | dynamic imports, adapter optimization |

## Diagnostic Dimensions

### 1. Core Web Vitals / 核心 Web 指标

**LCP (Largest Contentful Paint)**
- `<img>` without `loading="lazy"` for below-the-fold images (above-the-fold should NOT have lazy)
- `<img>` without explicit `width` + `height` (causes layout shift while loading)
- Hero/LCP images not preloaded via `<link rel="preload">`
- Render-blocking CSS/JS in `<head>` without `async`/`defer`/`module`
- Large unoptimized images (PNG/JPG > 100KB without WebP/AVIF fallback)

**INP (Interaction to Next Paint)**
- Long-running synchronous event handlers (> 50ms)
- `useEffect` / `useLayoutEffect` doing heavy computation without yielding
- Third-party scripts blocking main thread
- Missing `requestIdleCallback` / `scheduler.yield` for non-critical work

**CLS (Cumulative Layout Shift)**
- Images without `width`/`height` or CSS `aspect-ratio`
- Ads/embeds/iframes without reserved space
- Web fonts causing FOUT/FOIT (no `font-display: swap`)
- Content injected after initial render without placeholder

**TTFB (Time to First Byte)**
- Next.js / Nuxt pages without `getStaticProps`/`getServerSideProps` strategy analysis
- Missing CDN/edge configuration hints

### 2. Bundle Analysis / 构建产物分析

**Large Dependencies / 大体积依赖检测**
Flag known heavy packages and suggest lighter alternatives:

| 🔴 Heavy Package | ✅ Recommended Replacement | Size Saving |
|----------------|--------------------------|-------------|
| `lodash` (full) | `lodash-es` + named imports or `es-toolkit` | ~60KB |
| `moment` | `dayjs` or `date-fns` | ~230KB |
| `jquery` | Vanilla JS or modern framework | ~85KB |
| `@material-ui/core` | `@mui/material` (v5+) | ~30KB |
| `echarts` (full) | `echarts/core` + tree-shaken modules | ~200KB |
| `antd` (full) | `antd` + babel-plugin-import / unplugin | varies |
| `three` (full) | Tree-shaken `three` imports | varies |
| `axios` | Native `fetch` or `ky` | ~13KB |
| `uuid` | `crypto.randomUUID()` (native) | ~12KB |
| `core-js` (full) | `core-js-pure` + only needed polyfills | varies |
| `highlight.js` (full) | `highlight.js/lib/core` + langs | ~100KB |
| `@fortawesome/fontawesome-free` (CSS) | `@fortawesome/react-fontawesome` + individual | ~50KB |
| `chart.js` (full) | Tree-shaken imports | ~50KB |
| `jsdom` (browser bundle) | Should be server-only | ~200KB |

**Detection patterns in code:**
```typescript
// 🔴 Bad: Full import
import _ from 'lodash';
import moment from 'moment';

// ✅ Good: Named import from modular build
import { debounce } from 'lodash-es';
import dayjs from 'dayjs';
```

### 3. Code Splitting / 代码分割检查

**Route-Level Splitting**
- Check router config for lazy-loaded routes
- Vite/React: `React.lazy(() => import('./Page'))`
- Next.js: `dynamic(() => import('../components/Heavy'))`
- Vue: `() => import('./views/Page.vue')`
- Angular: `loadChildren: () => import('./module')`

**Component-Level Splitting**
- Heavy components (>100KB estimated) should use dynamic import
- Modal/drawer components that are rarely shown
- Below-the-fold components
- Third-party widgets (charts, maps, editors)

**Framework-Specific Checks**
- Vite: `build.rollupOptions.output.manualChunks` configuration
- Webpack: `optimization.splitChunks` configuration
- Next.js: `experimental.typedRoutes`, `reactCompiler`, `optimizePackageImports`

### 4. Duplicate Dependencies / 重复依赖检测

**Lock File Analysis**
- Parse `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml` for multiple versions of same package
- Flag when major versions differ (e.g., `lodash@3.x` + `lodash@4.x`)
- Common dupes: `react`, `react-dom`, `@types/react`, `typescript`, `webpack`

**Resolution**
```json
// package.json overrides / resolutions
{
  "overrides": {
    "lodash": "^4.17.21"
  },
  "resolutions": {
    "@types/react": "^18.0.0"
  }
}
```

### 5. Asset Optimization / 资源优化

**Images**
- Images > 50KB without `.webp`/`.avif` equivalent
- Missing `srcset` for responsive images
- SVGs without optimization (`svgo`)
- Icons as full PNG instead of SVG/icon font

**Fonts**
- Font files > 40KB (suggest subsetting)
- Missing `font-display: swap`
- Loading full font families when only weights 400/700 needed
- No `preload` for critical fonts

**CSS**
- Unused CSS (no PurgeCSS / unplugin-purge)
- Large CSS-in-JS runtime overhead (styled-components without babel plugin)
- Blocking render without `media` query or critical CSS extraction

## Output Format

Structure the diagnosis as:

```
## 📊 Performance Diagnosis Summary / 性能诊断摘要
- **Project**: (detected framework + build tool)
- **Overall Score**: (A/B/C/D based on issue count)
- **Issues Found**: X Critical, Y Warning, Z Suggestion

## 🔴 Critical Issues (Must Fix)
- [File:Line] [Category] Description + Auto-fix patch

## 🟡 Warnings (Should Fix)
- [File:Line] [Category] Description + Suggested fix

## 💡 Optimizations (Nice-to-Have)
- [File:Line] [Category] Description + Improvement idea

## ✅ Already Optimized (What's Done Well)
```

## Auto-Fix Mode (--fix)

When user requests auto-fixes or passes `--fix` flag, generate **ready-to-apply patches**:

### Fix Categories

**1. Import Replacement / 导入替换**
```diff
- import _ from 'lodash';
+ import debounce from 'lodash/debounce';
// or
+ import { debounce } from 'es-toolkit';
```

**2. Image Optimization / 图片优化**
```diff
- <img src="hero.png" alt="Hero" />
+ <img
+   src="hero.webp"
+   srcSet="hero-400.webp 400w, hero-800.webp 800w"
+   sizes="(max-width: 800px) 100vw, 800px"
+   width="800"
+   height="600"
+   loading="lazy"
+   alt="Hero"
+ />
```

**3. Dynamic Import / 动态导入**
```diff
- import HeavyChart from './HeavyChart';
+ const HeavyChart = dynamic(() => import('./HeavyChart'));
// or React.lazy / Vue async component
```

**4. Font Optimization / 字体优化**
```css
@font-face {
  font-family: 'MyFont';
  src: url('myfont.woff2') format('woff2');
  font-display: swap;
  unicode-range: U+4E00-9FFF; /* Subset for Chinese */
}
```

**5. Build Config / 构建配置**
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

## Priority Matrix

| Priority | Category | Impact | Effort |
|---------|---------|--------|--------|
| P0 🔴 | Duplicate React/Vue, Full lodash import | High | Low |
| P0 🔴 | Images without width/height (CLS) | High | Low |
| P1 🟡 | Missing code splitting on heavy components | High | Medium |
| P1 🟡 | Large dependencies (moment, full echarts) | Medium | Low |
| P2 🟢 | WebP/AVIF missing | Medium | Low |
| P2 🟢 | Font optimization | Low | Low |
| P3 🔵 | Critical CSS extraction | Medium | High |

## Scripts Integration

The skill can execute diagnostic scripts via the AI shell tool:

### Core Diagnosis Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/frontend-perf.sh` | Full diagnosis + optional verify/serve | `bash scripts/frontend-perf.sh [dir] [--fix] [--verify] [--serve]` |
| `scripts/core-web-vitals.sh` | CWV audit | `bash scripts/core-web-vitals.sh [dir]` |
| `scripts/bundle-analyzer.sh` | Bundle + dep analysis | `bash scripts/bundle-analyzer.sh [dir]` |
| `scripts/code-splitting.sh` | Splitting check | `bash scripts/code-splitting.sh [dir]` |
| `scripts/duplicate-deps.sh` | Duplicate deps | `bash scripts/duplicate-deps.sh [dir]` |
| `scripts/resource-optimizer.sh` | Asset optimization | `bash scripts/resource-optimizer.sh [dir]` |

### Post-Diagnosis Verification / 诊断后验证

| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/post-verify.sh` | Build artifact verification + Lighthouse | `bash scripts/post-verify.sh [dir] [--lighthouse]` |
| `scripts/preview-server.sh` | Local preview server + Lighthouse | `bash scripts/preview-server.sh [dir] [--lighthouse] [--port PORT]` |
| `scripts/json-aggregator.sh` | JSON report generator | `bash scripts/json-aggregator.sh [dir] [output.json]` |
| `scripts/watch-mode.sh` | Watch mode auto-diagnosis | `bash scripts/watch-mode.sh [dir] [--interval SEC]` |
| `scripts/config-loader.sh` | Config file parser | Internal use |

### CLI Usage Examples

```bash
# Full diagnosis + auto verify + serve
bash scripts/frontend-perf.sh . --verify --serve

# Diagnosis only
bash scripts/frontend-perf.sh .

# Diagnosis + verification (after build)
bash scripts/frontend-perf.sh . --verify

# Start preview server with Lighthouse
bash scripts/preview-server.sh . --lighthouse --port 8080

# Quick verification only
bash scripts/post-verify.sh . --lighthouse

# JSON report
bash scripts/frontend-perf.sh . --json

# Watch mode (auto re-diagnosis on file change)
bash scripts/frontend-perf.sh . --watch --interval 5

# Monorepo: diagnose all workspace packages
bash scripts/frontend-perf.sh . --monorepo

# Custom config file
bash scripts/frontend-perf.sh . --config .frontend-perf.yml
```

## Monorepo Support / Monorepo 支持

For monorepo projects (pnpm workspace, npm workspaces, lerna), use `--monorepo` to diagnose all workspace packages:

- Auto-detects `pnpm-workspace.yaml`, `lerna.json`, or `package.json` workspaces
- Runs full diagnosis on each package
- Generates per-package JSON reports when `--json` is used

## JSON Report / JSON 报告

Use `--json` to generate a structured JSON report (`frontend-perf-report.json`):

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

## Watch Mode / 监视模式

Use `--watch` to automatically re-run diagnosis when source files change:

- Supports `fswatch` (macOS), `inotifywait` (Linux), or polling fallback
- Configurable interval with `--interval SECONDS`
- Press Ctrl+C to exit

## CI/CD Integration / CI 集成

The included GitHub Actions workflow (`.github/workflows/frontend-perf.yml`) automatically:

- Runs on PR/push to src/ or config changes
- Installs dependencies and builds the project
- Runs full diagnosis with optional Lighthouse
- Posts results as PR comments
- Uploads JSON report as artifact

## Post-Diagnosis Verification / 诊断后验证

After static analysis, run actual verification on build artifacts:

### 1. Build Artifact Analysis
- Parse JS bundles to confirm tree-shaking effectiveness (check if lodash/moment code is actually removed)
- Verify code splitting produced actual chunk files
- Check HTML output for async/defer/module script loading
- Validate image optimization (WebP/AVIF presence in output)
- Check gzip/brotli pre-compression

### 2. Lighthouse Verification
- Start temporary HTTP server on a free port
- Run Lighthouse headless to get real performance scores
- Display formatted score table (Performance, Accessibility, Best Practices, SEO)
- Show CWV metrics: LCP, CLS, TBT, FCP, Speed Index
- Provide verdict: ✅ Pass / 🟡 Needs Work / 🔴 Critical

### 3. Preview Server
- Auto-detects available HTTP server (serve / python3 / python2 / node built-in)
- Auto-finds free port if default is taken
- Supports SPA fallback (serves index.html for unknown routes)
- Optional `--lighthouse` flag to run full Lighthouse report
- Graceful shutdown on Ctrl+C

## Rules

1. Always detect the build tool first (Vite/Next.js/Webpack/etc.) before making recommendations
2. Prioritize fixes by impact/effort ratio — low-hanging fruit first
3. Provide exact file:line references for every issue
4. For auto-fixes, generate copy-paste ready code blocks, not vague suggestions
5. Distinguish between framework-level configs and code-level changes
6. For Next.js images, recommend `<Image>` component over raw `<img>`
7. For Vite projects, recommend `vite-plugin-imagetools` for image optimization
8. Never suggest changes that break functionality (e.g., removing `defer` from critical scripts)
9. Flag when a "fix" would require additional tooling (e.g., installing `sharp` for image conversion)
10. Include size estimates when possible ("This change saves ~X KB")

## Example Diagnosis

### Input: React + Vite project with issues

```tsx
// src/App.tsx
import _ from 'lodash';
import moment from 'moment';
import { BigChart } from './components/BigChart';

function App() {
  const data = _.map(users, u => ({
    name: u.name,
    date: moment(u.createdAt).format('YYYY-MM-DD'),
  }));

  return (
    <div>
      <img src="/hero.jpg" alt="Hero" />
      <BigChart data={data} />
    </div>
  );
}
```

### Output:

```
## 📊 Performance Diagnosis Summary
- **Project**: React + Vite
- **Overall Score**: C (3 Critical, 2 Warning)

## 🔴 Critical Issues

1. [src/App.tsx:1] [Bundle] Full lodash import (~70KB gzip)
   Fix: Replace with `import { map } from 'lodash-es'` or `es-toolkit`
   Estimated saving: ~65KB

2. [src/App.tsx:2] [Bundle] moment is deprecated and heavy (~290KB)
   Fix: Replace with `dayjs` (~2KB)
   Auto-fix:
   ```diff
   - import moment from 'moment';
   + import dayjs from 'dayjs';
   - date: moment(u.createdAt).format('YYYY-MM-DD'),
   + date: dayjs(u.createdAt).format('YYYY-MM-DD'),
   ```

3. [src/App.tsx:10] [CLS] Image missing width/height
   Fix: Add explicit dimensions or aspect-ratio
   ```diff
   - <img src="/hero.jpg" alt="Hero" />
   + <img src="/hero.jpg" alt="Hero" width="1200" height="600" />
   ```

## 🟡 Warnings

4. [src/App.tsx:3] [Code Split] BigChart imported synchronously
   Fix: Use dynamic import
   ```diff
   - import { BigChart } from './components/BigChart';
   + const BigChart = lazy(() => import('./components/BigChart'));
   ```

5. [vite.config.ts] Missing manualChunks config
   Fix: Add vendor splitting

## ✅ Positive Notes
- No render-blocking scripts detected
- modern ES modules output detected
```
