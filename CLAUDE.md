# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ghostty is a cross-platform terminal emulator written in Zig with platform-native GUIs (Swift/AppKit for macOS, GTK4 for Linux). The core terminal emulation logic lives in a shared Zig library (libghostty), which platform-specific shells consume via a C API.

## Custom Fork Notes

This is a custom fork where the app has been renamed from **Ghostty** to **Ghosttown**. The display name is configured in `macos/Ghostty.xcodeproj/project.pbxproj` via `INFOPLIST_KEY_CFBundleDisplayName` and `INFOPLIST_KEY_CFBundleName`. UI-facing references (MainMenu.xib, AboutView, TerminalView, CommandPalette, ErrorView, UpdatePopoverView, IntentPermission) have also been updated.

## Custom Feature: In-Pane Editor

터미널 패인 안에서 파일을 편집할 수 있는 코드 에디터 + Notion 스타일 마크다운 에디터. 모든 코드는 `macos/Sources/Features/Editor/` 아래에 있다.

### 구성 요소

| 파일 | 역할 |
|------|------|
| `EditorPaneView.swift` | 에디터 메인 UI (헤더 바 + 웹뷰 컨테이너). 저장 상태 표시, 닫기 버튼 |
| `EditorState.swift` | 상태 관리 (`filePicker` ↔ `editing`). `FileInfo` 구조체, `MarkdownViewMode` enum |
| `EditorWebView.swift` | WKWebView 기반 JS↔Swift 브릿지. 메시지 핸들러: `save`, `autoSave`, `switchMode`, `close`, `ready` |
| `EditorWKWebView.swift` | WKWebView 서브클래스. Cmd+B(닫기), Cmd+P(퀵오픈) 키 인터셉트 |
| `Resources/editor.html` | **Monaco** 코드 에디터 (CDN `0.52.2`). 범용 코드 편집 |
| `Resources/blocknote.html` | **BlockNote** 마크다운 에디터 (로컬 번들). Notion 스타일 블록 편집 |
| `Resources/blocknote-bundle.js/css` | BlockNote + React 로컬 번들 (CDN 의존성 없음) |
| `QuickOpenView.swift` | Cmd+P 퀵오픈 오버레이. 파일 검색 + 결과 리스트 |
| `FileScanner.swift` | 비동기 디렉토리 스캐너 (max 50,000 파일). `.git`, `node_modules` 등 제외 |
| `FuzzyMatcher.swift` | 순수 Swift 퍼지 매칭 알고리즘. 상위 50개 결과 반환 |
| `FilePickerView.swift` | 사이드바 파일 트리 (터미널과 분할 표시) |
| `EditorLanguageDetection.swift` | 파일 확장자 → Monaco 언어 ID 매핑 |

### 아키텍처

```
SurfaceView (editorState: EditorState?)
  ├─ nil → 일반 터미널
  └─ not nil
       ├─ .filePicker → SplitView { Terminal | FilePickerView }
       └─ .editing(FileInfo) → EditorPaneView { header + EditorWebView }
                                  ├─ .md 파일: blocknote.html (기본) ↔ editor.html (Cmd+E 전환)
                                  └─ 기타 파일: editor.html (Monaco)
```

**JS↔Swift 브릿지 흐름:**
1. Swift가 HTML 로드 → JS에서 `ready` 메시지 전송
2. Swift가 `initEditor()`, `setContent()`/`setMarkdown()`, `applyGhosttyConfig()` 호출
3. 사용자 편집 → `autoSave` (1초 디바운스) 또는 `save` (Cmd+S) 메시지로 Swift에 전달

### 키보드 단축키

| 단축키 | 동작 | 컨텍스트 |
|--------|------|----------|
| `Cmd+S` | 저장 (UI 피드백 포함) | 양쪽 에디터 |
| `Cmd+E` | BlockNote ↔ Monaco 전환 | 마크다운 파일만 |
| `Cmd+B` | 에디터 닫고 터미널 복귀 | EditorWKWebView |
| `Cmd+P` | 퀵오픈 (파일 검색) | EditorWKWebView |

### 알려진 이슈 및 워크어라운드

