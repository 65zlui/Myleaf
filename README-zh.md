# myleaf

> 一款原生 macOS LaTeX 编辑器，专注于学术写作体验。

myleaf 是使用 SwiftUI 构建的原生 macOS LaTeX 编辑器，提供开箱即用的 LaTeX 编译、语法高亮、PDF 预览和模板管理功能。无需手动安装 TeX 发行版，应用内置 Tectonic 引擎自动安装机制。

![macOS](https://img.shields.io/badge/platform-macOS_14+-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

---

## 功能特性

### 📝 LaTeX 编辑器
- **语法高亮**：注释、命令、环境、数学模式、括号等分类着色，支持深色/浅色模式
- **原生编辑体验**：基于 NSTextView，支持撤销/重做、自动缩进、等宽字体
- **智能粘贴**：粘贴时自动过滤富文本格式，即时语法高亮

### 📄 PDF 预览
- **实时预览**：PDFKit 驱动的 PDF 渲染，编译完成后即时显示
- **分栏布局**：可拖拽分割的编辑器 + PDF 预览分栏

### 🔧 LaTeX 编译
- **多引擎支持**：Tectonic（首选）→ pdflatex 自动降级
- **自动检测**：启动时自动检测可用引擎并显示状态指示
- **一键安装**：应用内下载安装 Tectonic（从 GitHub Release 获取）
- **快捷键**：⌘B 一键编译

### 📦 模板系统
- **19 个内置模板**，分三类：
  - **会议论文**（8个）：AAAI、NeurIPS、CHI、SIGGRAPH、UbiComp、MobiSys、MobiCom、CCF 中文
  - **期刊论文**（3个）：SCI、EI、IEEE Transactions
  - **学位论文**（8个）：理工科/文科/艺术类本科及硕士学位论文模板（中英双语）
- 新建文档时可从模板选择器快速选取

### 📤 导出
- **PDF 导出**：将当前 PDF 预览导出到文件
- **Word 导出**：通过 Pandoc 将 LaTeX 转换为 DOCX，支持应用内一键安装 Pandoc

### 📚 BibTeX 引用管理
- 导入 `.bib` 文件，解析为结构化条目
- 搜索和批量选择引用
- 自动在 `\end{document}` 前插入 `\cite{key}`

### ⚙️ 项目管理
- **最近项目**：记录最近打开的 10 个文件
- **自动保存**：每 30 秒自动保存（可开关）
- **启动恢复**：自动打开上次编辑的项目

### 🛡️ 安全与调试
- **Release 加固**：Hardened Runtime、符号剥离、反调试保护（ptrace）
- **Debug 诊断**：内存泄漏检测（`leaks` 命令行工具）、Deinit 日志追踪

---

## 安装

### 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- Apple Silicon (ARM64) 或 Intel (x86_64)

### 下载

从 [Releases](https://github.com/65zlui/myleaf/releases) 页面下载最新版 `.app` 文件，拖入 Applications 文件夹即可。

> **首次启动**：应用会自动检测 LaTeX 引擎。如未安装，可在设置中一键安装 Tectonic（约 25MB）。

### 从源码构建

```bash
git clone https://github.com/65zlui/myleaf.git
cd myleaf
open myleaf.xcodeproj
```

在 Xcode 中选择 `myleaf` scheme，按 ⌘R 运行，或选择 Product → Archive 构建发布版本。

---

## 使用指南

### 快捷键

| 操作 | 快捷键 |
|------|--------|
| 新建文档 | ⌘N |
| 从模板新建 | ⌘⇧N |
| 打开文件 | ⌘O |
| 保存 | ⌘S |
| 另存为 | ⌘⇧S |
| 编译 | ⌘B |
| 导出 PDF | ⌘E |
| 导出 Word | ⌘⇧E |
| 设置 | ⌘, |

### 工作流程

1. **新建文档**：使用欢迎页的「空白文档」或「从模板开始」
2. **编辑 LaTeX**：在左侧编辑器中撰写内容，语法自动高亮
3. **编译预览**：按 ⌘B 编译，右侧即时显示 PDF
4. **导出分享**：通过工具栏的 Export 菜单导出 PDF 或 Word
5. **管理引用**：点击 BibTeX 按钮导入 `.bib` 文件并插入引用

---

## 技术栈

| 层级 | 技术 |
|------|------|
| UI 框架 | SwiftUI + AppKit (NSViewRepresentable) |
| 架构 | MVVM + Service Layer |
| 状态管理 | `@Observable` (iOS 17+) |
| PDF 渲染 | PDFKit |
| 编辑器 | NSTextView + 正则语法高亮 |
| LaTeX 引擎 | Tectonic / pdfLaTeX |
| Word 导出 | Pandoc (LaTeX → DOCX) |
| 进程管理 | `Process` + 管道通信 |
| 持久化 | UserDefaults (项目历史) |
| 调试 | `leaks` CLI 内存检测 |

### 外部依赖

**编译时**：无（仅使用 Apple 原生框架：Foundation、SwiftUI、PDFKit、AppKit）

**运行时**：
- Tectonic（可选，应用内自动安装）
- pdfLaTeX（可选，需系统安装 MacTeX）
- Pandoc（可选，应用内自动安装）

---

## 目录结构

```
myleaf/
├── myleaf/                     # 主应用
│   ├── Models/                 # 数据模型
│   ├── ViewModels/             # 状态管理 (EditorViewModel)
│   ├── Views/                  # SwiftUI 视图
│   ├── Services/               # 业务服务层
│   ├── Utils/                  # 工具类
│   └── Resources/Templates/    # 19 个 LaTeX 模板
├── myleafTests/                # 单元测试
├── myleafUITests/              # UI 测试
└── myleaf.xcodeproj            # Xcode 项目
```

---

## 测试

```bash
xcodebuild -scheme myleafTests -configuration Debug test
```

包含 43+ 个单元测试，覆盖：
- 模板加载与分类
- BibTeX 解析
- 项目历史管理
- 文档模型验证

---

## 许可证

[MIT License](LICENSE)

---

## 作者

**张锐** — [65zlui](https://github.com/65zlui)

---

*让 LaTeX 写作更简单。*
