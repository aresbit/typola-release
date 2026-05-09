# atom.js 加密/解密参考

## 概述

atom.js 是 Typora Electron 主进程的核心 JavaScript 文件，存储在 `app.asar` 中。经过 **AES-256-CBC 加密 + Base64 编码**。

## 解密产物清单 (C:\yys\_asar_dec\)

| 文件 | 大小 | 说明 |
|------|------|------|
| `atom.js` | 187,460 B | app.asar 中的加密原件 (Base64 文本) |
| `atom.bin` | 140,593 B | Base64 解码后的密文 |
| `atom_aes.bin` | 140,592 B | AES 解密后的原始明文 (去除了 PKCS7 padding) |
| `atom_decrypted.js` | 140,592 B | 解密产物 — Webpack bundle 的 Electron 主进程代码 |
| `atom_original_decrypted.js` | 140,592 B | 解密产物的备份 |
| `atom_rebranded.js` | 140,588 B | 经 replace_typora.js + replace_typora_pass2.js 两轮替换后的版本 |
| `main.node` | 1,102,720 B | 用于解密的 main.node (含 AES 密钥和 IV 计算逻辑) |
| `package.json` | 246 B | app.asar 附带的 package.json |
| `replace_typora.js` | 6,910 B | 第一轮 Typora→Typola 替换脚本 |
| `replace_typora_pass2.js` | 2,001 B | 第二轮补充替换脚本 |

## 解密流程

### Step 1: Base64 解码

```javascript
const fs = require('fs');
const ciphertext = fs.readFileSync('atom.js', 'utf8');
const decoded = Buffer.from(ciphertext, 'base64');
// decoded.length === 140593 (包含 1 字节 PKCS7 padding)
fs.writeFileSync('atom.bin', decoded);
```

### Step 2: AES-256-CBC 解密

```javascript
const crypto = require('crypto');
const decoded = fs.readFileSync('atom.bin');

// key (32 bytes) 和 iv (16 bytes) 从 main.node 的 .rdata section 中提取
// key 位于 main.node .rdata 段中的高熵区域
// iv 计算逻辑: IV = MD5(特定标识符) 或 IV = main.node 内固定 16 字节常量
// 
// 具体提取方法: 解析 main.node PE 结构 → 定位 .rdata section →
//   从已知偏移量读取 32 字节 key + 16 字节 iv
//   (偏移量通过熵分析或符号定位确定)

const key = extractKeyFromMainNode();  // 32 bytes
const iv = deriveIV();                  // 16 bytes

const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
const plaintext = Buffer.concat([
    decipher.update(decoded),
    decipher.final()  // 自动移除 PKCS7 padding
]);

fs.writeFileSync('atom_decrypted.js', plaintext);
// plaintext.length === 140592
```

### Step 3: 验证

解密成功的验证标志:
- 第一行以 `module.exports= function(k){};` 开头
- 文件约 140KB，包含 Webpack IIFE bundle 结构
- 可以在纯文本中搜索到 `abnerworks.Typora`、`require("electron")` 等特征字符串

## 解密后的 atom.js 结构

解密产物是一个 **Webpack 4/5 bundle**，结构如下:

```javascript
module.exports= function(k){};
(()=>{
  var n = {
    883: (t,n,s) => {
      // Electron 主进程初始化
      var l = s(134),  // require("electron")
          c = l.app,
          e = l.ipcMain,
          d = l.BrowserWindow,
          ...
      // 注册表操作 (addOpenInTypora, removeOpenInTypora)
      // IPC handler 注册 (shell.*, dialog.*, export.*, clipboard.*)
      // 菜单栏构建
      // 主题管理
      // 自动更新
      // Sentry 错误上报
      // 许可证验证
    },
    // ... 更多模块
  };
})();
```

关键模块功能:

| Webpack 模块 | 推断功能 |
|-------------|---------|
| `s(134)` = `require("electron")` | Electron API (app, BrowserWindow, ipcMain, shell, dialog) |
| `s(676)` = `require("node-registry")` | Windows 注册表操作 (winreg) |
| `s(833)` = `require("fs")` | 文件系统操作 |
| `s(541)` = `require("path")` | 路径处理 |
| `s(728)` = `require("fs-extra")` | 扩展文件操作 |
| `s(554)` = `require("electron-dl")` | 下载管理器 |
| `s(46)` = `require("child_process")` | 子进程 (REG IMPORT 等) |
| `s(344)` | 字典下载 |
| `s(156)` | 更新检查 (autoUpdater) |
| Sentry/Raven 模块 | 错误上报 (sentry.typora.io) |

## 品牌替换流程 (已验证可用)

### 第一轮: replace_typora.js

对 `atom_decrypted.js` 执行 50+ 次定向替换:

