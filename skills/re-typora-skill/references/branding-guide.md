# 品牌替换安全指南

## 可以安全修改的内容

这些修改只影响用户看到的文本，不涉及内部逻辑：

### P0 - 核心元数据
| 文件 | 修改内容 | 示例 |
|------|---------|------|
| `resources/package.json` | name, author, homepage, concat | `"name": "Typola"` |
| `resources/window.html` | `<title>`, `<span id="title-text">` | `<title>Typola</title>` |
| `resources/conf.default.json` | URL 引用 | `https://support.typola.io/...` |

### P1 - 本地化文件 (~151 处引用)
| 路径模式 | 文件 | 修改内容 |
|----------|------|---------|
| `resources/locales/*/Front.json` | 39 个 | "Typora" → "Typola" |
| `resources/locales/*/Menu.json` | 39 个 | "Typora" → "Typola" |
| `resources/locales/*/Panel.json` | 39 个 | "Typora" → "Typola" |
| `resources/locales/*/Welcome.json` | 39 个 | "Typora" → "Typola" |

URL 替换规则：
- `typora.io` → `typola.io`
- `support.typora.io` → `support.typola.io`
- `theme.typora.io` → `theme.typola.io`
- `hi@typora.io` → `hi@typola.io`

### P2 - 页面和脚本
| 文件 | 修改范围 |
|------|---------|
| `page-dist/*.html` | 用户可见文本 |
| `html/content.html` | 用户可见文本 |
| `html/preview.html` | 标题文本 |
| `appsrc/finder-worker.js` | 用户可见字符串 (不改函数名) |
| `appsrc/window/frame.js` | 用户可见字符串 (不改函数名) |
| `plugin/**/*.js` | console.log / 横幅 / 菜单项中的 "Typora" |
| `plugin/*/package.json` | 元数据字段 |
| `copilot/package.json` | name, description |
| `Docs/*.md` | 文档全部文本 |

---

## 绝对不能修改的内容

### 1. `typora://` 协议 URL
- **使用位置**: window.html, page-dist/*.html, appsrc/window/frame.js, style/*.css
- **注册位置**: main.node (C++ 原生代码)
- **作用**: 加载 app.asar 内部资源 (CSS, JS, 字体)
- **修改后果**: 所有内部资源加载失败 → 应用白屏

示例 (不可修改)：
```html
<link rel="stylesheet" href="typora://app/typemark/lib.asar/bootstrape/css/bootstrap.css">
<link rel="stylesheet" href="typora://app/userData/themes/current-theme.css">
<link rel="stylesheet" href="typora-bg://bg.css">
```

### 2. `ty-` CSS 类名前缀
- **使用位置**: window.html, 所有 CSS 文件, JS DOM 操作
- **作用**: 全局 UI 组件样式
- **修改后果**: 全部样式失效 → 界面混乱

示例 (不可修改)：
```css
.ty-tooltip { }
.ty-icon { }
.ty-search-item { }
.ty-tab-wrapper { }
```

### 3. DOM 元素 ID
- **使用位置**: window.html, JS 代码中 `document.querySelector()`
- **作用**: JS 代码通过这些 ID 查找和操作 DOM 元素
- **修改后果**: `querySelector("#typora-sidebar")` 返回 null → JS 报错 → 功能失效

示例 (不可修改)：
```html
<div id="typora-sidebar">
<div id="typora-quick-open">
<div id="typora-source">
<div id="typora-caret">
<script id="typora-uploading-image-templ">
```

### 4. JavaScript 函数/变量名
- **使用位置**: appsrc/*.js, plugin/**/*.js
- **作用**: 代码逻辑引用
- **修改后果**: `ReferenceError: typoraVersion is not defined`

示例 (不可修改)：
```javascript
var typoraOptionPrefix = /^--tyopt=/;  // CLI 参数解析
var canOpenByTypora = function() {};    // 文件类型判断
utils.typoraVersion                     // 版本检测
this.utils.exitTypora()                 // 退出应用
```

### 5. `--tyopt=` CLI 参数
- **使用位置**: window.html, content.html, main.node
- **作用**: 从命令行传递配置选项到渲染进程
- **修改后果**: 命令行参数解析失败 → 配置无法传递

### 6. atom.js 加密内容
- **位置**: app.asar/atom.js
- **状态**: AES-256-CBC 加密 + Base64 编码
- **内容**: Electron 主进程完整逻辑
- **修改前提**: 必须先完成完整的解密→修改→重加密流程
- **修改后果 (未正确重加密)**: 应用完全无法启动

---

## 经验总结

1. **品牌替换的本质是区分"皮肤"和"骨架"** — 用户看到的是皮肤，`typora://` 和 `ty-` 是骨架
2. **main.node 中的字符串不要动** — 虽然长度相同，但影响面太广（协议、注册表、内部标识）
3. **package.json 的 name 字段决定用户数据目录** — 改为 Typola 后数据自动存到 `%APPDATA%/Typola/`
4. **先表面后深度** — 先做 HTML/locale 替换验证可用，再考虑 atom.js 解密深度替换
5. **保持一致性** — 如果只改了 asar 内的 main.node 但没改 unpacked 的，修改无效