**BlockNote 마크다운 라운드트립 손실**: `blocksToMarkdownLossy()` 내부의 `remark-stringify`가 리스트 마커를 `*`로, 줄바꿈을 `\`(hard break)로 변환함. `blocknote.html`의 `normalizeMarkdown()` 후처리 함수로 보정:
- `* ` → `- ` (thematic break 패턴 `* * *`은 보존)
- trailing `\` 제거 (홀수 개만 — 짝수는 이스케이프 쌍이므로 보존)
- fenced 코드 블록 내부는 건너뜀

**테마 동기화**: 터미널의 `fontSize`, `fontFamily`, `bgColor`, `fgColor`를 `applyGhosttyConfig()`로 에디터에 전달. BlockNote는 CSS 변수, Monaco는 커스텀 테마로 적용.

### 수정 가이드

- **Monaco 에디터 수정**: `Resources/editor.html` — CDN 기반이므로 HTML 내 JS 수정
- **BlockNote 에디터 수정**: `Resources/blocknote.html` — 로컬 번들 위의 얇은 JS 레이어
- **BlockNote 번들 업데이트**: `blocknote-bundle.js/css` 교체 (별도 빌드 필요)
- **새 키보드 단축키 추가**: `editor.html`/`blocknote.html`의 `keydown` 이벤트 + `EditorWKWebView.swift`의 `performKeyEquivalent`
- **새 JS→Swift 메시지**: `EditorWebView.swift`의 `Coordinator.userContentController(_:didReceive:)` 에 핸들러 추가
- **파일 탐색 제외 패턴**: `FileScanner.swift`의 `ignoredDirectories` 배열

## Build Commands

Ghostty uses the Zig build system. Minimum Zig version: **0.15.2**.

| Command | Description |
|---------|-------------|
| `zig build` | Build (debug mode by default — do not add `-Doptimize` flags for development) |
| `zig build run` | Build and run |
| `zig build test` | Run all unit tests |
| `zig build test -Dtest-filter=<name>` | Run specific tests by name pattern |
| `zig build run-valgrind` | Run under Valgrind (Linux, memory leak checking) |
| `zig build update-translations` | Update translation strings |

### libghostty-vt (standalone VT library)

| Command | Description |
|---------|-------------|
| `zig build lib-vt` | Build libghostty-vt |
| `zig build test-lib-vt` | Run libghostty-vt tests |
| `zig build test-lib-vt -Dtest-filter=<name>` | Filter libghostty-vt tests |

When working on libghostty-vt, do not build the full app. For C-only changes, skip Zig tests and build the examples instead.

### macOS App

- Do **not** use `xcodebuild` directly — use `zig build` for everything
- Requires **Xcode 26** with the **macOS 26 SDK**, iOS SDK, and Metal Toolchain
- Select Xcode: `sudo xcode-select --switch /Applications/Xcode.app`
- `zig build run` builds and runs the macOS app
- `zig build test` also runs Xcode tests

### Production Build (macOS)

| Command | Description |
|---------|-------------|
| `zig build -Doptimize=ReleaseFast` | 릴리즈 빌드 (앱 번들 생성) |
| `zig build run -Doptimize=ReleaseFast` | 릴리즈 빌드 후 바로 실행 |

- `-Doptimize=ReleaseFast`는 Xcode configuration `ReleaseLocal`로 매핑됨
- 빌드된 앱 번들 위치: `macos/build/ReleaseLocal/Ghostty.app` (Dock 표시 이름은 Ghosttown)
- `/Applications/`에 설치: `cp -R macos/build/ReleaseLocal/Ghostty.app /Applications/`
- 원스텝 빌드+설치 스크립트: `./build-production.sh` (--open 플래그로 설치 후 바로 실행)

### Formatting & Linting

| Tool | Command | Scope |
|------|---------|-------|
| zig fmt | `zig fmt .` | Zig code |
| Prettier | `prettier --write .` | Docs, YAML, non-Zig files |
| Alejandra | `alejandra .` | Nix files |
| ShellCheck | `shellcheck --check-sourced --severity=warning <files>` | Shell scripts |

Nix users can prefix with `nix develop -c` for version-matched tools.

### Key Build Options

- `-Dapp-runtime=none|gtk` — Platform runtime (none for library/macOS, gtk for Linux)
- `-Drenderer=opengl|metal` — GPU backend
- `-Dfont-backend=freetype|coretext|coretext_freetype` — Font rendering
- `-Dsimd=true|false` — SIMD acceleration
- `-Di18n=true|false` — Internationalization
- `-Demit-macos-app` / `-Demit-xcframework` — macOS artifact types

### Logging

- `GHOSTTY_LOG` env var controls log destinations: `stderr`, `macos`, or combined with commas
- Prefix with `no-` to disable (e.g., `no-stderr`); `true`/`false` toggles all
- Debug builds log to stderr by default; release builds do not
- macOS unified log: `sudo log stream --level debug --predicate 'subsystem=="com.mitchellh.ghostty"'`

## Architecture

### Core-to-Shell Model

```
┌─────────────────────────────────────────────┐
│  Platform Shell (Swift/AppKit or GTK4)      │
├─────────────────────────────────────────────┤
│  C API boundary (include/ghostty.h)         │
├─────────────────────────────────────────────┤
│  libghostty (Zig core)                      │
│  ┌──────────┬──────────┬────────┬─────────┐ │
│  │ terminal │ renderer │  font  │  input  │ │
│  └──────────┴──────────┴────────┴─────────┘ │
└─────────────────────────────────────────────┘
```

### Directory Layout

- **`src/`** — Shared Zig core (terminal emulation, rendering, fonts, input, config)
- **`src/terminal/`** — Terminal state machine, ANSI/VT parser, screen buffers, scrollback (PageList)
- **`src/renderer/`** — GPU backends: Metal (`Metal.zig`), OpenGL (`OpenGL.zig`), with shared logic in `generic.zig`
- **`src/font/`** — Font discovery, glyph atlasing, text shaping (HarfBuzz), font face backends
- **`src/input/`** — Keybinding system (`Binding.zig`), key encoding, Kitty keyboard protocol
- **`src/apprt/`** — App runtime abstraction layer
  - `embedded.zig` — C API wrapper used by macOS Swift code
  - `gtk/` — GTK4 implementation for Linux/FreeBSD
  - `none.zig` — No-op runtime for tests/library builds
- **`src/config/`** — Configuration parsing (`~/.config/ghostty/config`)
- **`src/build/`** — Modular build system components
- **`macos/`** — macOS Swift/AppKit application
  - `Sources/App/` — AppDelegate, entry point
  - `Sources/Ghostty/` — Surface wrappers bridging Swift ↔ C API
  - `Sources/Features/` — Terminal windows, settings, command palette, etc.
- **`include/ghostty.h`** — Public C API header (the boundary between Zig core and platform code)

### Compile-Time Dispatching

Platform and backend selection happens at compile time via `build_config`, producing zero-cost abstractions:

```zig
// No runtime conditionals — each build has exactly one implementation
pub const runtime = switch (build_config.app_runtime) { .none, .gtk, ... };
pub const Renderer = switch (build_config.renderer) { .metal, .opengl, ... };
```

### Threading Model

Each terminal surface runs three threads:
- **Main thread** — GUI event loop (Cocoa/GTK), processes user input
- **Renderer thread** — GPU command submission, driven by dirty flags
- **I/O thread** — Reads/writes PTY, feeds bytes through parser into terminal state

Inter-thread communication uses message queues (`BlockingQueue`) with copyable structs.

### Data Flow

```
Shell process ←→ PTY ←→ I/O thread → Parser → Terminal state → dirty flags → Renderer → GPU
                                                     ↑
GUI input events → Surface → Binding check → Key encoding → PTY write
```

## Code Style

- Zig code: `zig fmt` (standard Zig formatting)
- Swift: 4-space indentation, trim trailing whitespace
- Shell scripts: 2-space indentation
- See `.editorconfig` for details

## AI Policy

All AI usage must be disclosed with tool name. AI-assisted PRs must reference accepted issues and be fully human-verified. See `AI_POLICY.md` for full policy.

## Agent Commands

The `.agents/commands/` directory provides vetted prompts:
- **`/gh-issue <number/url>`** — Diagnose a GitHub issue and suggest a plan (planning only, no code)
- **`/review-branch`** — Review branch changes for code quality issues (review only, no code)