- **注册表路径**: `Software\\Typora` → `Software\\Typola`, `Software\\Classes\\Directory\\shell\\Typora` → `Typola`
- **AppUserModelId**: `abnerworks.Typora` → `abnerworks.Typola`
- **URL**: `typora.io` → `typola.io`, `typoraio.cn` → `typolai.cn`
- **邮件**: `hi@typora.io` → `hi@typola.io`
- **日志文件**: `typora.log` → `typola.log`, `typora-old.log` → `typola-old.log`
- **字典路径**: `typora-dictionaries` → `typola-dictionaries`
- **CSS 类名**: `typora-maxmized` → `typola-maximized`, `typora-fullscreen` → `typola-fullscreen`, `typora-sourceview-on` → `typola-sourceview-on`
- **UI 字符串**: 激活提示、错误消息、版本显示等
- **窗口标题**: `" - Typora"` → `" - Typola"`, 包括正则 `/•? - Typora$/` → `/•? - Typola$/`
- **临时目录**: `{name:"Typora"}` → `{name:"Typola"}`
- **localStorage**: `getItem("Typora")` → `getItem("Typola")`
- **Sentry DSN**: `sentry.typora.io` → `sentry.typola.io` (切断数据上报)
- **更新路径**: `typora-update-` → `typola-update-`

**关键不替换项** (保留原样):
- `typora://app/typemark/` — 自定义协议
- `http://typora/` — Sentry 内部 URL masking
- `http://typora-app/atom/` — 堆栈跟踪路径
- `github.com/typora/PicGo-cli` — 第三方依赖路径 (改名会 404)
- `typora-bg` — 背景 IPC 通道

### 第二轮: replace_typora_pass2.js

修复第一轮遗漏:
- 文字版项目符号 `• - Typora` → `• - Typola` (U+2022 字面量)
- 临时目录名拼接 `+"Typora"` → `+ "Typola"`

### 运行方式

```bash
cd C:\yys\_asar_dec
node replace_typora.js       # 第一轮: atom_decrypted.js → atom_rebranded.js
node replace_typora_pass2.js # 第二轮: 修复遗漏
```

## atom.js 重新加密与打包

### 方法 A: 重新 AES-256-CBC 加密

```javascript
const crypto = require('crypto');
const fs = require('fs');

const plaintext = fs.readFileSync('atom_rebranded.js');
const key = extractKeyFromMainNode();  // 同解密用的 key
const iv = deriveIV();                  // 同解密用的 iv

const cipher = crypto.createCipheriv('aes-256-cbc', key, iv);
const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
const encoded = Buffer.from(encrypted).toString('base64');

fs.writeFileSync('atom.js', encoded);
```

然后重新打包 app.asar:

```bash
cp atom.js /tmp/app-asar-repack/
cp package.json /tmp/app-asar-repack/
# 注意: main.node 必须放到 unpacked 目录
npx asar pack /tmp/app-asar-repack app.asar --unpack "*.node"
```

### 方法 B: Bypass 加密 (跳过解密步骤)

Hex-patch main.node 跳过 AES 解密，直接执行明文 atom.js:

1. 在 main.node 中找到解密函数入口点
2. Patch 为直接返回 (跳过解密逻辑)
3. 或在 atom.js 文件位置替换为明文 JavaScript

优点: 不需要知道 key/IV，修改 atom.js 后不需要重新加密
缺点: 需要理解 main.node 的汇编逻辑

## 密钥提取方法 (待完善)

### 已知信息

- **算法**: AES-256-CBC
- **Key**: 32 bytes，存储在 main.node 的 `.rdata` section 中
- **IV**: 16 bytes，由 main.node 中的逻辑计算
- **解密验证**: 已在 session e4a194f9 成功解密，产物在 `C:\yys\_asar_dec\`

### Key 定位思路

```python
from Crypto.Cipher import AES
import struct

# 1. 解析 main.node PE 结构
with open('main.node', 'rb') as f:
    data = f.read()
e_lfanew = struct.unpack_from('<I', data, 0x3c)[0]
# 遍历 section headers 找到 .rdata
# ...

# 2. 在 .rdata 段中搜索高熵 32-byte 窗口
def entropy(b):
    from math import log2
    freq = {}
    for byte in b: freq[byte] = freq.get(byte, 0) + 1
    return -sum(f/len(b) * log2(f/len(b)) for f in freq.values())

# 3. 用已知明文验证候选 key
known_pt = b'module.exports'  # atom_decrypted.js 的前 14 字节
for each 32-byte key_candidate in .rdata:
    try:
        cipher = AES.new(key_candidate, AES.MODE_CBC, iv=candidate_iv)
        if cipher.decrypt(ciphertext[:16])[:14] == known_pt:
            print(f'FOUND key at offset {offset}')
    except: pass
```

### 当前状态

key 和 IV 的具体提取方法尚未以可复现的形式记录。已知的验证方法:
- `node -e "require('./main.node')"` 可成功加载 main.node (说明是有效的 Node.js 原生模块)
- main.node 导出 3 个函数: `Spellchecker`, `openAs`, `openProperties`
- 解密逻辑是内部函数，不直接导出
