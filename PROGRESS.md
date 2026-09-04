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
- AppKit owns the lifecycle (`main.swift`, `NSApplicationMain`). The SwiftUI `Settings` scene never responded to `showSettingsWindow:` in this accessory app, so Settings and onboarding are plain `NSWindow`s hosting SwiftUI. A main menu built in code keeps ⌘Q and the Edit key equivalents working.
- Model choice: `mlx-community/Qwen3-14B-4bit` stays the default. The MLX registry has newer Qwen3.5/3.6/3.8 releases but none in the 14B class (9B below, 27B above, and 27B at 4-bit does not fit the 24 GB budget with a KV cache). Lightweight option: `mlx-community/Qwen3-4B-Instruct-2507-4bit` (2.28 GB, loads, tool calling works).
- Model files live in `~/Library/Application Support/Nomi/Models/<org>/<name>/` via the app's own `ModelDownloader` (Hugging Face tree API, ranged resume, SHA-256 verify). mlx-swift-lm's tokenizer loader comes from `swift-transformers`; no `HubClient` is used.
- Thinking is disabled (`enable_thinking: false`) and a `HiddenSpanFilter` drops any `<think>` or `<tool_call>` text that reaches the output.
- Building needs the Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`) and, from the command line, `-skipPackagePluginValidation -skipMacroValidation` for mlx-swift's build plugin and the MLXHuggingFace macros.
- The `nomi://` URL scheme (`open`, `close`, `toggle`, `settings`, `welcome`) exists so scripts and the verification steps below can drive the app. `probe` and `closewindows` exist only in Debug builds.

## Phase 1: Shell

| # | Item | Status | Verified by |
|---|------|--------|-------------|
| 1 | Xcode project, native .app, signing, .gitignore | done | `xcodebuild build` and `xcodebuild test` succeed; `codesign -dv` shows team MACDPWQG37, hardened runtime, no sandbox |
| 2 | Notch panel: idle / hover / open, geometry on notched and external displays | done | 11 geometry tests pass; pixel measurement of screenshots: idle 663-848 x 0-32 pt equals housing, hover 659-852 x 0-36, open 545-965 wide; hit-test probe shows transparent pixels pass clicks through |
| 3 | Global shortcut (Option+Space, configurable) | done | Synthetic ⌥Space opened the surface, typing and ⌘V paste landed in the field, Escape closed it; recorder changed the shortcut to ⌃⌥N, which then opened the surface, then back to ⌥Space; 11 shortcut and conflict tests pass |
| 4 | Settings window skeleton, onboarding skeleton | done | Settings window with 9 sections opens from the status item and `nomi://settings`; General has launch at login, menu bar icon, shortcut recorder, sounds, spoken responses; onboarding shows 5 pages on first launch and via `nomi://welcome` |
| 5 | Screenshot every state and review | done | `docs/screenshots/` holds idle, hover, open (context and surface only), onboarding, settings; reviewed against the visual spec (colours, 24 pt continuous bottom corners, 16/8 pt spacing, 13/11/10 pt type, accent only on the focused field) |

## Phase 2: Local intelligence

| # | Item | Status | Verified by |
|---|------|--------|-------------|
| 6 | ModelManager: download, progress, resume, verify, remove | done | Qwen3 4B downloaded through the app with live progress; the 14B download was interrupted by a relaunch and resumed from its `.partial` file; `verify` recomputed SHA-256 of the 4B files ("All files match their checksums"); 9 model manager tests cover progress, cancel, failure, resume, remove, shared load and load failure |
| 7 | Streaming chat through MLX with cancellation | done | Qwen3 14B (default): loads in 2.0 s (weights are memory-mapped, the first answer pays for paging them in), 24.0 tokens/s on a 78-token answer, 35% system memory free while resident. Qwen3 4B: loads in 1.5-1.7 s, 66.8 tokens/s. A 300-word story was cut off by Escape mid-sentence and the partial answer stayed on screen; the conversation window shows the transcript |
| 8 | Structured tool calling via MLXLMCommon | done | `get_current_time` call parsed by MLXLMCommon, executed, result fed back, final answer shown with the activity timeline; 8 agent loop tests cover plain answers, tool results, unknown tools, malformed arguments, step limit, denied confirmation, hidden reasoning and cancellation |
| 9 | System, file, clipboard, weather tools | done | Verified live with the 14B model: Melbourne weekend forecast (Saturday and Sunday lines from Open-Meteo); with the 4B model: weather for Sydney, frontmost app (Google Chrome), Spotlight PDF search, open_app launched Calculator, write_clipboard set the clipboard; 8 weather parsing tests, 8 argument validation tests, 3 path policy tests |
| 10 | Confirmation policy and risk levels | done | Medium-risk `write_clipboard` showed "Replace the clipboard with \"banana\"?" with Cancel and Allow; Return allowed it (clipboard changed), Escape on a second run denied it (clipboard unchanged); Tools settings list risk per tool and the medium-risk toggle |

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

Nothing yet. Both models are downloaded on this machine (8.32 GB and 2.28 GB under Application Support).

## Log

- 2026-09-04: Inspected machine, toolchain, certificates, package registries. Wrote this file.
- 2026-09-04: First panel attempt resized the window per state and crashed inside NSHostingView layout (setFrame during a display cycle). Replaced with a fixed window frame.
- 2026-09-04: `isFloatingPanel = true` resets `level`; the level must be set afterwards or the surface sits under the menu bar.
- 2026-09-04: zsh has a `log` builtin. Use `/usr/bin/log show --predicate 'subsystem == "com.mehulfursule.nomi"'`.
- 2026-09-04: Verification posts synthetic mouse and key events with CGEvent (no permission needed). Never post ⌘ key equivalents that way: if Nomi is not the active app they land in whatever is. Use `nomi://closewindows` to close windows.
- 2026-09-05: Phase 2 tools verified live. The 4B model sometimes answers "I can't provide the weather" instead of calling the tool; the instructions now name the tools explicitly. Expect the 14B model to be more reliable.
- 2026-09-05: `nomi://ask` from Launch Services activates Nomi, so the frontmost-app tool tracks the last app activated other than Nomi.
- 2026-09-04: Phase 1 complete. Build, 23 tests, launch, notch open/close, shortcut, Settings and onboarding all verified on this machine.
