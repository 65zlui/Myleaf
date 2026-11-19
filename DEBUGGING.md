# myleaf 调试与代码修改记录

> 时间：2026-11-18 ~ 2026-11-19
> 仓库：`git@github.com:65zlui/Myleaf.git`（`main`）
> 对应版本：v1.4.0
>
> 本文记录的是**定位问题、修改代码、验证修复**的过程，而不是应用运行时的操作日志。
> 应用运行时的编译日志见下文第 5 节（功能实现）以及 `~/Library/Logs/myleaf/`。

---

## 1. 基线与环境

### 1.1 工具链

| 项目 | 值 |
|------|-----|
| Xcode | 16.4 (16F6)，通过 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 调用 |
| Swift | 6.1.2 编译器，项目语言模式 Swift 5 |
| SDK | macOS 15.5 |
| 部署目标 | 初始 15.3，后调整为 14.0（与 README 一致） |
| TeX | `/opt/homebrew/bin/tectonic` 0.17.0；应用内安装版 0.16.9 |
| Pandoc | 未安装（导出 Word 的安装流程未做端到端验证） |

系统 `xcode-select` 指向 CommandLineTools，`xcodebuild` 会报错，因此所有构建都显式指定 Xcode 的 `DEVELOPER_DIR`。

### 1.2 基线验证

```bash
xcodebuild -project myleaf.xcodeproj -scheme myleaf -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/myleaf-dd \
  CODE_SIGNING_ALLOWED=NO build
# => ** BUILD SUCCEEDED **，无 Swift 警告

xcodebuild -project myleaf.xcodeproj -scheme myleafTests \
  -destination 'platform=macOS' -derivedDataPath /tmp/myleaf-dd \
  CODE_SIGNING_ALLOWED=NO test
# => ** TEST SUCCEEDED **，43 个测试全部通过
```

同时确认：

- 19 个模板确实被复制进 `Contents/Resources`（`PBXFileSystemSynchronizedRootGroup` 会扁平化目录，`TemplateManager` 生产模式按扁平结构读取，逻辑正确）。
- 启动 Debug 构建并截图，欢迎页渲染正常。
- 最小文档用 Tectonic 命令行编译成功，排除环境问题。

---

## 2. 定位方法与证据来源

不是只靠“读代码猜”，每个问题都尽量找到可复现的证据：

1. **静态审查**：通读 3.5k 行 Swift 源码，重点看进程、并发、文件生命周期。
2. **独立 harness**：把 `LaTeXCompiler.swift` 与测试 `main.swift` 一起 `swiftc` 编译，绕过 UI 直接验证编译服务：

   ```bash
   swiftc -o harness LaTeXCompiler.swift main.swift && ./harness
   ```

   这样能精确复现“临时目录 / 相对路径 / 返回码 / 日志”问题。
3. **编译器警告**：Swift 6 模式下的 actor 隔离警告暴露了后台线程调用 `NSSavePanel` 的问题。
4. **xcodebuild 真实构建**：Release/签名阶段暴露了 FileProvider 元数据问题。
5. **lldb attach**：直接查看运行中应用的 `UserDefaults`，定位历史记录/沙盒容器差异。
6. **截图与 Saved Application State 对照**：定位窗口状态恢复问题。
7. **多次全量测试**：暴露并行测试下的 Tectonic 缓存竞争。

---

## 3. 问题定位与修复过程（按发现顺序）

### 3.1 编译可能永久卡死：`Pipe` + `waitUntilExit()`

**定位**

审查 `Services/LaTeXCompiler.swift` 的进程执行代码：

```swift
try process.run()
process.waitUntilExit()                       // 先等退出
let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()  // 后读管道
```

管道内核缓冲区只有约 64 KB。LaTeX/pdflatex 的日志很容易超过这个大小，子进程写满缓冲区后会阻塞，父进程又在等子进程退出——典型死锁。

`ExportService.exportWord` 里对 Pandoc 使用了同样模式。

