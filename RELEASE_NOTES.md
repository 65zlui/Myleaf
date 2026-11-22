# myleaf 0.1.0

**First public release.** A native macOS LaTeX editor for academic writing,
with project-aware compilation, build logs and phase timings, automatic
selection of the newest installed Tectonic engine, process memory diagnostics,
a visual Performance panel, and proper install/uninstall packages.

> Versioning note: internal development iterations were tagged `v1.x`; the
> first public release is numbered **0.1.0**.

## Highlights

### Reliability
- Settings (⌘,) opens from the welcome screen as well as the editor; the menu
  uses a scene-level value instead of a view-focused one.
- Saved window frames that fall outside the visible screen are recentered or
  clamped at launch and whenever the window becomes key.

### Upgrade safety
- The `.pkg` preinstall script quits myleaf and removes older `myleaf*.app`
  copies from `/Applications` and `~/Applications` before the new bundle is
  written, so versions never sit side by side.
- Settings → General → Installation shows the running version/path, lists all
  registered copies found by LaunchServices (including Xcode build outputs),
  and warns when more than one is present.

### Compilation
- Compiles inside the document's own folder, so `\input{}`, images, and
  `.bib` files resolve exactly like a command-line build.
- Engine output is redirected to log files instead of pipes, eliminating the
  deadlock that could hang builds with verbose logs.
- Five-minute compilation timeout with graceful termination.
- PDFs are kept in memory, so temporary build folders are removed immediately.
- Works with Tectonic (with in-app one-click install) or pdflatex.

### Performance
- Engine detection now probes every installed Tectonic build with
  `--version` and selects the newest one (app-installed, Homebrew, or
  `/usr/local`), falling back to pdflatex only when no Tectonic is available.
- This matters: on the test machine Tectonic **0.16.9** spent 5–7 s per run on
  a bundle-index HTTP check even for a one-line document, while **0.17.0**
  completed the same warm compile in 0.20–0.37 s. The app previously preferred
  an older app-installed build over a newer system build.
- Compile wall time is broken down into preparation, engine run, PDF cache, and
  total, so regressions are visible at a glance.
- Measured result: a tiny warm document went from ~5–7 s to **~0.33 s**, and
  the 50-test suite dropped from ~19 s to **~2.9 s**.

### Build logs
- Every compilation is recorded with a timestamp, engine + version, input
  path, working directory, exact command line, full engine output, exit
  status, per-phase timings, and total duration.
- Logs are persisted to `~/Library/Logs/myleaf/build-*.log` (last 30 kept) and
  can be viewed in-app via the toolbar, the error panel, or **Build → Show
  Build Log** (⌘⇧L).
- The log panel supports copy, reveal-in-Finder, and opening the logs folder.
- Compilation progress now shows the current phase (detecting engine, running
  engine, loading PDF), and phases are also written to the unified system log.

### Diagnostics
- Settings is now tabbed (General / Tools / Performance).
- The **Performance** tab shows a live physical-footprint chart with selectable
  1/5/15/30-minute windows, current/peak/resident counters, and a "Sample Now"
  action.
- A per-compile chart breaks each build into preparation / engine / PDF cache
  time, with a recent-build list (status, engine version, duration, PDF size),
  average of the last five successful builds, and a Clear action.
- Footprint is sampled every 2 s with `task_info(TASK_VM_INFO)` (very low
  overhead) and published to SwiftUI.
- One sample per minute is persisted to
  `~/Library/Logs/myleaf/memory-YYYYMMDD.jsonl`; the last 7 days are kept.
- The previous automatic `leaks` CLI loop (which suspended the process every
  minute) has been removed; memory monitoring is now lightweight and also
  available in Release builds.

### Memory optimizations
- PDF previews are now file-backed: each compile is moved to
  `~/Library/Caches/myleaf/pdfs` (max 3 files) and opened with
  `PDFDocument(url:)` instead of retaining a full `Data` copy. The previous
  preview file is removed when a new one is shown.
- The editor's undo history is capped at 100 levels; NSTextView's default is
  unlimited, which retains many full snapshots while editing large documents.
