# Nomi

A macOS assistant that lives in the MacBook notch and runs its language model locally on Apple Silicon. No API keys, no accounts, no cloud inference.

Status: Phase 1 (shell) complete. The notch surface, global shortcut, Settings and onboarding exist. Model download, chat, tools, screen understanding, knowledge and MCP arrive in later phases. See [PROGRESS.md](PROGRESS.md) for the current state.

## Requirements

- macOS 15 or later on Apple Silicon (developed on macOS 26.6, an M5 Pro with 24 GB)
- Xcode 26.6 (macOS 26.5 SDK, Swift 6.3)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to regenerate the project after adding files

## Build

```sh
xcodegen generate
xcodebuild -project Nomi.xcodeproj -scheme Nomi -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData build
xcodebuild -project Nomi.xcodeproj -scheme Nomi -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData test
open build/DerivedData/Build/Products/Debug/Nomi.app
```

`project.yml` is the source of truth for the Xcode project. Edit it, then run `xcodegen generate`. The generated `Nomi.xcodeproj` is committed so the project also opens without XcodeGen installed.

## Signing and TCC

macOS ties Accessibility and Screen Recording permission to the app's code signature. A build that is ad-hoc signed gets a fresh identity every time, which revokes the permission on every rebuild.

The project therefore signs every build with the same Apple Development certificate (`CODE_SIGN_STYLE = Manual`, `CODE_SIGN_IDENTITY = "Apple Development"`, team `MACDPWQG37` in `project.yml`) and keeps the bundle identifier `com.mehulfursule.nomi` stable. On another machine, change `DEVELOPMENT_TEAM` to your own team, or create a self-signed code-signing certificate once in Keychain Access and set `CODE_SIGN_IDENTITY` to its name.

The app is not sandboxed, because the Accessibility API does not work inside the App Sandbox. Hardened Runtime is on. It requests no root privileges and installs no helper.

## Architecture

- `Nomi/App`: AppKit lifecycle (`main.swift`, `AppDelegate`), main menu, status item, `nomi://` URL commands
- `Nomi/UI/Notch`: display geometry (`DisplayLayout`, `NotchGeometry`), the `NSPanel`, per-display controllers and the SwiftUI surface
- `Nomi/UI/Settings`, `Nomi/UI/Onboarding`: SwiftUI content hosted in AppKit windows
- `Nomi/Services/Shortcuts`: Carbon hot key registration, shortcut model, conflict lookup against macOS system shortcuts
- `Nomi/Persistence`: preferences and the Application Support location
- `NomiTests`: Swift Testing suites, hosted by the app target

The notch window keeps one fixed frame, the size of the largest open surface. Transparent pixels pass clicks through to whatever is beneath, so menu bar items stay usable while the assistant is idle.

## Using it

- `⌥Space` opens the assistant (change it in Settings > General). Pressing it again focuses the question field. `Escape` closes.
- Hover over the notch for a small growth; click it to open.
- The menu bar icon opens Settings, the welcome flow, or quits the app.
- `open nomi://open`, `nomi://close`, `nomi://toggle`, `nomi://settings`, `nomi://welcome` drive the same actions from scripts.

## Screenshots

| Idle | Hover | Open |
|---|---|---|
| ![Idle](docs/screenshots/notch-idle.png) | ![Hover](docs/screenshots/notch-hover.png) | ![Open](docs/screenshots/notch-open.png) |

![Onboarding](docs/screenshots/onboarding.png)
![Settings](docs/screenshots/settings-general.png)

## Known limitations

- No model, tools, screen reading or knowledge yet. Submitting a question reports that the model is not installed.
- The microphone button is present but voice input is not implemented.
- System shortcut conflicts are detected from `com.apple.symbolichotkeys`; conflicts with third-party apps are not.