**修复**

- 子进程 stdout/stderr 直接重定向到临时日志文件（`FileHandle`），彻底绕开管道容量限制。
- `waitUntilExit` 之外增加超时轮询：默认 300 秒，先 `terminate()`（SIGTERM），1 秒后仍在运行则 `kill(pid, SIGKILL)`。
- Pandoc 导出同样改为日志文件 + 180 秒超时。

**验证**

- 编译器集成测试：正常文档、错误文档都能在数秒内返回，不再依赖“日志大小足够小”。
- 超时路径通过代码审查验证（未构造 300 秒挂起测试，避免 CI 变慢）。

---

### 3.2 打开的项目无法编译：`\input` / 图片 / `.bib` 全部丢失

**定位**

原实现把当前文本写死为临时目录里的 `document.tex`，再在该目录编译。Tectonic 按**主文件所在目录**解析相对路径，因此：

```latex
\documentclass{article}
\begin{document}
\input{section.tex}
\end{document}
```

即使 `section.tex` 与用户文档在同一目录，也一定找不到。

用独立 harness 复现，真实输出：

```text
simple: SUCCESS .../document.pdf
sibling input: FAIL note: Running TeX ...
error: document.tex:3: ! LaTeX Error: File `section.tex' not found.
```

**修复**

`LaTeXCompiler.compile(source:documentURL:)` 增加文档路径：

1. 若缓冲区内容与磁盘文件一致 → 直接编译真实文件。
2. 若缓冲区有未保存修改 → 在文档同目录写一个唯一的临时兄弟文件（`myleaf-compile-XXXXXXXX.tex`），编译后删除。
3. 通过 `--outdir` / `-output-directory` 把输出定向到临时目录，不污染用户工程。
4. 目录不可写（只读卷等）时回退到自包含临时目录编译。

**验证**

修复后同一 harness：

```text
simple: SUCCESS pdfBytes=2506
sibling input with documentURL: SUCCESS pdfBytes=2939
project files after compile: ["section.tex", "main.tex"]   # 临时文件已清理
broken document: FAIL ... Undefined control sequence
```

并新增 `LaTeXCompilerTests.compileResolvesSiblingInputFiles` 固化该行为。

---

### 3.3 PDF 预览指向已删除文件

**定位**

原来 `compile()` 返回临时 PDF 的 `URL`，`PDFDocument(url:)` 是惰性读取；下一次编译会删除上一个临时目录。理论上旧预览可能读到已删除的文件。

**修复**

- 编译成功后立即 `Data(contentsOf: pdfURL)`，返回内存中的 `Data`。
- `EditorViewModel` 用 `PDFDocument(data:)` 创建预览。
- 临时目录在 `defer` 中立即删除。

---

### 3.4 Word 导出在后台线程操作 AppKit

**定位**

Xcode 构建时出现警告（Swift 6 下为错误）：

```text
ExportService.swift:98: main actor-isolated property 'allowedContentTypes'
can not be mutated from a nonisolated context
ExportService.swift:97: expression is 'async' but is not marked with 'await'
```

`exportPDF`/`exportWord` 是非隔离的；`exportWord` 是 `async`，按 SE-0338 会在通用执行器上运行，但内部调用了 `NSSavePanel.runModal()` 和面板属性——在后台线程操作 AppKit，存在崩溃风险。

**修复**

为两个导出方法标注 `@MainActor`（保存面板回到主线程），进程本身仍在后台队列执行。

---

### 3.5 Tectonic 安装器的并发与解压假设

**定位**

- `TectonicInstaller` 是 `@Observable` 但未隔离到 `@MainActor`。`install()` 是 `async`，在 `URLSession` 恢复后可能在非主线程改 UI 状态。
- `URLSession.download` 对 HTTP 错误不抛异常，原代码没有检查状态码。
- tar 直接解压到 `bin/`，假设压缩包根目录就是二进制；不同版本可能带子目录，且会把 LICENSE 等文件一起放进 bin。
- 解压 `Process` 的 stderr 也是在 `waitUntilExit` 之后读取（同样有小概率管道问题）。

**修复**

- 类标注 `@MainActor`；耗时的解压放到 `Task.detached`。
- 校验 HTTP 200，设置超时。
- 解压到独立临时目录，递归查找可执行文件 `tectonic`，再复制并 `chmod 755`。
- 清理下载包与解压目录。

---

### 3.6 反调试代码的常量错误

**定位**

`Utils/AntiDebug.swift`：

```swift
private static func denyPtrace() {
    let PT_DENY_ATTACH: Int32 = 0   // 错误
    let result = c_ptrace(PT_DENY_ATTACH, 0, nil, 0)
    if result == -1 { exit(1) }
}
```

macOS 的 `PT_DENY_ATTACH` 是 **31**；0 是 `PT_TRACE_ME`。而且 `ptrace` 在受限环境下失败时直接 `exit(1)` 会让 Release 应用莫名退出。

**修复**

- 常量改为 31。
- 失败不再退出；保留 `sysctl` 的 `P_TRACED` 检测。

**验证**

Release（Hardened Runtime + ad-hoc 签名）实际启动成功，未出现启动即退出。

---

### 3.7 硬编码的开发者路径

**定位**

`grep -R "/Users/zhangrui"` 命中 `TemplateManager` 与测试代码。换机器（或 CI）时模板目录不存在，开发模式判断失效。

**修复**

- `TemplateManager` 从 `#filePath` 推导源码目录，存在 `templates.json` 时作为开发模式；否则使用 `Bundle.main.resourceURL`。
- 测试改为通过 `TemplateManager().templatesDir` 获取，不再写死绝对路径。

