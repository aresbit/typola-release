# Microsoft Detours: 学术背景与架构详解

## 原始论文

**"Detours: Binary Interception of Win32 Functions"**
— Galen Hunt & Doug Brubacher, Microsoft Research
— 3rd USENIX Windows NT Symposium, Seattle, WA, July 1999

这是 Detours 库的奠基性论文，被引用超过 1000 次。论文可在 USENIX 官方档案中获取：
[hunt_html/index.html](https://atc.usenix.org/legacy/publications/library/proceedings/usenix-nt99/full_papers/hunt/hunt_html/index.html)

## 论文核心贡献

### 1. Trampoline 设计 (Detours 独有)

在 Detours 之前，大多数二进制拦截方案直接将 target function 前几个指令替换为 JMP，使得**原始函数无法再被调用**。Detours 的创新在于：

- 分配 trampoline 内存块
- 将被覆盖的原始指令复制到 trampoline
- 追加 JMP 回到 target function 的剩余部分
- 提供 **target pointer** → trampoline，使 hook 函数仍可将原函数作为子程序调用

这使得 Detours 成为"第一个在逻辑上将未被修改的目标函数作为子程序保留的包"。

### 2. 表驱动反汇编器

Detours 使用**表驱动**的代码反汇编器来确定要复制多少指令：

- 不同的 CPU 架构有不同的指令表 (x86, x64, IA64, ARM)
- 从 target function 开始逐条反汇编
- 累计复制指令直到 ≥ 5 字节 (x86 无条件 JMP 的最短长度)
- 处理可变长度编码 (x86/x64) 和定长编码 (ARM/IA64)

### 3. 线程安全 (Transaction 模型)

现代 Detours (v4+) 引入了 ACID 风格的 transaction 模型：

```
DetourTransactionBegin()
    ↓ 标记事务开始
DetourUpdateThread(hThread)
    ↓ 征用线程，挂起后安全修改其 IP
DetourAttach(&TrueFunc, HookFunc)
    ↓ 排队 attach 操作
DetourTransactionCommit()
    ↓ 原子执行所有排队的 attach/detach
    ↓ 更新所有征用线程的指令指针
    ↓ 恢复线程执行
```

在 Transaction 期间：
- 所有征用的线程被挂起
- 检查每个线程的 IP 是否在将被覆盖的代码区域内
- 若 IP 在影响范围内，将其调整为指向 trampoline 的对应位置
- 一次性应用所有内存修改

## Detours 拦截的汇编实现

### x86 (32-bit)

```
; Target function before:
TargetFunc:
    PUSH EBP           ; 1 byte
    MOV EBP, ESP       ; 2 bytes
    SUB ESP, 0x40      ; 3 bytes  → 总共 6 字节 (≥5, 足够)

; Target function after DetourAttach:
TargetFunc:
    JMP DetourFunc     ; 5 bytes (覆盖前 6 字节，第 6 字节为 nop/忽略)

; Trampoline:
Trampoline:
    PUSH EBP           ; 原始指令 1
    MOV EBP, ESP       ; 原始指令 2
    SUB ESP, 0x40      ; 原始指令 3
    JMP TargetFunc+6   ; 跳回原函数第 7 字节
```

### x64 (64-bit)

x64 地址空间超过 4GB，5 字节 JMP 无法覆盖全部地址范围。Detours 在 x64 上使用 `JMP [RIP+0]` (间接跳转)：

```
; Target function after hook:
TargetFunc:
    JMP [RIP+0]        ; 6 bytes, 跳转到下一条指令的地址处存储的 64-bit 地址
    .dq DetourFunc     ; 8 bytes — 目标地址
```

## Detours API 关键函数

```c
// 事务管理
LONG DetourTransactionBegin(VOID);
LONG DetourTransactionCommit(VOID);
LONG DetourTransactionAbort(VOID);

// 线程征用
LONG DetourUpdateThread(HANDLE hThread);

// Hook 操作
LONG DetourAttach(PVOID *ppPointer, PVOID pDetour);
LONG DetourDetach(PVOID *ppPointer, PVOID pDetour);

// DLL 注入辅助
BOOL DetourCreateProcessWithDllExW(
    LPCWSTR lpApplicationName,
    LPWSTR lpCommandLine,
    ...,
    LPCWSTR lpDllName,
    PDETOUR_CREATE_PROCESS_ROUTINEW pfCreateProcessW
);

// 进程内恢复
LONG DetourRestoreAfterWith(VOID);
BOOL DetourIsHelperProcess(VOID);

// PE 修改
LONG DetourBinaryOpen(HANDLE hFile);
LONG DetourBinaryEditImports(PVOID pBinary);
LONG DetourBinaryWrite(PVOID pBinary, HANDLE hFile);
```

## Detours 的 PE Section 特征

当 Detours 修改 PE 文件 (如编辑 import table) 时，会创建自定义 section：

| Section 名 | 内容 |
|------------|------|
| `.detourc` | 原始 PE 头的副本 (Certificate / PE Header — 用于 reversibility) |
| `.detourd` | Detours 附加的载荷数据 (Data) |

这也是磁盘上的 DLL 可以被识别为使用了 Detours 的关键特征。

## 与其他 Hook 技术对比

| 技术 | 开销 | 捕获全部调用 | 需要源码 | 内存安全 |
|------|------|-------------|---------|---------|
| **Detours (Inline Hook)** | ~400ns | 是 | 否 | 是 (Transaction) |
| IAT Hooking | 极低 | 否 (漏 GetProcAddress) | 否 | 取决于实现 |
| DLL Redirection | 低 | 否 | 否 | 是 |
| Breakpoint Trapping | 极高 | 是 | 否 | 否 (挂起全部线程) |
| VTable Hooking | 极低 | 取决于语言 | 否 | 否 |
| SSDT Hooking (内核) | 中 | 是 | 否 | 需要内核模块 |

## 相关学术工作

1. **HookChain** (arXiv:2404.16856, 2024) — 结合 IAT Hooking + 动态 SSN 解析 + 间接系统调用，绕过仅监控 ntdll.dll 的 EDR
2. **Malware Charaterization Using Windows API Call Sequences** (Gupta et al., 2018) — 使用 Detours hook 534 个 Win-API 对恶意软件行为进行分类
3. **基于 Detours 的文件操作监控方案** (计算机应用, 2010) — 国内最早系统介绍 Detours 用于文件监控的论文之一

## 开源仓库

- [github.com/microsoft/Detours](https://github.com/microsoft/Detours) — MIT 许可证开源
- [github.com/SpartanX1/microsoft-detours-example](https://github.com/SpartanX1/microsoft-detours-example) — 完整教程示例
