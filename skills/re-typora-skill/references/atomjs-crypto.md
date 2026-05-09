# atom.js 加密/解密参考

> 参考文章: [Typora 1.9.5 Cracking](https://reinject.vercel.app/posts/reverse/cracking/typora_1_9_5_cracking/)

## 概述

atom.js 是 Typora Electron 主进程的核心 JavaScript 文件，存储在 `app.asar` 中。经过 **AES-256-CBC 加密 + Base64 编码**。

## 解密产物清单 (C:\yys\_asar_dec\)

| 文件 | 大小 | 说明 |
|------|------|------|
| `atom.js` | 187,460 B | app.asar 中的加密原件 (Base64 文本) |
| `atom.bin` | 140,593 B | Base64 解码后的原始数据 |
| `atom_aes.bin` | 140,592 B | AES 解密后的明文 (已去除末尾 1 字节) |
| `atom_decrypted.js` | 140,592 B | 解密产物 — Webpack bundle 的 Electron 主进程代码 |
| `atom_original_decrypted.js` | 140,592 B | 解密产物的备份 |
| `atom_rebranded.js` | 140,588 B | 经 replace_typora.js + pass2 两轮替换后的版本 |
| `main.node` | 1,102,720 B | 用于解密的 main.node (含 AES 密钥和 IV 生成函数) |
| `package.json` | 246 B | app.asar 附带的 package.json |
| `replace_typora.js` | 6,910 B | 第一轮 Typora→Typola 替换脚本 |
| `replace_typora_pass2.js` | 2,001 B | 第二轮补充替换脚本 |

## 加密方案

- **算法**: AES-256-CBC
- **Key (v1.9.5)**: `0d8e841eb83ac8106208f45770bc39b9d8b8ab60b2fb4613284fb497b68b0c6a`
- **IV**: 动态计算 — 由最终文件长度和末尾字节通过 main.node 内 `sub_180001992` 生成
- **文件结构**: `[Base64(AES-CBC(plaintext) + trailing_byte)]`
- **Trailing byte**: 文件最后一个字节不参与 AES 加密，但参与 IV 计算

## 解密流程 (已验证)

### Step 1: Base64 解码

```javascript
const fs = require('fs');
const ciphertext = fs.readFileSync('atom.js', 'utf8');
const decoded = Buffer.from(ciphertext, 'base64');  // 140593 bytes
fs.writeFileSync('atom.bin', decoded);
```

### Step 2: 分离 trailing byte

```python
with open('atom.bin', 'rb') as f:
    raw = f.read()                  # 140593 bytes

trailing_byte = raw[-1]             # 0x6a (原始值)
ciphertext = raw[:-1]               # 140592 bytes — AES-CBC payload
```

### Step 3: 计算 IV

IV 由 main.node 中的 `sub_180001992` 函数动态生成，参数:
1. IV 输出缓冲区 (16 bytes)
2. `(file_length % 256) ^ trailing_byte` 作为 seed
3. 输出长度 `0x10`

**原始 atom.js 的 IV**: `47a91ac73cfaa5af60e1e1d54301e848`

调用方法 (Windows C++):
```cpp
HMODULE hMod = LoadLibraryW(L"./main.node");
uint8_t* baseAddr = (uint8_t*)hMod;
typedef void (*GenIV)(uint8_t*, uint8_t, size_t);
GenIV genIV = (GenIV)(baseAddr + 0x1992);

uint8_t iv[16] = {0};
uint8_t seed = (140593 % 256) ^ 0x6a;  // = 0x6a ^ 0x6a = 0
genIV(iv, seed, 16);
// iv now contains the 16-byte IV
```

### Step 4: AES-256-CBC 解密

```python
from Crypto.Cipher import AES

key = bytes.fromhex('0d8e841eb83ac8106208f45770bc39b9d8b8ab60b2fb4613284fb497b68b0c6a')
iv  = bytes.fromhex('47a91ac73cfaa5af60e1e1d54301e848')

cipher = AES.new(key, AES.MODE_CBC, iv=iv)
plaintext = cipher.decrypt(ciphertext)  # 140592 bytes, 包含 PKCS7 padding
# plaintext starts with: module.exports= function(k){};
```

### Step 5: 验证

```bash
python -c "
from Crypto.Cipher import AES
key = bytes.fromhex('0d8e841eb83ac8106208f45770bc39b9d8b8ab60b2fb4613284fb497b68b0c6a')
iv  = bytes.fromhex('47a91ac73cfaa5af60e1e1d54301e848')
with open('atom.bin','rb') as f: raw = f.read()
pt = AES.new(key, AES.MODE_CBC, iv=iv).decrypt(raw[:-1])
with open('atom_decrypted.js','rb') as f: expected = f.read()
assert pt == expected, 'MISMATCH'
print('✓ Key and IV verified against atom_decrypted.js')
"
```

## 修改后重新加密

修改 `atom_decrypted.js` 后需要重新加密打包。由于文件长度变化，必须重新计算 IV:

### Step 1: 用临时 IV 预加密确定长度

```python
from Crypto.Cipher import AES
import os

key = bytes.fromhex('0d8e841eb83ac8106208f45770bc39b9d8b8ab60b2fb4613284fb497b68b0c6a')
temp_iv = os.urandom(16)

with open('atom_rebranded.js', 'rb') as f:
    plaintext = f.read()

cipher = AES.new(key, AES.MODE_CBC, iv=temp_iv)
temp_encrypted = cipher.encrypt(plaintext)

new_length = len(temp_encrypted) + 1  # +1 for trailing byte
print(f'New encrypted length: {new_length}')
```

### Step 2: 计算新 IV

```python
# 选择一个 trailing byte (0x00-0xff)
trailing_byte = 0xb7
seed = (new_length % 256) ^ trailing_byte

# 调用 main.node 的 sub_180001992 生成新 IV
# 或使用以下简化版 (根据文章，IV = MD5 类变体):
import hashlib

# IV = first 16 bytes of:
#   MD5( little_endian_uint32(seed) + b'\x00' * 12 )
seed_bytes = seed.to_bytes(4, 'little')
iv = hashlib.md5(seed_bytes + b'\x00' * 12).digest()
```

### Step 3: 用正确 IV 重新加密

```python
cipher = AES.new(key, AES.MODE_CBC, iv=iv)
encrypted = cipher.encrypt(plaintext)
final = encrypted + bytes([trailing_byte])

import base64
encoded = base64.b64encode(final).decode('ascii')
with open('atom.js', 'w') as f:
    f.write(encoded)
```

或使用 OpenSSL:

```bash
openssl enc -aes-256-cbc -in atom_rebranded.js -out atom_encrypted.bin \
  -iv <new_iv_hex> -K 0d8e841eb83ac8106208f45770bc39b9d8b8ab60b2fb4613284fb497b68b0c6a
printf '\xb7' >> atom_encrypted.bin
base64 -w0 atom_encrypted.bin > atom.js
```

### Step 4: 重新打包 app.asar

```bash
# 复制 atom.js, package.json, main.node 到打包目录
mkdir repack
cp atom.js repack/
cp package.json repack/
cp main.node repack/

# 打包 (注意: main.node 必须 unpack)
npx asar pack repack app.asar --unpack "main.node"
```

## main.node 关键函数偏移 (v1.9.5)

| 地址 | 函数 | 功能 |
|------|------|------|
| `0x180010BF0` | — | `app.asar` compilation |
| `0x180004647` | — | Wrapper for decryption |
| `0x18000B480` | — | `atom.js` decryption (AES-256-CBC) |
| `0x180001992` | `GenIV` | IV 生成 (3 params: buffer, seed, length) |
| `0x1800044DF` | — | AES decryption call |

## 解密后的 atom.js 结构

解密产物是一个 **Webpack 4/5 bundle**:

```javascript
module.exports= function(k){};
(()=>{
  var n = {
    883: (t,n,s) => {
      var l = s(134),  // require("electron")
          c = l.app,
          e = l.ipcMain,
          d = l.BrowserWindow,
          ...
      // 注册表操作 (addOpenInTypora, removeOpenInTypora)
      // IPC handler (shell.*, dialog.*, export.*, clipboard.*)
      // 菜单栏、主题、更新、Sentry、许可证验证
    },
  };
})();
```

## Bypass 加密 (跳过解密步骤)

可 hex-patch main.node 跳过 AES 解密，使明文 atom.js 直接执行:

1. 定位 `sub_18000B480` (atom.js 解密函数)
2. Patch 函数入口点为直接返回或跳过解密
3. 修改 atom.js 加载逻辑指向明文文件

优点: 不需要反复计算 IV 和重新加密
缺点: 需要理解 main.node 的汇编逻辑

## 品牌替换流程 (已验证可用)

### 第一轮: replace_typora.js (50+ 替换)

```javascript
// 注册表路径
'Software\\\\Typora' → 'Software\\\\Typola'
'Software\\\\Classes\\\\Directory\\\\shell\\\\Typora' → 'Typola'

// AppUserModelId
'abnerworks.Typora' → 'abnerworks.Typola'

// URL / Email / 日志 / 字典 / CSS / UI 字符串 / 窗口标题
// (详见 C:\yys\_asar_dec\replace_typora.js)
```

**关键不替换项**: `typora://app/typemark/`, `http://typora/`, `http://typora-app/atom/`, `github.com/typora/PicGo-cli`, `typora-bg`

### 第二轮: replace_typora_pass2.js

修复文字版项目符号 `• - Typora` 和临时目录名 `+"Typora"` 的遗漏。