- Profiling with `footprint`/`vmmap` shows the idle process at ~69 MB:
  ~28 MB IOSurface (window/layer buffers), ~27 MB malloc zones, and ~14 MB
  frameworks/assets. Idle memory is therefore close to the AppKit/SwiftUI
  floor; the largest controllable wins are large-PDF and long-editing peaks.

### Editor
- Syntax highlighting now gives comments the final word, ignores escaped `%`,
  and colors `\begin`/`\end` and math delimiters correctly.
- Re-highlights automatically when macOS switches between light and dark mode.
- Preserves scroll position and cursor when a template or recent project is
  loaded.
- Opens legacy .tex files using detected encodings with a Latin-1 fallback.

### App & packaging
- New app icon (all macOS sizes).
- Universal binary: Apple Silicon + Intel.
- Minimum supported macOS is now 14.0 (Sonoma), matching the README.
- Reproducible release packaging: `scripts/package-app.sh` produces an
  installer `.pkg`, a full uninstaller `.pkg`, a keep-data uninstaller `.pkg`,
  a DMG, a ZIP, and `SHA256SUMS.txt`.
- Three supported macOS modes: full install, full uninstall (app + data), and
  uninstall-while-keeping-data (app only; settings, history, tools, and logs
  are preserved for the next install).
- The installer package puts myleaf in `/Applications`; the full uninstaller
  removes the bundle, app-managed tools, build logs, caches, preferences,
  saved state, and the legacy sandbox container. Projects and system
  TeX/Pandoc installs are left untouched.
- The DMG includes both uninstaller packages.
- Hardened Runtime; ad-hoc signed (no paid Developer ID).
- Fixed the anti-debug `PT_DENY_ATTACH` constant.

### Stability
- Tectonic installer is MainActor-isolated, validates HTTP responses, extracts
  into a temp directory, locates the binary recursively, and cleans up.
- Pandoc export no longer calls `NSSavePanel` from a background executor and
  cannot deadlock on stderr.
- Removed the hardcoded developer-specific template path.
- Added compiler, build-log, memory-monitor, and view-model integration tests.
- Unit tests run serially by default to avoid concurrent Tectonic cache
  contention.

## Installation

Choose one:

- **Installer package (recommended):** double-click `myleaf-0.1.pkg` and follow
  the Installer. myleaf is installed to `/Applications`.
- **DMG:** open `myleaf-0.1.dmg` and drag **myleaf** into **Applications**.
- **ZIP:** unzip `myleaf-0.1.zip` and move **myleaf** to **Applications**.

First launch only: right-click **myleaf** → **Open** if Gatekeeper blocks it,
or run:

```bash
xattr -dr com.apple.quarantine /Applications/myleaf.app
```

If no LaTeX engine is found, open Settings (⌘,) and install Tectonic with one
click.

## Uninstall

**Full uninstall** — double-click `myleaf-uninstaller-0.1.pkg` (DMG:
`Uninstall myleaf.pkg`). It quits myleaf and removes:

- `/Applications/myleaf.app`
- `~/Library/Application Support/myleaf` (Tectonic/Pandoc installed by the app)
- `~/Library/Logs/myleaf`
- Tectonic cache, app cache, preferences, saved state, and the legacy sandbox
  container

**Uninstall but keep data** — double-click
`myleaf-uninstaller-keepdata-0.1.pkg` (DMG: `Uninstall myleaf (keep data).pkg`).
It removes only `/Applications/myleaf.app`; tools, build logs, preferences,
recent-project history, and caches remain so a later install restores your
setup.

`.tex` projects and system TeX/Pandoc installations are never removed. Manual
commands for both modes are listed in the README.

**Requirements:** macOS 14.0 or later, Apple Silicon or Intel.

## Verification

- `codesign --verify --deep --strict /Applications/myleaf.app`
- Checksums for the DMG and ZIP are published in `SHA256SUMS.txt`.

## Known limitations

- Builds and packages are ad-hoc signed, so Gatekeeper shows an "unidentified
  developer" warning on other Macs until Developer ID certificates are
  configured. Right-click → Open works for both the app and the `.pkg`.
- Word export requires Pandoc (installed from within the app).
- pdflatex fallback runs a single pass; Tectonic performs automatic reruns.
