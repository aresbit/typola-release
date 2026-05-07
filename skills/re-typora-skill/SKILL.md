---
name: re-typora-skill
description: Reverse-engineer and rebrand Typora (Electron Markdown editor) to a new brand name. Covers app.asar extraction/packing, main.node hex-patching, atom.js AES-256-CBC decryption, safe vs unsafe string replacement rules, 7-Zip SFX installer creation, and macOS-to-Linux cross-platform conversion. Use this skill whenever the user wants to rebrand Typora, fork Typora, reverse engineer an Electron app, decrypt atom.js, patch main.node, create a Typora-based custom editor, or port a macOS Electron app to Linux.
compatibility: Windows, Linux, macOS — requires node 20+, npx, 7-Zip 24.09+, python3
---

# Typora → Rebrand Reverse Engineering Skill

逆向工程与品牌替换 Typora Electron 应用的完整方法论。核心理念：**Typora 是层层加密的 Electron 应用，品牌替换需要精确理解哪些可以改、哪些改了会炸。**

## 架构概览

```
Typora.exe (Electron runtime, renamed)
└── resources/
    ├── app.asar              ← Electron 归档 (包含 atom.js, main.node, package.json)
    ├── app.asar.unpacked/    ← 原生模块提取目录
    │   └── main.node         ← **实际加载的** C++ 原生模块 (PE32 DLL)
    ├── window.html           ← 主窗口 UI (可安全修改用户可见文本)
    ├── page-dist/            ← Vite 构建的页面产物
    ├── locales/              ← 39 种语言的本地化文件
    ├── plugin/               ← 插件系统 (terminal, copilot, etc.)
    ├── appsrc/               ← 未压缩的源代码 (frame.js, finder-worker.js)
    ├── html/                 ← 编辑器 iframe 内容 (content.html, preview.html)
    ├── style/                ← CSS 样式表
    └── copilot/              ← GitHub Copilot 集成
```

## 核心规则：安全与不安全的替换

### 可以安全修改（仅用户可见文本）
这些修改只影响用户看到的文字，不涉及内部逻辑：
- `window.html` 中的 `<title>`、标题栏 `<span id="title-text">`
- `package.json` 元数据：name, author, homepage, concat
- `conf.default.json` 中的 URL 引用
- 所有 `locales/*/` JSON 文件中的品牌名和 URL
- `page-dist/*.html` 页面中的可见文本
- `copilot/package.json` 元数据
- `Docs/*.md` 文档文件
- `plugin/**/*.js` 中 `console.log("Typora")` 等可见字符串

### 绝对不能修改（修改会破坏应用）
这些都是内部架构标识符，改了会导致功能异常或应用崩溃：

1. **`typora://` 协议 URL** — 由 main.node 注册的自定义协议，window.html 和所有页面通过它加载资源。修改 main.node 中的协议名 → 所有 `typora://app/...` 引用全部失效 → 应用白屏
2. **`ty-` CSS 类名前缀** — 全局 CSS 选择器依赖
3. **DOM IDs** — `typora-sidebar`, `typora-quick-open`, `typora-source` 等，JS 代码通过 ID 查找元素
4. **JS 函数/变量名** — `typoraVersion`, `exitTypora()`, `canOpenByTypora()` 等
5. **`--tyopt=` CLI 参数** — 由 main.node 解析的命令行参数
6. **atom.js 加密内容** — 主进程核心逻辑，修改需走完整解密→修改→重加密流程

> 详细清单见 `references/branding-guide.md`

## 关键技能领域

### 1. app.asar 操作

```bash
# 提取
npx asar extract app.asar <output_dir>

# 列出内容
npx asar list app.asar

# 重新打包
npx asar pack <input_dir> app.asar --unpack "{*.node,*.so,*.dylib}"
```

**关键陷阱**：`app.asar.unpacked/` 中的原生模块 (.node) 是 **Electron 实际加载的版本**。asar 内的同名文件仅作为占位符。修改原生模块必须同时修改 unpacked 版本。

### 2. main.node 逆向

main.node 是编译的 C++ Node.js 原生模块 (PE32 DLL on Windows)。包含单一的 `"typora"` 字符串，控制：
- 自定义协议注册 (`typora://`)
- 注册表键名 (`HKCU\Software\Typora`)
- 可能的其他内部标识符

```bash
# 查找 typora 字符串
strings main.node | grep -i typora

# 精确定位偏移量
hexdump -C main.node | grep typora

# 比较两个 main.node 的差异
cmp -l main1.node main2.node
```

Hex-patch 规则：
- 必须保持字符串长度不变（"typora" → "typola" 同为 6 字节，可替换）
- **警告**：修改此字符串会改变协议注册名 → 所有 `typora://` URL 失效 → 应用无法加载资源
- 经验结论：**不要修改 main.node 中的 "typora" 字符串**，品牌信息通过 package.json 和 HTML 控制