---

### 3.8 语法高亮优先级错误

**定位**

逐条分析正则匹配与实际着色顺序：

1. 注释规则 `%.*` 会把 `\%` 当成注释开头。
2. 所有 token 先按位置排序，同位置没有稳定优先级：`\begin` 同时被环境规则和通用命令规则命中，颜色不确定。
3. 数学内容在第二轮单独上色，会把注释里的 `$...$` 也染成橙色，覆盖注释色。

**修复**

- 注释正则改为 `(?<!\\)%.*`。
- 规则带 `priority`：环境关键字 0、数学分隔符 1、命令 2、其他 3、括号 4；同位置低优先级优先。
- 注释区间单独收集，其他 token 与注释相交时跳过；数学内容跳过注释；最后再统一覆盖注释颜色。

**验证**

- 单元测试全部通过。
- 实际启动加载 `aaai.tex` 截图：命令蓝色加粗、环境紫色、正文白色，效果正常。

---

### 3.9 深浅色切换、滚动位置与编码

**定位**

- `updateNSView` 只在文本变化时重新着色，系统切换深浅色不会触发。
- 程序化替换文本（加载模板/历史）后没有恢复滚动位置。
- 读取 `.tex` 固定 UTF-8，旧文件（Latin-1/GBK）会直接报错。

**修复**

- `LaTeXTextView` 监听 `viewDidChangeEffectiveAppearance` 并重新着色。
- 替换文本时保存/恢复 `scrollView.contentView.bounds.origin`。
- 加入 `typingAttributes` 复位，避免颜色残留。
- 新增 `readText(from:)`：先让 Foundation 探测编码，失败回退 UTF-8，再回退 Latin-1。

---

### 3.10 Release 签名失败：FileProvider 元数据

**定位**

第一次打包（derived data 放在项目内 `build/`）：

```text
myleaf.app: resource fork, Finder information, or similar detritus not allowed
Command CodeSign failed with a nonzero exit code
```

检查扩展属性：

```bash
xattr -lr build/Build/Products/Release/myleaf.app
# com.apple.FinderInfo
# com.apple.fileprovider.fpfs#P
```

项目位于 macOS 桌面（iCloud/FileProvider 同步目录），Finder/同步服务给 bundle 根目录写入了 `FinderInfo`，`codesign` 拒绝签名。

