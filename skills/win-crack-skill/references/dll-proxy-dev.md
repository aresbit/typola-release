# DLL 代理开发参考

## 概述

DLL 代理 (Proxy DLL) 是一种技术，通过创建一个与目标 DLL 同名的恶意/拦截 DLL，将其放置在搜索路径中比原始 DLL 更优先的位置。代理 DLL 转发所有合法导出到原始 DLL，同时植入自定义逻辑。

## 工作流程

```
应用程序
    ↓ LoadLibrary("target.dll")
代理 DLL (target.dll)
    ├── DllMain() → 植入 API hook / 内存补丁
    ├── Export1 → 转发到 target_orig.Export1
    ├── Export2 → 转发到 target_orig.Export2
    └── ExportN → 转发到 target_orig.ExportN
原始 DLL (重命名为 target_orig.dll)
    ├── Export1 (真实实现)
    ├── Export2 (真实实现)
    └── ...
```

## 方法 1: .def 文件导出转发

### 步骤

1. 重命名原始 DLL：
```cmd
ren target.dll target_orig.dll
```

2. 使用 dumpbin 获取导出表：
```cmd
dumpbin /EXPORTS target_orig.dll
```

3. 创建 .def 文件，转发所有导出：
```def
EXPORTS
    Function1    = target_orig.Function1    @1
    Function2    = target_orig.Function2    @2
    Function3    = target_orig.Function3    @3
    ; ... 所有导出函数
```

4. 编写 DllMain 植入 hook：
```c
#include <windows.h>
#include <detours.h>

BOOL WINAPI DllMain(HINSTANCE hinst, DWORD dwReason, LPVOID reserved)
{
    if (dwReason == DLL_PROCESS_ATTACH) {
        // 植入 hook 逻辑
        DisableThreadLibraryCalls(hinst);
    }
    return TRUE;
}
```

5. 编译代理 DLL：
```cmd
cl /LD proxy.c /link /DEF:proxy.def /OUT:target.dll detours.lib
```

### 注意事项

- 转发声明必须覆盖原始 DLL 的全部导出
- 缺失的导出会导致 `GetProcAddress` 返回 NULL → 应用崩溃
- 可以使用 `EXPORTS` 中的 `NONAME` 关键字处理仅序号导出
- `.def` 中 `@Ordinal` 必须与原始 DLL 的导出序号匹配

## 方法 2: #pragma comment(linker, ...)

不需要单独的 .def 文件，直接在 C 代码中使用链接器指令：

```cpp
#pragma comment(linker, "/EXPORT:Function1=target_orig.Function1,@1")
#pragma comment(linker, "/EXPORT:Function2=target_orig.Function2,@2")
#pragma comment(linker, "/EXPORT:Function3=target_orig.Function3,@3")
```

### 绝对路径转发 (防二次劫持)

使用 NT 对象命名空间确保转发目标始终指向正确的文件：

```cpp
#pragma comment(linker,
    "/EXPORT:CredPackAuthenticationBufferA=\\\\.\\GLOBALROOT\\SystemRoot\\System32\\credui.dll.CredPackAuthenticationBufferA")
```

## 方法 3: 动态导出克隆 (运行时)

对于导出表非常长（数百个导出）的 DLL，手动编写转发不现实。使用运行时方法：

```c
// Koppeling-style dynamic export cloning
BOOL WINAPI DllMain(HINSTANCE hinst, DWORD dwReason, LPVOID reserved)
{
    if (dwReason == DLL_PROCESS_ATTACH) {
        // 1. 加载原始 DLL
        HMODULE hOrig = LoadLibraryA("target_orig.dll");

        // 2. 遍历原始 DLL 导出表
        PIMAGE_DOS_HEADER pDos = (PIMAGE_DOS_HEADER)hOrig;
        PIMAGE_NT_HEADERS pNt = (PIMAGE_NT_HEADERS)((BYTE*)hOrig + pDos->e_lfanew);
        PIMAGE_EXPORT_DIRECTORY pExport = ...;

        // 3. 为自己的 DLL 重建导出表
        // 每个 RVA 指向原始 DLL 的对应函数
        // 同时保留少量自己的导出 (带 hook 逻辑的)
    }
    return TRUE;
}
```