### 3. atom.js 加密系统

atom.js 是 Electron 主进程的核心 JavaScript 文件，包含：
- 窗口管理和菜单创建
- 自定义协议注册 (`protocol.registerFileProtocol`)
- 激活/许可证验证
- Sentry 错误上报
- 自动更新检查
- IPC 通信处理

atom.js 存储在 app.asar 中，经过 **AES-256-CBC 加密 + Base64 编码**：
- 密钥和 IV 计算逻辑在 main.node 的编译代码中
- 解密需逆向 main.node 获取密钥派生算法
- 可以从 main.node 中提取密钥，或通过 hex-patch 跳过解密步骤直接执行明文 JS

```bash
# 检查 atom.js 是否为加密内容 (base64 编码的头部特征)
head -c 100 atom.js | xxd
```

> 详细流程见 `references/atomjs-crypto.md`

### 4. 7-Zip SFX 安装包制作

用于创建 Windows 自解压安装程序：

```bash
# Step 1: 创建 config.txt
cat > config.txt << 'EOF'
;!@Install@!UTF-8!
Title="MyApp 1.0.0 Setup"
BeginPrompt="Welcome to MyApp Setup. Install to the selected folder?"
ExtractPathText="Select installation folder:"
ExtractDialogText="MyApp Setup"
GUIFlags="8+32+64+256+4096"
CancelPrompt="Cancel installation?"
FinishMessage="MyApp has been installed."
RunProgram="scripts\\setup.bat"
;!@InstallEnd@!
EOF

# Step 2: 创建 7z 归档
7z a -t7z -m0=lzma2 -mx=9 -mhe=on archive.7z ./app-folder/ -xr!*.bak -xr!.git*

# Step 3: 拼接 SFX
cat "C:/Program Files/7-Zip/7z.sfx" config.txt archive.7z > Setup-MyApp.exe
```

**注意事项**：
- 排除 `.bak` 文件和 `.git` 目录
- RunProgram 在提取后从提取目录执行
- 使用 `7z l Setup.exe` 验证内容

### 5. macOS → Linux 转换

基于 macos2linuxapp 技能的经验：

```bash
# 从 DMG 提取 (需要 7zz 24.09+, 旧版无法处理 APFS DMG)
7zz x App.dmg

# 提取 app.asar
npx asar extract "App.app/Contents/Resources/app.asar" app-extracted

# 为目标平台重建原生模块
npx @electron/rebuild -v <ELECTRON_VERSION> --force

# 移除 macOS 专有模块
rm -rf app-extracted/node_modules/sparkle-darwin

# Linux UI 适配：动态检测 path 变量名
# 不要硬编码 t.join，Vite 压缩后变量名会变化
pathVarMatch = source.match(/\blet\s+([A-Za-z_$][\w$]*)=require\(`(?:node:)?path`\)/)

# 修复透明窗口闪烁 (Linux 不支持 vibrancy)
# dark mode: backgroundColor → '#000000'
# light mode: backgroundColor → '#f9f9f9'
```

> 详细流程见 `references/cross-platform.md`

## 调试与验证

```
# 用户数据目录 (由 package.json name 决定)
%APPDATA%/{app.name}/

# 日志文件
%APPDATA%/{app.name}/typora.log

# 注册表路径 (由 main.node 写入)
HKCU\Software\{app.name}

# 验证主进程日志
tail -f %APPDATA%/Typola/typora.log

# 检查协议引用
grep -r "typora://" resources/ --include="*.html" --include="*.js"

# 验证 asar 完整性
npx asar list resources/app.asar

# 检查 SFX 内容
7z l Setup-App.exe

# 运行时错误：检查 typora.log 中的 ERROR 行
grep ERROR %APPDATA%/Typola/typora.log
```

## 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| 应用白屏/资源加载失败 | 修改了 main.node 中的 "typora" 字符串 | 恢复原始 main.node，品牌信息通过 HTML/package.json 控制 |
| `render process is killed` | JS 错误或资源 404 | 检查 window.html 中的 typora:// 协议引用未被修改 |
| 窗口透明闪烁 (Linux) | 原应用使用 macOS vibrancy | patch backgroundColor 为不透明色 |
| `Cannot find module` | asar 打包不完整 | 重新从原始 DMG/安装提取 |
| 原生模块加载失败 | .node 文件与平台不匹配 | 使用 @electron/rebuild 为目标平台编译 |
| SFX 安装后不运行 | RunProgram 路径错误或 setup.bat 权限问题 | 检查 SFX config 中 RunProgram 路径和脚本语法 |
