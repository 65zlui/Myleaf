# myleaf 1.1.0

A native macOS LaTeX editor for academic writing — now with a hardened,
project-aware compilation pipeline, full build logs, and a proper app icon.

## Highlights

### Compilation
- Compiles inside the document's own folder, so `\input{}`, images, and
  `.bib` files resolve exactly like a command-line build.
- Engine output is redirected to log files instead of pipes, eliminating the
  deadlock that could hang builds with verbose logs.
- Five-minute compilation timeout with graceful termination.
- PDFs are kept in memory, so temporary build folders are removed immediately.
- Works with Tectonic (with in-app one-click install) or pdflatex.

### Build logs
- Every compilation is recorded with a timestamp, engine, input path, working
  directory, exact command line, full engine output, exit status, and duration.
- Logs are persisted to `~/Library/Logs/myleaf/build-*.log` (last 30 kept) and
  can be viewed in-app via the toolbar, the error panel, or **Build → Show
  Build Log** (⌘⇧L).
- The log panel supports copy, reveal-in-Finder, and opening the logs folder.
- Compilation progress now shows the current phase (detecting engine, running
  engine, loading PDF), and phases are also written to the unified system log.

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
- Reproducible release packaging: `scripts/package-app.sh` produces a DMG, a
  ZIP, and `SHA256SUMS.txt`; both archives contain the signed `myleaf.app`.
- Hardened Runtime; ad-hoc signed (no paid Developer ID).
- Fixed the anti-debug `PT_DENY_ATTACH` constant.

### Stability
- Tectonic installer is MainActor-isolated, validates HTTP responses, extracts
  into a temp directory, locates the binary recursively, and cleans up.
- Pandoc export no longer calls `NSSavePanel` from a background executor and
  cannot deadlock on stderr.
- Removed the hardcoded developer-specific template path.
- Added compiler, build-log, and view-model integration tests.
- Unit tests run serially by default to avoid concurrent Tectonic cache
  contention.

## Installation

1. Download `myleaf-1.1.dmg` (or `myleaf-1.1.zip`).
2. Open the DMG and drag **myleaf** into **Applications**.
3. First launch only: right-click **myleaf** → **Open** if Gatekeeper blocks it,
   or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/myleaf.app
   ```
4. If no LaTeX engine is found, open Settings (⌘,) and install Tectonic with
   one click.

**Requirements:** macOS 14.0 or later, Apple Silicon or Intel.

## Verification

- `codesign --verify --deep --strict /Applications/myleaf.app`
- Checksums for the DMG and ZIP are published in `SHA256SUMS.txt`.

## Known limitations

- Builds are ad-hoc signed, so Gatekeeper shows an "unidentified developer"
  warning on other Macs until a Developer ID certificate is configured.
- Word export requires Pandoc (installed from within the app).
- pdflatex fallback runs a single pass; Tectonic performs automatic reruns.