**修复**

- 构建改到 `mktemp -d`（`/var/folders/...`）下，避开同步目录。
- 使用 `CODE_SIGNING_ALLOWED=NO` 构建，然后显式：

  ```bash
  xattr -cr myleaf.app
  codesign --force --sign - --options runtime \
    --entitlements myleaf/myleaf.entitlements myleaf.app
  ```

- 后续发现把 `.app` 复制回桌面 `dist/` 后，同步元数据会重新出现，导致 `codesign --verify dist/myleaf.app` 再次失败。因此发布物只保留 **DMG 与 ZIP**（两者都含已签名的 app，DMG 已验证签名），不再保留裸 `.app` 副本。

**验证**

```text
myleaf-1.4.dmg: valid on disk / satisfies its Designated Requirement
Signature=adhoc, Format=universal (x86_64 arm64), Runtime Version=15.5.0
```

从 DMG 挂载后实际启动，进程正常。

---

### 3.11 UI 自动化受限，改用 ViewModel 集成测试

**定位**

- `osascript ... System Events` 报错 `-1719`（未授予辅助功能权限）。
- 编写 XCUITest 后，应用能启动，但辅助功能树中窗口状态为 `Disabled`，点击事件不生效。
- 同时发现 SwiftUI 自定义卡片按钮的 accessibility label 是组合文案：
  `'Blank Document, Start with a basic template'`，按纯文本精确查找必然失败。

**处理**

- 删除不可靠的 UI 测试与 scheme 改动，避免把无法运行的环境问题带进仓库。
- 新增 `EditorViewModelCompileTests`：`compile()` → 等待 `isCompiling == false` → 断言 `pdfDocument != nil`、`errorMessage == nil`，覆盖从 VM 到编译服务的整条链路。
- UI 部分通过实际启动 + 截图人工确认（欢迎页、编辑器高亮、Release 启动）。

---

### 3.12 并行测试偶发失败

**定位**

全量测试偶尔出现 `EditorViewModelCompileTests` 失败，单独运行则通过；日志显示测试套件同时在两个进程中运行（`My Mac - myleaf (27863)` 与 `(27861)`）。

两个进程同时首次调用 Tectonic，共享同一个 cache 目录，存在竞争。

**修复**

把 scheme 中 `myleafTests` 的 `TestableReference` 设为 `parallelizable = "NO"`。之后连续两次全量测试通过。

> 过程中还踩了一个工具坑：一条 `perl` 替换误删了 scheme 里 `BuildableReference` 的结尾标签，导致 `xcodebuild` 报 “Scheme ... is not currently configured for the test action”。用 `git checkout` 恢复 scheme 后用精确编辑修复。

---

### 3.13 窗口状态恢复导致“幽灵文档”

**定位**

从 DMG 启动新构建时，在没有任何最近项目历史的情况下，窗口显示了一个 **Untitled + SIGGRAPH 模板内容** 的文档。

对照实验：

```bash
rm -rf ~/Library/Saved\ Application\ State/com.65zlui.myleaf.savedState
```

再次启动后正常显示欢迎页。

**根因**

AppKit 的自动窗口状态恢复把旧的 `NSTextView` 内容恢复了回来；而应用本身已经通过 `ProjectHistoryManager` 做“恢复上次项目”。两套机制冲突，且恢复出来的文本与 ViewModel 可能不一致，编译时会用到错误内容。

**修复**

增加 `AppDelegate`：

```swift
func applicationShouldSaveSecureApplicationState(_ app: NSApplication) -> Bool { false }
func applicationShouldRestoreSecureApplicationState(_ app: NSApplication) -> Bool { false }
```

由 `@NSApplicationDelegateAdaptor` 挂到 App 上，统一由应用自己的历史恢复逻辑负责。

---

### 3.14 编译等待 6 秒：不是排版慢，是引擎版本旧

**现象**

