# Progress

Status legend: not started / in progress / done / blocked.

How to resume: read this file and `git log --oneline`, then continue from the first unfinished item. Nothing below is marked done unless it was built and run on this machine.

## Machine and toolchain (verified 2026-09-04)

- macOS 26.6.2 (25G83), Xcode 26.6 (17F113), Swift 6.3.3, macOS SDK 26.5
- Apple M5 Pro, 24 GB unified memory, built-in notched display 3024x1964
- XcodeGen 2.46.0 at /usr/local/bin/xcodegen generates `Nomi.xcodeproj` from `project.yml`
- Signing: "Apple Development: mehulfursule@gmail.com (7C4328F4MF)", team MACDPWQG37, valid until 2027-08-14
- Deployment target: macOS 15.0 (mlx-swift-lm needs 14+, MCP SDK 13+, nothing here needs 26)
- Package versions chosen: mlx-swift-lm 3.31.4 (pulls mlx-swift 0.31.6), modelcontextprotocol/swift-sdk 0.12.1

## Decisions

- Bundle identifier `com.mehulfursule.nomi`, product name `Nomi`. Stable across builds so TCC grants survive rebuilds.
- Not sandboxed, hardened runtime on. Accessibility automation does not work inside the App Sandbox.
- App is `LSUIElement` (no Dock icon). A status item gives access to Settings and Quit.
- Unit tests are hosted by the app target. The app skips panel creation when it detects the test runner.
- Displays without a notch get a top-centre island sized like a typical housing so the interaction is the same.
- The notch window keeps one fixed frame (largest open size). Transparent pixels pass clicks through (verified with `NSWindow.windowNumber(at:)`), so resizing the window per state is unnecessary and avoided a SwiftUI layout crash.
- Commits go on `main`: single contributor, fresh repository, and the resume flow reads a linear `git log`.

## Phase 1: Shell

| # | Item | Status | Verified by |
|---|------|--------|-------------|
| 1 | Xcode project, native .app, signing, .gitignore | done | `xcodebuild build` and `xcodebuild test` succeed; `codesign -dv` shows team MACDPWQG37, hardened runtime, no sandbox |
| 2 | Notch panel: idle / hover / open, geometry on notched and external displays | done | 11 geometry tests pass; pixel measurement of screenshots: idle 663-848 x 0-32 pt equals housing, hover 659-852 x 0-36, open 545-965 wide; hit-test probe shows transparent pixels pass clicks through |
| 3 | Global shortcut (Option+Space, configurable) | not started | |
| 4 | Settings window skeleton, onboarding skeleton | not started | |
| 5 | Screenshot every state and review | not started | |

## Phase 2: Local intelligence

| # | Item | Status | Verified by |
|---|------|--------|-------------|
| 6 | ModelManager: download, progress, resume, verify, remove | not started | |
| 7 | Streaming chat through MLX with cancellation | not started | |
| 8 | Structured tool calling via MLXLMCommon | not started | |
| 9 | System, file, clipboard, weather tools | not started | |
| 10 | Confirmation policy and risk levels | not started | |

## Phase 3: Seeing and acting

| # | Item | Status | Verified by |
|---|------|--------|-------------|
| 11 | Accessibility inspection and generic UI action tools | not started | |
| 12 | Permissions UI with real state | not started | |
| 13 | What's on my screen: capture, OCR, layout mapping | not started | |
| 14 | Optional local vision model | not started | |

## Phase 4: Knowledge

| # | Item | Status | Verified by |
|---|------|--------|-------------|
| 15 | Document ingestion (PDF, text, Markdown, HTML, URLs) | not started | |
| 16 | Local embeddings, SQLite, hybrid retrieval | not started | |
| 17 | Documentation-aware agent flow for frontmost app | not started | |
| 18 | Learned skills | not started | |

## Phase 5: Extensions and finish

| # | Item | Status | Verified by |
|---|------|--------|-------------|
| 19 | MCP client (stdio) | not started | |
| 20 | Calendar and Reminders | not started | |
| 21 | Voice input, optional spoken output | not started | |
| 22 | Performance and memory pass | not started | |
| 23 | Tests, README, cleanup, final verification | not started | |

## Needs manual action

Nothing yet.

## Log

- 2026-09-04: Inspected machine, toolchain, certificates, package registries. Wrote this file.
- 2026-09-04: First panel attempt resized the window per state and crashed inside NSHostingView layout (setFrame during a display cycle). Replaced with a fixed window frame.
- 2026-09-04: `isFloatingPanel = true` resets `level`; the level must be set afterwards or the surface sits under the menu bar.
- 2026-09-04: zsh has a `log` builtin. Use `/usr/bin/log show --predicate 'subsystem == "com.mehulfursule.nomi"'`.