## 自动化工具

| 工具 | 语言 | 特点 |
|------|------|------|
| **SharpDllProxy** | C# | 读取目标 DLL，生成 C 源码 + .def，含 shellcode 注入 |
| **Koppeling** | C/Python/.NET | 4 种构建模式：静态转发、动态 NetClone/PyClone、运行时导出表重建 |
| **FaceDancer** | Python | 扫描 DLL 创建 .def，生成恶意代理 DLL |
| **perfect-dll-proxy** | Python (pefile) | 绝对路径转发，防二次劫持 |
| **dll-proxy-generator** | C | 导出所有符号并加载任意 DLL |

## 导出表转发器的 PE 格式原理

在 PE 文件的 Export Directory Table 中，每个导出函数有一个 RVA (Relative Virtual Address)：

- **普通导出**：RVA 指向 `.text` 段内的实际代码
- **转发器 (Forwarder)**：RVA 指向 `.edata` 段内的字符串 `"DLL名.函数名"`

Windows 加载器遇到转发器时，自动加载目标 DLL 并解析对应的函数。

**检测方法** (python + pefile)：
```python
import pefile

pe = pefile.PE("target.dll")
for exp in pe.DIRECTORY_ENTRY_EXPORT.symbols:
    rva = exp.address
    # 检查 RVA 是否在 .edata 段范围内
    for section in pe.sections:
        if section.contains_rva(rva):
            if section.Name.startswith(b'.edata'):
                # 这是一个转发器
                forwarder = pe.get_string_at_rva(rva)
                print(f"{exp.name} → {forwarder}")
```

## 隐蔽性增强

### 1. 保持原始时间戳
```python
import time, os
# 复制原始 DLL 的文件时间
st = os.stat("target_orig.dll")
os.utime("target.dll", (st.st_atime, st.st_mtime))
```

### 2. 复用原始版本信息
在 VS 项目属性中设置与原始 DLL 相同的 VERSIONINFO 资源。

### 3. 保留原始 DLL 数字签名 (作为备用)
将原始 DLL 作为资源嵌入代理 DLL，首次加载时提取到临时目录。转发使用绝对路径指向提取的副本。

## 实战流程：分析未知劫持 DLL

```bash
# 1. 识别是否为代理 DLL
file suspicious.dll                        # PE32+ DLL x86-64
strings suspicious.dll | grep ".detour"    # Detours 库特征
strings -e l suspicious.dll | grep ".exe"  # 进程名检查

# 2. 分析导出表
dumpbin /EXPORTS suspicious.dll | head -30

# 3. 对比系统原始 DLL 的导出
dumpbin /EXPORTS C:/Windows/System32/winmm.dll > sys_exports.txt
dumpbin /EXPORTS suspicious.dll > sus_exports.txt
diff sys_exports.txt sus_exports.txt

# 4. 判断代理模式
# 若导出全部或部分转发到另一个 DLL → 代理 DLL
# 若导出表为空或不完整 → 纯注入器 / 内存加载器
# 若包含 WriteProcessMemory + 进程名检查 → 内存补丁型
```

## 常见目标 DLL

以下 Windows 系统 DLL 经常被用作劫持目标 (因为它们不在 KnownDLLs 列表中)：

| DLL | 典型用途 |
|-----|---------|
| `winmm.dll` | 多媒体 API (wave*, midi*, mmio*) |
| `version.dll` | 版本信息 API |
| `userenv.dll` | 用户环境 (CreateEnvironmentBlock) |
| `dwmapi.dll` | Desktop Window Manager |
| `propsys.dll` | Property System |
| `dxgi.dll` | DirectX Graphics Infrastructure |
| `d3d12.dll` | Direct3D 12 |