```bash
/usr/bin/time -p tectonic --outdir out tiny.tex
# real 5.34–6.94s, user 0.24–0.26s
```

CPU 只用了 0.25 秒，wall time 却是 5–7 秒。同机 Homebrew Tectonic 0.17.0
编译同一文档只要 **0.20s**。

**定位**

用 `sample <pid> 1 1` 抓取运行栈，时间全部耗在：

```text
ItarBundle::ensure_index
  → BundleCache::new
    → reqwest::blocking ... send
      → semaphore_wait
```

即 Tectonic 0.16.9 每次启动都在做 bundle index 的 HTTP 检查，
`--only-cached` 也挡不住；0.17.0 使用缓存索引，不再有这段等待。

而应用的 `detectEngine()` 按“应用内安装 → Homebrew → /usr/local”的顺序
直接返回第一个可执行文件，因此明明系统里有 0.17.0，却一直使用应用内安装的
0.16.9。

**修复**

1. `TeXEngine` 从 enum 改为 struct：`kind + url + version`。
2. `detectEngine()` 收集所有候选路径（应用内、Homebrew、`/usr/local`，
   必要时 `which`），逐个执行 `--version`，按语义版本选最新者；
   只有完全没有 Tectonic 时才使用 pdflatex。
3. 版本比较支持 `0.17.0 > 0.16.9`、`1.0.10 > 1.0.9`，缺失版本排在最后。
4. Build Log 增加：
   - `Engine version: 0.17.0`
   - `--- timings ---`：Preparation / Engine run / PDF cache / Total

**验证**

独立 harness：

```text
Selected engine: Tectonic 0.17.0
Path: /opt/homebrew/bin/tectonic
wall: 0.338s
prepare: 0.002s engine: 0.333s pdf: 0.000s total: 0.335s
```

测试套件 50 个测试从约 19 秒降到 **2.85 秒**，说明每次编译都走了 0.17 的
快速路径。Build Log 中可直接看到各阶段耗时。

> 后续可选项：在设置页显示“当前使用的引擎/版本”，并为应用内旧版
> Tectonic 提供“检查更新”按钮；对只有 0.16.x 的用户，升级后同样受益。

---

## 4. 发布构建与打包

`scripts/package-app.sh` 固化整个流程：

1. 在临时目录用 Xcode 16.4 构建 Release，通用架构 `arm64 + x86_64`。
2. `xattr -cr` 后显式 ad-hoc 签名，启用 Hardened Runtime 与项目 entitlements。
3. `codesign --verify --deep --strict` 校验。
4. 生成 DMG（含 `/Applications` 快捷方式）与 ZIP。
5. 生成 `SHA256SUMS.txt`，清理旧版本产物。

其他发布调整：

- 补全 16–1024 全套 AppIcon。
- 部署目标统一为 macOS 14.0。
- 增加 MIT LICENSE（README 一直引用但仓库缺失）。
- README 增加 Gatekeeper 说明与打包章节。

### 安装包与卸载包

`pkgbuild` 生成三个本地包，对应三种路径：

1. **`myleaf-1.4.pkg`**（完整安装）
   - 用 `--root` 构造 payload：`Applications/myleaf.app`，安装位置 `/`。
   - `preinstall` 先 `pkill -x myleaf`，避免覆盖正在运行的应用。
   - 验证方式：`pkgutil --expand-full` 解开 payload，确认 `codesign --verify`
     仍通过（payload 里的 app 签名有效）。
2. **`myleaf-uninstaller-1.4.pkg`**（完整卸载）
   - `pkgbuild --nopayload`，只用 `preinstall` 执行清理。
   - 删除 `/Applications/myleaf.app`、应用管理的 Tectonic/Pandoc、编译日志、
     Tectonic 缓存、应用缓存、偏好设置、窗口状态、旧沙盒容器。
   - 保留用户 `.tex` 项目和系统安装的 TeX/Pandoc。
