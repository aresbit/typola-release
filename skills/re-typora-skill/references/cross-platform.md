# 跨平台转换参考 (macOS → Linux/Windows)

基于 macos2linuxapp 技能和 Typora 逆向经验的综合指南。

## macOS DMG → Linux 转换

### 前置条件
- Node.js 20+, npm/npx
- python3
- 7zz 24.09+ (旧版 p7zip 无法解压 APFS DMG)
- curl, unzip, make, g++
- Rust + cargo (若需要 updater 服务)

### 完整流程

```bash
# 1. 解压 DMG (需要 7zz 24.09+)
7zz x -y App.dmg

# 2. 提取 app.asar
npx asar extract "App.app/Contents/Resources/app.asar" app-extracted

# 3. 确认 Electron 版本 (从 DMG 中自带的 electron 可执行文件)
./App.app/Contents/MacOS/App --version

# 4. 为目标平台重建原生模块
cd app-extracted
npm install better-sqlite3@<version> node-pty@<version>
npx @electron/rebuild -v <ELECTRON_VERSION> --force

# 5. 移除 macOS 专有模块
rm -rf node_modules/sparkle-darwin
find . -name "sparkle.node" -delete

# 6. Linux UI patch
# 关键: 不要硬编码变量名，需动态检测
# - 检测 path 模块变量名
# - 添加 Linux 图标路径
# - 隐藏菜单栏
# - 替换透明背景色
```

### Linux UI Patch 脚本关键逻辑

```javascript
// 动态检测 Vite/Rollup 压缩后的 path 模块变量名
const pathVarMatch = source.match(
  /\blet\s+([A-Za-z_$][\w$]*)=require\(`(?:node:)?path`\)/
);
const pathVar = pathVarMatch ? pathVarMatch[1] : null;
const pathJoinExpr = pathVar
  ? `${pathVar}.join`
  : `require(\`node:path\`).join`;

// 使用动态变量名构建图标路径
const iconPath = `${pathJoinExpr}(process.resourcesPath,\`..\`,\`content\`,\`webview\`,\`assets\`,\`icon.png\`)`;

// 替换 BrowserWindow 配置
// - 为 Linux 添加 icon 属性
// - autoHideMenuBar: true
// - backgroundColor: '#000000' (dark) | '#f9f9f9' (light)
```

### 打包输出

```bash
# 下载 Linux Electron runtime
curl -L -o electron.zip \
  "https://github.com/electron/electron/releases/download/v<VERSION>/electron-v<VERSION>-linux-x64.zip"

# 组装应用目录
mkdir -p output-app/resources
unzip electron.zip -d output-app/
cp app.asar output-app/resources/
cp -r app-extracted/webview output-app/content/

# 创建启动脚本
cat > output-app/start.sh << 'EOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/electron" --no-sandbox "$@"
EOF
chmod +x output-app/start.sh
```

## 常见坑

### 1. `t.join is not a function`
原因: 硬编码了压缩后的变量名 `t.join(...)`，但新版 Vite bundle 中 `t` 不代表 `path` 模块。
修复: 运行时动态检测 path 模块变量名 (见上方脚本)。

### 2. 透明背景闪烁 (Linux)
原因: macOS 使用 `backgroundColor: '#00000000'` + vibrancy 实现毛玻璃效果，Linux 无等价合成器。
修复: 替换为不透明色 `#000000` (dark) / `#f9f9f9` (light)。

### 3. 原生模块平台不匹配
原因: DMG 中的 .node 文件是 macOS arm64/x64 编译的。
修复: 使用 `@electron/rebuild` 为目标平台重建。

### 4. `Cannot find module './product-name-XXXX.js'`
原因: app.asar 打包不完整，缺失 Vite 产物 chunk。
修复: 从原始 DMG 重新提取，不要手动删除 .vite/build/ 下的文件。

### 5. Windows → Linux 额外注意事项
- 换行符: `.bat` 用 CRLF，`.sh` 用 LF
- 路径分隔符: `\` → `/`
- DLL → .so 原生库替换
- 注册表操作 → 配置文件
- 7-Zip SFX → .deb/.rpm 打包

## 验证清单

- [ ] 应用启动无 crash
- [ ] 窗口无透明闪烁
- [ ] 菜单栏正常显示
- [ ] 图标正常加载
- [ ] 原生模块 (better-sqlite3) 正常工作
- [ ] 自定义协议 (typora://) 正常加载资源
- [ ] 插件系统正常
