# myleaf

> A native macOS LaTeX editor crafted for academic writing.

myleaf is a native macOS LaTeX editor built with SwiftUI, offering out-of-the-box LaTeX compilation, syntax highlighting, PDF preview, and template management. No manual TeX distribution installation required — the app features automatic Tectonic engine installation.

![macOS](https://img.shields.io/badge/platform-macOS_14+-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

---

## Features

### LaTeX Editor
- **Syntax highlighting**: Color-coded tokens for comments, commands, environments, math mode, and braces with dark/light mode support
- **Native editing experience**: NSTextView-based with undo/redo, auto-indent, monospaced font
- **Smart paste**: Automatically strips rich text formatting on paste, with instant syntax highlighting

### PDF Preview
- **Live preview**: PDFKit-powered rendering, displayed immediately after compilation
- **Split-pane layout**: Draggable divider between editor and PDF preview

### LaTeX Compilation
- **Multi-engine support**: Tectonic (preferred) with automatic fallback to pdflatex
- **Auto-detection**: Detects available engines on launch with status indicator
- **One-click install**: In-app Tectonic download and installation from GitHub Releases
- **Shortcut**: Cmd+B to compile

### Template System
- **19 built-in templates** in three categories:
  - **Conference** (8): AAAI, NeurIPS, CHI, SIGGRAPH, UbiComp, MobiSys, MobiCom, CCF Chinese
  - **Journal** (3): SCI, EI, IEEE Transactions
  - **Thesis** (8): Bilingual Chinese/English templates for Science, Engineering, Liberal Arts, and Fine Arts — both Bachelor's and Master's levels
- Quick template selection when creating new documents

### Export
- **PDF export**: Save the current PDF preview to a file
- **Word export**: Convert LaTeX to DOCX via Pandoc, with in-app Pandoc installation

### BibTeX Reference Management
- Import `.bib` files with structured entry parsing
- Search and batch-select citations
- Automatic `\cite{key}` insertion before `\end{document}`

### Project Management
- **Recent projects**: Remembers the last 10 opened files
- **Auto-save**: Automatic save every 30 seconds (toggleable)
- **Session restore**: Reopens the last edited project on launch

### Security & Diagnostics
- **Release hardening**: Hardened Runtime, symbol stripping, anti-debug protection (ptrace)
- **Debug diagnostics**: Memory leak detection via the `leaks` CLI tool, deinit logging

---

## Installation

### System Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (ARM64) or Intel (x86_64)

### Download

Grab the latest `.app` bundle from the [Releases](https://github.com/65zlui/myleaf/releases) page and drag it into your Applications folder.

> **First launch**: The app will automatically detect available LaTeX engines. If none are found, you can install Tectonic with one click in Settings (~25MB download).

### Build from Source

```bash
git clone https://github.com/65zlui/myleaf.git
cd myleaf
open myleaf.xcodeproj
```

Select the `myleaf` scheme in Xcode, press Cmd+R to run, or choose Product > Archive for a release build.

---

## Usage Guide

### Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| New Document | Cmd+N |
| New from Template | Cmd+Shift+N |
| Open File | Cmd+O |
| Save | Cmd+S |
| Save As | Cmd+Shift+S |
| Compile | Cmd+B |
| Export PDF | Cmd+E |
| Export Word | Cmd+Shift+E |
| Settings | Cmd+, |

### Workflow

1. **Create a document**: Use the welcome screen to start blank or pick a template
2. **Edit LaTeX**: Write your content in the editor with automatic syntax highlighting
3. **Compile & preview**: Press Cmd+B to compile — the PDF renders instantly on the right
4. **Export**: Use the Export menu in the toolbar for PDF or Word output
5. **Manage references**: Click the BibTeX button to import `.bib` files and insert citations

---

## Technology Stack

| Layer | Technology |
|-------|-----------|
| UI Framework | SwiftUI + AppKit (NSViewRepresentable) |
| Architecture | MVVM + Service Layer |
| State Management | `@Observable` (iOS 17+) |
| PDF Rendering | PDFKit |
| Text Editor | NSTextView with regex syntax highlighting |
| LaTeX Engine | Tectonic / pdfLaTeX |
| Word Export | Pandoc (LaTeX to DOCX) |
| Process Management | `Process` with pipe communication |
| Persistence | UserDefaults (project history) |
| Debugging | `leaks` CLI memory analysis |

### Dependencies

**Compile-time**: None (uses only Apple frameworks: Foundation, SwiftUI, PDFKit, AppKit)

**Runtime**:
- Tectonic (optional, auto-installable)
- pdfLaTeX (optional, requires system MacTeX installation)
- Pandoc (optional, auto-installable)

---

## Project Structure

```
myleaf/
├── myleaf/                     # Main application
│   ├── Models/                 # Data models
│   ├── ViewModels/             # State management (EditorViewModel)
│   ├── Views/                  # SwiftUI views
│   ├── Services/               # Business logic services
│   ├── Utils/                  # Utility classes
│   └── Resources/Templates/    # 19 LaTeX templates
├── myleafTests/                # Unit tests
├── myleafUITests/              # UI tests
└── myleaf.xcodeproj            # Xcode project
```

---

## Testing

```bash
xcodebuild -scheme myleafTests -configuration Debug test
```

43+ unit tests covering:
- Template loading and categorization
- BibTeX file parsing
- Project history management
- Document model validation

---

## License

[MIT License](LICENSE)

---

## Author

**Zhang Rui** — [65zlui](https://github.com/65zlui)

---

*Making LaTeX writing simpler.*