3. **`myleaf-uninstaller-keepdata-1.4.pkg`**（卸载但保留数据）
   - 只删除 `/Applications/myleaf.app`。
   - 保留 `Application Support/myleaf`（工具）、`Logs/myleaf`（编译日志）、
     偏好设置/最近项目、Tectonic 缓存等，重新安装后可恢复原状态。
   - 与完整卸载共用 `/tmp/myleaf-uninstall.log`，并记录保留的路径列表。

两个卸载脚本都支持 `MYLEAF_UNINSTALL_APP_PATH` / `MYLEAF_UNINSTALL_HOME`
环境变量覆盖；在 `/tmp` 下用假目录分别实测：

- 完整卸载：应用与数据目录被删除，退出码 0。
- 保留数据：应用被删除，`Application Support`、`Logs`、偏好设置等仍在。

两个卸载包同时被复制进 DMG，分别命名为
`Uninstall myleaf.pkg` 与 `Uninstall myleaf (keep data).pkg`。

---

## 5. 运行时日志与诊断

需求：记录每次 LaTeX 编译的执行流程，并能回看。

### 实现

| 位置 | 作用 |
|------|------|
| `Utils/BuildLogStore.swift` | 将每次构建日志写入 `~/Library/Logs/myleaf/build-YYYYMMDD-HHmmss-SSS.log`，保留最近 30 份 |
| `Services/LaTeXCompiler.swift` | 日志包含开始时间、引擎与版本/路径、输入文件、工作目录、完整命令行、超时、引擎输出、退出码、分阶段耗时；失败时日志随 `CompilationError` 返回 |
| `ViewModels/EditorViewModel.swift` | 保存 `lastBuildLog` / `lastBuildLogFile` / 耗时；编译阶段文案（检测引擎 → 运行引擎 → 加载 PDF） |
| `Views/BuildLogView.swift` | 等宽字体日志面板，支持复制、在 Finder 中显示、打开日志目录 |
| `ContentView.swift` / `myleafApp.swift` | 工具栏按钮、错误面板 “Show Log”、Build 菜单 ⌘⇧L |
| OSLog | `subsystem: com.65zlui.myleaf, category: build`，可在 Console.app 查看 |

日志示例结构：

```text
myleaf build log
================
Started: 2026-11-19 00:12:31.204
Engine: Tectonic
Engine version: 0.17.0
Engine path: /opt/homebrew/bin/tectonic
Input: /path/to/project/main.tex
Working directory: /path/to/project
Command: tectonic --outdir /var/folders/.../output --keep-logs /path/to/project/main.tex
Timeout: 300s

--- engine output ---
note: Running TeX ...
...

--- result ---
Exit status: 0

--- timings ---
Preparation: 0.002s
Engine run: 0.333s
PDF cache: 0.000s
Total: 0.335s
Finished: 2026-11-19 00:12:31.539
```

### 验证

- `BuildLogStoreTests.savesLogFile`：文件创建、内容写入、出现在最近日志列表。
- 编译测试断言日志包含 `myleaf build log`、`Exit status: 0`、引擎名，且日志文件真实存在。
- ViewModel 测试断言 `lastBuildLog` 非空、`lastCompilationDuration` 有值。

### 5.2 内存占用监控（v1.3）

原先的 `MemoryMonitor` 只在 DEBUG 下每 60 秒调用两次 `leaks` CLI，
既重又会短暂挂起进程。现在改为轻量的内存采样：

- 通过 Mach `task_info(TASK_VM_INFO)` 读取：
  - `phys_footprint`：物理内存占用（与系统 `footprint` 工具一致）
  - `resident_size`、`virtual_size`
- 每 2 秒采样一次，主线程更新 `@Observable` 状态
- 启动 10 秒后写第一条持久化样本，之后每 60 秒一条：
  `~/Library/Logs/myleaf/memory-YYYYMMDD.jsonl`
- 自动保留最近 7 天
- 设置页新增 Diagnostics：
  - Current memory / Peak memory / Resident memory
  - 采样次数、Sample Now、Show log
