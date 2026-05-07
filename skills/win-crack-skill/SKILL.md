---
name: win-crack-skill
description: Analyze, reverse-engineer, and create DLL hijacking/proxy DLLs using Microsoft Detours for API hooking on Windows. Covers PE format analysis, .def export forwarding, hex-patching, process name checks, and memory patching via WriteProcessMemory. Use whenever the user needs to analyze a suspicious DLL in an app directory, understand how a crack/activation bypass works, hex-patch a DLL to fix a process name check, create a proxy DLL, or reverse-engineer Detours-based API hooks.
compatibility: Windows only — requires strings, xxd/hexdump, dumpbin (or PE-bear/CFF Explorer), python3
---

# Windows DLL Hijacking & Detours Proxy Skill

基于 Microsoft Detours 的 DLL 劫持代理技术逆向分析技能。核心理念：**DLL 劫持是 Windows 应用破解最常用的入口点，理解其机制需要同时掌握 PE 格式、Detours hook 架构和内存补丁技术。**

## 理论背景

### Windows DLL 搜索顺序

当程序调用 `LoadLibrary` 且未指定完整路径时，Windows 按以下顺序搜索 (MITRE ATT&CK: T1574.001)：

| 优先级 | 位置 | 说明 |
|--------|------|------|
| 1 | 应用启动目录 | **最容易被劫持的位置** |
| 2 | System32 | KnownDLLs 保护 |
| 3 | System | 16-bit 兼容 |
| 4 | Windows | 系统目录 |
| 5 | 当前工作目录 (CWD) | Safe DLL Search Mode 下移到 System 之后 |
| 6 | PATH 环境变量 | 用户级 → 系统级 |

**KnownDLLs 保护**：`HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\KnownDLLs` 中的 DLL 始终从 System32 加载。但许多系统 DLL（如 winmm.dll, version.dll, userenv.dll）不在此列表中，成为常见的劫持目标。

### Microsoft Detours 架构

Detours 是 Microsoft Research 在 1999 年 USENIX 发表的 API 拦截库 (Galen Hunt & Doug Brubacher)。核心机制：

**1. Inline Hooking** — 修改目标函数的内存镜像，而非磁盘文件：
```
Before:  Caller → TargetFunc (正常执行)
After:   Caller → TargetFunc (前 5 字节被覆盖为 JMP)
                    ↓
               DetourFunc (用户代码)
                    ↓
               Trampoline (原始指令 + JMP 回原函数)
                    ↓
               TargetFunc 剩余部分
```

**2. Trampoline** — Detours 的关键创新：保留原始函数为可调用子程序：
- 复制被覆盖的原始指令到动态分配的 trampoline 内存
- 追加无条件 JMP 回原函数剩余部分
- 使 detour 函数可以通过 target pointer 调用原函数

**3. ACID Transaction 模型** — 线程安全的 hook 插入：
```c
DetourTransactionBegin();                     // 开始原子事务
DetourUpdateThread(GetCurrentThread());        // 征用线程，安全更新 IP
DetourAttach(&(PVOID&)TrueFunc, HookFunc);     // 排队 attach
DetourTransactionCommit();                     // 原子提交全部 hook
```

**4. PE 文件特征**：
- `.detourc` section — Detours 创建的 PE 头副本（用于 reversibility）
- `.detourd` section — 附加的载荷数据段
- Detours 修改 PE import table 时创建这些 section

> 详细学术背景和原始论文见 `references/detours-paper.md`

## 实战方法论

### Step 1: 识别 DLL 劫持

```bash
# 检查应用目录下的可疑 DLL
ls -la /path/to/app/*.dll

# 查找包含 Detours 特征的 DLL
strings *.dll | grep -E "\.detour|WriteProcessMemory|GetModuleFileNameW"

# 列出所有非系统来源的 DLL
for dll in /path/to/app/*.dll; do
    sigcheck=$(strings "$dll" | grep -c "Microsoft Corporation")
    if [ "$sigcheck" -eq 0 ]; then
        echo "SUSPICIOUS: $dll (unsigned or third-party)"
    fi
done
```

### Step 2: 提取和分析字符串

这是最关键的逆向步骤。DLL 内的字符串直接暴露其逻辑：

```bash
# ASCII 字符串 — 查找 API 调用和逻辑特征
strings target.dll | grep -iE "process|write|read|load|create|registry|software|license|activation|trial|key|serial"

# UTF-16LE 字符串 — Windows 内部广泛使用，包含文件名/路径/注册表键
strings -e l target.dll | grep -iE "exe|dll|software|typora|typola|\.exe"

# 查找 hex 模式
xxd target.dll | grep -i "007400790070"  # UTF-16LE "typo"
```

**经验法则**：
- `WriteProcessMemory` + `ReadProcessMemory` → 内存补丁（修改代码逻辑）
- `GetModuleFileNameW` → 进程名/路径检查
- `CreateThread` + `LoadLibraryA` → 代码注入
- `SymLoadModule64` + `SymGetModuleInfo64` → 符号/调试信息操作
- 包含 `.detourc` / `.detourd` → 使用 Microsoft Detours 库
- Win32 multimedia API (wave*, midi*, mmio*) → 伪装成合法的 winmm.dll

### Step 3: 判断破解机制

分析 `DllMain` 或 hook 函数的逻辑：

```
1. DLL_PROCESS_ATTACH → 启动 hook 逻辑
2. GetModuleFileNameW → 获取当前进程路径
3. 检查进程名是否匹配 "target.exe" → 条件判断
4. 匹配 → DetourTransactionBegin + DetourAttach → hook 关键 API
5. WriteProcessMemory → 修改激活验证逻辑的内存
6. 不匹配 → 直接转发所有 API (代理模式)
```

