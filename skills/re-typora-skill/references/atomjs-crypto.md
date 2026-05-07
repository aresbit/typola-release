# atom.js 加密/解密参考

## 概述

atom.js 是 Typora Electron 主进程的核心 JavaScript 文件，存储在 `app.asar` 中。经过 **AES-256-CBC 加密 + Base64 编码**。

解密后的 atom.js 包含 (约 187KB 原始代码)：
- 窗口管理 (BrowserWindow 创建和配置)
- 自定义协议注册 (`typora://`, `typora-bg://`)
- 菜单栏构建
- 文件关联处理
- 激活/许可证验证 (license check)
- Sentry 错误上报 (Raven SDK)
- 自动更新检查
- 字典下载
- IPC 通信处理
- 文件系统操作

## 加密格式

```
atom.js 文件内容:
┌──────────────────────────────────────────────┐
│  Base64 编码的 AES-256-CBC 密文              │
│  (单行, 约 250KB 文本)                       │
└──────────────────────────────────────────────┘

解密流程:
Base64 文本 → 解码为二进制 → AES-256-CBC 解密 → 原始 JavaScript
```

## 密钥与 IV

- **算法**: AES-256-CBC
- **密钥**: 32 字节 (256 bits)，存储在 main.node 中或在 main.node 中通过算法派生
- **IV**: 16 字节，计算方法在 main.node 中 (可能与版本号、机器 ID 或其他标识符相关)
- **关键发现**: 密钥和 IV 计算逻辑在 main.node 的编译 C++ 代码中

## 逆向方法

### 方法 1: 从 main.node 提取密钥

```bash
# 在 main.node 中搜索可能的密钥模式 (32 字节高熵数据)
strings main.node | grep -E '^[A-Za-z0-9+/=]{32,44}$'

# 使用 IDA Pro / Ghidra 反汇编 main.node
# 定位 AES 密钥调度或 OpenSSL/BoringSSL 的 EVP_DecryptInit_ex 调用

# 搜索可能的 IV 常量
hexdump -C main.node | grep -E '00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00'

# 用 Python 尝试解密
python3 << 'PYEOF'
import base64
from Crypto.Cipher import AES

with open('atom.js', 'r') as f:
    ciphertext = base64.b64decode(f.read())

key = bytes.fromhex('...')  # 32 bytes from main.node
iv = bytes.fromhex('...')   # 16 bytes

cipher = AES.new(key, AES.MODE_CBC, iv)
plaintext = cipher.decrypt(ciphertext)

# 移除 PKCS7 padding
pad_len = plaintext[-1]
plaintext = plaintext[:-pad_len]

with open('atom_decrypted.js', 'wb') as f:
    f.write(plaintext)
print("Decrypted successfully")
PYEOF
```

### 方法 2: Bypass 解密 (推荐用于快速迭代)

Hex-patch main.node 跳过解密步骤，直接执行明文 atom.js：

```bash
# 1. 解密 atom.js (使用上述方法获取密钥)
# 2. 修改 atom.js 内容 (品牌替换、移除验证等)
# 3. 在 main.node 中找到解密调用点
# 4. Patch main.node 跳过解密:
#    - 找到调用解密的函数入口
#    - 修改为直接返回 (ret) 或跳过解密逻辑
#    - 或修改 atom.js 的加载路径指向已解密文件

# 验证: 将明文 atom.js 放入 app.asar 后应用应正常启动
```

### 方法 3: 重新加密

```bash
# 修改 atom_decrypted.js 后重新加密:
python3 << 'PYEOF'
import base64
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad

with open('atom_decrypted.js', 'rb') as f:
    plaintext = f.read()

key = bytes.fromhex('...')
iv = bytes.fromhex('...')

cipher = AES.new(key, AES.MODE_CBC, iv)
ciphertext = cipher.encrypt(pad(plaintext, AES.block_size))

encoded = base64.b64encode(ciphertext).decode('ascii')
with open('atom.js', 'w') as f:
    f.write(encoded)
PYEOF

# 然后用 npx asar pack 重新打包
```

## atom.js 内部结构 (解密后)

解密后的 atom.js 是一个压缩/混淆的单文件 JavaScript。关键模块 (通过 `require()` 识别):

| 模块 | 功能 | 可修改性 |
|------|------|---------|
| BrowserWindow 配置 | 窗口创建参数 | 可修改 backgroundColor, icon 等 |
| protocol.registerFileProtocol | 注册 typora:// 协议 | **不可修改协议名** |
| Menu.buildFromTemplate | 菜单栏模板 | 可修改 label 文字 |
| app.setName / app.getName | 应用名称 | 可修改 (与 package.json name 对齐) |
| autoUpdater | 自动更新 | 可移除 (安全) |
| Sentry/Raven | 错误上报 | 可移除 (安全) |
| license check | 激活验证 | 可移除/bypass |

> 注意: 解密后的 atom.js 约 187KB 是高度压缩的代码，直接编辑需要谨慎定位修改点。