- Release 构建同样启用（开销极低）

**验证**

- 单元测试 `MemoryMonitorTests.reportsMemoryFootprint`
- 实际运行 Debug 构建：
  - 应用采样 `phys_footprint ≈ 23 MB`
  - 系统 `/usr/bin/footprint -p <pid>` 显示 `Footprint: 22 MB`，两者一致
  - `~/Library/Logs/myleaf/memory-20261119.jsonl` 正常写入
- 现有 51 个测试全部通过

### 5.3 内存占用优化（v1.4）

**测量**

对运行中的 Release 构建使用 `footprint -p`、`vmmap -summary`：

```text
Physical footprint: 69 MB（峰值 113 MB）
IOSurface          28.2 MB
MALLOC_SMALL        8.9 MB
MALLOC_NANO         8.2 MB
MALLOC_MEDIUM       6.0 MB
MALLOC_TINY         4.1 MB
__DATA              4.2 MB
CoreUI image data   2.3 MB
```

结论：空闲内存主要是 AppKit/SwiftUI/窗口图层（IOSurface）与 malloc 区域，
应用自身可优化的空间主要在大文档/大 PDF 的峰值，而不是空闲基线。

**改动**

1. **PDF 改为文件缓存**
   - 编译成功后把 PDF 移入 `~/Library/Caches/myleaf/pdfs`（最多保留 3 份）
   - 用 `PDFDocument(url:)` 打开，不再把整份 PDF 读成 `Data` 常驻内存
   - 新预览加载后删除上一份缓存文件；新建/打开/换模板时也清理
2. **限制撤销栈**
   - `NSTextView` 默认撤销历史无上限，会保留大量全文快照
   - 在 `viewDidMoveToWindow` 中设置 `undoManager?.levelsOfUndo = 100`

**验证**

- harness：编译产物落到 `~/Library/Caches/myleaf/pdfs/preview-*.pdf`，
  `pdfByteCount` 正确，缓存文件可被 `PDFDocument` 打开
- 51 个测试全部通过
- 输出日志的 timings 阶段由 “PDF read” 改为 “PDF cache”（包含落盘时间）

> 说明：这两项主要降低大 PDF/长文档的峰值与长期增长；空闲 69 MB 中约 28 MB
> 是窗口 IOSurface，应用代码无法显著压缩。若需要进一步降低空闲内存，只能考虑
> 缩小窗口/减少图层，或改为更轻的原生 UI 架构。

---

## 6. 验证矩阵

| 检查项 | 命令/方法 | 结果 |
|--------|-----------|------|
| Debug 构建 | `xcodebuild ... build` | 通过，无警告 |
| 单元 + 集成测试 | `xcodebuild -scheme myleafTests ... test` | 全部通过（连续两次） |
| 编译成功路径 | 测试 + harness | 生成有效 `%PDF` 数据 |
| 编译失败路径 | 测试 + harness | 返回日志、退出码、日志文件 |
| 相对路径 | harness `\input{section.tex}` | 修复前失败、修复后成功 |
| 引擎版本选择 | harness `detectEngine()` | 选中 Tectonic 0.17.0（而非应用内 0.16.9） |
| 阶段耗时 | Build Log + 测试断言 | preparation / engine / pdf / total 均有值 |
| 编译耗时 | harness | 0.335s（修复前 5–7s） |
| 测试耗时 | 51 个测试 | 4.3s（修复前约 19s） |
| 内存采样 | 运行 Debug 构建 + `footprint -p` | 23 MB vs 22 MB，一致 |
| 内存日志 | 查看 `~/Library/Logs/myleaf/memory-*.jsonl` | 启动 10s 后写入，之后每分钟一条 |
| PDF 文件缓存 | harness 编译 + 检查 `~/Library/Caches/myleaf/pdfs` | 生成 preview-*.pdf，大小正确，可被 PDFKit 打开 |
| 撤销栈上限 | 代码审查 + 编辑器实际使用 | `levelsOfUndo = 100` |
| 空闲内存构成 | `footprint -p` + `vmmap -summary` | 69 MB：IOSurface 28 MB、malloc 27 MB、框架/资源 14 MB |
| Release 启动 | `open` + `pgrep` + 截图 | 正常，AntiDebug 未误杀 |
| DMG 签名 | `codesign --verify --deep --strict` | 通过 |
| DMG 启动 | 挂载后运行 | 正常 |
| 安装包 payload | `pkgutil --expand-full` + `codesign --verify` | 通过，payload 内 app 签名有效 |
| 安装包元数据 | 查看 `PackageInfo` | `com.65zlui.myleaf`，1.3，min OS 14.0，含 preinstall |
| 卸载包结构 | `pkgutil --expand-full` | 两个包均无 payload，preinstall 可执行 |
| 完整卸载逻辑 | 临时目录 + 环境变量覆盖 | 应用与数据目录被删除，退出码 0 |
| 保留数据卸载逻辑 | 临时目录 + 环境变量覆盖 | 应用被删除，工具/日志/偏好保留 |
| DMG 内容 | `hdiutil attach` | app + Applications 链接 + 两个卸载包 |
| 应用图标 | 构建产物 `AppIcon.icns` + 截图 | 已生效 |