### Step 4: Hex-Patch 修复

当需要修改 DLL 内的硬编码字符串时：

```python
import sys

with open(sys.argv[1], 'rb') as f:
    data = bytearray(f.read())

# 搜索 UTF-16LE 编码的字符串
search = b'target.exe'  # ASCII
pos = data.find(search)
if pos < 0:
    search = 'target.exe'.encode('utf-16-le')  # UTF-16LE
    pos = data.find(search)

if pos >= 0:
    # 验证替换前后长度一致
    replace = b'newapp.exe'
    assert len(search) == len(replace), \
        f"Length mismatch: {len(search)} vs {len(replace)}"
    
    # 应用 patch
    data[pos:pos+len(replace)] = replace
    
    with open(sys.argv[1], 'wb') as f:
        f.write(data)
    print(f"Patched at offset {pos} (0x{pos:x})")
else:
    print("String not found")

# 验证
for encoding in ['ascii', 'utf-16-le']:
    test = replace if encoding == 'ascii' else replace.decode('ascii').encode('utf-16-le')
    assert test in data, f"Patch verification failed for {encoding}"
```

**关键规则**：
- 替换字符串必须与原始字符串**长度完全相同**
- UTF-16LE 中每个 ASCII 字符占 2 字节 (char + 0x00)
- 10 个字符的 ASCII 字符串 = 20 字节的 UTF-16LE 编码
- 始终用 hexdump 验证 patch 结果

### Step 5: 创建代理 DLL（高级）

当需要完整替换 DLL 功能时，使用 export forwarding 实现代理：

**.def 文件方法：**
```def
EXPORTS
    midiInOpen    = winmm_orig.midiInOpen    @1
    midiOutOpen   = winmm_orig.midiOutOpen   @2
    waveInOpen    = winmm_orig.waveInOpen    @3
    waveOutWrite  = winmm_orig.waveOutWrite  @4
    ; ... 转发所有其他导出到原 DLL
```

**链接器 pragma 方法：**
```cpp
#pragma comment(linker, "/EXPORT:midiInOpen=winmm_orig.midiInOpen,@1")
#pragma comment(linker, "/EXPORT:midiOutOpen=winmm_orig.midiOutOpen,@2")
```

然后在 `DllMain` 中植入 hook 逻辑。
自动化工具：**SharpDllProxy**, **Koppeling**, **perfect-dll-proxy**, **FaceDancer**。

> 详细开发流程见 `references/dll-proxy-dev.md`

## PE 格式快速参考

```
PE 文件结构:
┌──────────────────────┐
│ DOS Header (MZ)      │
│ DOS Stub              │  ← "This program cannot be run in DOS mode"
│ PE Signature (PE\0\0) │
│ COFF File Header      │  → NumberOfSections
│ Optional Header       │
│ Section Headers       │  → .text, .rdata, .data, .detourc, .detourd
│ .text section         │  ← 代码段
│ .rdata section        │  ← 只读数据（含导入/导出表）
│ .edata section        │  ← 导出表 (Export Directory)
│ .detourc section      │  ← Detours PE 头副本
│ .detourd section      │  ← Detours 载荷数据
│ .reloc section        │  ← 重定位表
└──────────────────────┘
```

**Forwarder RVA 检测**：若导出函数 RVA 在 `.edata` section 范围内，则该入口为转发器，指向格式为 `"DLLName.FunctionName"` 的 ASCII 字符串。

## 调试与验证工具箱

| 工具/命令 | 用途 |
|-----------|------|
| `strings target.dll` | ASCII 字符串提取 |
| `strings -e l target.dll` | UTF-16LE 字符串提取 |
| `hexdump -C target.dll \| grep pattern` | Hex 模式搜索 |
| `xxd target.dll \| grep -i pattern` | 同上 (备用) |
| `dumpbin /EXPORTS target.dll` | 导出表查看 |
| `file target.dll` | PE 格式识别 |
| `objdump -p target.dll` | PE 头信息 |
| Process Monitor (procmon) | DLL 加载顺序监�� |
| `npx asar list/extract app.asar` | Electron asar 操作 |
| `cmp -l file1 file2` | 逐字节比较 |
| `md5sum / sha256sum` | 文件一致性校验 |

## 常见问题速查

| 症状 | 原因 | 修复 |
|------|------|------|
| DLL 劫持不生效 | 进程名检查不匹配 | hex-patch 进程名字符串 (UTF-16LE)，保持长度一致 |
| Detours hook 不触发 | 目标进程使用了其他加载路径 | 检查 DLL 搜索顺序 (procmon)，确认 DLL 位置正确 |
| 替换后应用崩溃 | 导出表不完整，缺少某些函数转发 | 使用 dumpbin 对比原始 DLL 导出表，补全所有转发 |
| `strings` 找不到关键字符串 | 字符串可能是压缩/加密的 | 检查 .rdata 段和 UTF-16LE 编码 |
| 64-bit DLL 无法 hook 32-bit 进程 | 架构不匹配 | 确保 DLL 和目标进程架构一致 (都是 x64 或都是 x86) |

## 安全注意事项

本技能用于合法的逆向工程、安全研究和软件互操作性目的。DLL 劫持技术在未授权的情况下使用可能违反软件许可协议和相关法律。进行此类分析时：
- 仅在拥有合法授权的系统上操作
- 遵守当地知识产权法律
- 不要将技术用于绕过软件付费或破坏 DRM 保护（除非在合法安全研究范围内）