测试数量：43（基线）→ 47（编译与 ViewModel 集成）→ 48（运行时日志存储）→ 50（引擎版本比较与阶段耗时断言）→ 51（内存采样）。

---

## 7. 提交时间线

| 提交 | 内容 |
|------|------|
| `af05f47` | 基线整理：`.gitignore`、截图、现有编辑器/README 修改 |
| `43cbf61` | 修复编译管线：管道死锁、项目感知编译、超时、PDF 内存化、安装器、反调试、模板路径、编译测试 |
| `6898973` | 编辑器：高亮优先级、深浅色、滚动、编码、ViewModel 编译测试 |
| `e36d022` | App 图标、打包脚本、macOS 14 支持、发布文档 |
| `695ac89` | MIT LICENSE |
| `fe188d3` | 打包 `.app` 副本的 FileProvider 元数据清理 |
| v1.1 提交 | 运行时编译日志、窗口状态恢复修复、pkg 安装/卸载包、本调试记录 |
| v1.2 提交 | 引擎版本探测/最新版选择 + Build Log 阶段耗时 |
| v1.3 提交 | 内存占用监控（task_info 采样 + JSONL 日志 + 设置页 Diagnostics） |
| v1.4 提交 | PDF 文件缓存 + 撤销栈上限（降低大文档/大 PDF 峰值） |

标签：`v1.0.0`（首个可分发构建）→ `v1.1.0`（运行时日志 + 调试记录）→ `v1.2.0`（引擎选择 + 阶段耗时）→ `v1.3.0`（内存监控）→ `v1.4.0`（内存优化）。

---

## 8. 发现但未处理

- **公证**：当前为 ad-hoc 签名，其他机器首次打开需要右键 → 打开。要消除提示需 Apple Developer ID + notarization。
- **pdflatex 单次编译**：交叉引用需要多趟；Tectonic 会自动 rerun，pdflatex 分支目前未做两遍编译。
- **Word 导出**：Pandoc 安装流程未做端到端验证（本机未安装 Pandoc）。
- **超大文档高亮**：每次按键仍会对全文做正则高亮；对数千行文档可能可感知延迟，后续可按可视区域/编辑行做增量高亮。
- **UI 自动化**：当前机器未授予辅助功能权限，XCUITest 无法交互；已用 ViewModel 集成测试替代。
- **旧版引擎升级**：当前只会选择“已安装的最新版”；如果机器上只有应用内 0.16.x，编译仍会慢。后续可在设置页增加“检查 Tectonic 更新”按钮。
- **监控深化**：本次只把阶段耗时写入 Build Log；OSSignposter 时间线与 JSONL 指标尚未接入，适合作为下一阶段。
