# PhoneAgent

PhoneAgent is an experimental mobile automation project with two operating modes:

1. **In-app iPhone agent** (SwiftUI app + XCTest runner + OpenAI Responses API)
2. **External bridge** to let Codex/OpenClaw control iOS/Android devices

The bridge supports both:
- **iOS** (XCTest-hosted actions against simulator or physical iPhone)
- **Android** (adb + UiAutomator + input/screencap actions against emulator or device)

## Demo

- [Self contained iOS app](https://www.youtube.com/shorts/4rnv6dN-2Lg)
- [OpenClaw controlling an iPhone](https://youtube.com/shorts/MMAjh1xqsdM?feature=share)
- [OpenClaw controlling an Android phone](https://www.youtube.com/shorts/gN7ZJtl0byM)
- [Codex controlling an iPhone](https://youtu.be/D44AWOQI74I)

## What This Repo Includes

- **iOS app UI**: API key entry, prompt input, microphone support, settings, always-on wake-word mode
- **iOS test-hosted RPC server**: newline-delimited JSON-RPC on port `45678`
- **Android RPC server**: localhost JSON-RPC bridge backed by `adb` commands
- **Helper scripts**:
  - iOS bridge launcher + physical-device localhost forwarding
  - Android bridge launcher (with adb auto-discovery)
  - generic RPC CLI (`rpc.py`) for both platforms

## Capabilities

### Shared RPC action surface (iOS + Android)

- `get_tree`
- `get_screen_image`
- `get_context`
- `set_api_key`
- `open_app`
- `tap`
- `tap_element`
- `enter_text`
- `scroll`
- `swipe`
- `stop`

### iOS-only RPC method

- `submit_prompt`

`submit_prompt` powers the in-app iPhone agent loop.

### In-app iPhone agent features

- OpenAI API key stored in Keychain
- Prompt submission from keyboard or microphone
- Optional always-on mode with custom wake word
- Notification completion + quick-reply follow-up loop

## Requirements

### macOS host

- Xcode (for iOS app/UITest bridge)
- Python 3
- Android SDK tools (`adb`) for Android bridge

### Devices

- iOS simulator or physical iPhone (Developer setup)
- Android emulator or physical Android device (USB debugging or wireless debugging)

## Quick Start (In-App iPhone Agent)

1. Open `/Users/rounak/Developer/PhoneAgent-cli/PhoneAgent.xcodeproj` in Xcode.
2. Run the `PhoneAgent` scheme on an iPhone/simulator.
3. Enter OpenAI API key when prompted.
4. Submit tasks via keyboard or microphone.

## Quick Start (AI Agents)

For Codex/OpenClaw usage, use the skill docs:
- [`.agents/skills/phoneagent/`](./.agents/skills/phoneagent/)

### Send RPC calls

```bash
# iOS bundle identifier example
./.agents/skills/phoneagent/scripts/rpc.py open-app com.apple.Preferences

# Android package example
./.agents/skills/phoneagent/scripts/rpc.py open-app com.android.settings

# Fetch tree
./.agents/skills/phoneagent/scripts/rpc.py get-tree

# Capture screenshot (writes PNG under /tmp/phoneagent-artifacts)
./.agents/skills/phoneagent/scripts/rpc.py get-screen-image --print-metadata
```

The CLI supports `--host` and `--port` if you need non-default endpoint settings.

## RPC Notes

- Transport: newline-delimited JSON-RPC objects
- Endpoint: `127.0.0.1:45678` by default
- `open_app` request parameter is `bundle_identifier`:
  - iOS: pass bundle identifier (e.g. `com.apple.Preferences`)
  - Android: pass package name (e.g. `com.android.settings`)
- `tap_element` / `enter_text` use coordinate rectangles in format `{{x, y}, {w, h}}`

## Common App Identifiers

### iOS

- Settings: `com.apple.Preferences`
- Camera: `com.apple.camera`
- Photos: `com.apple.mobileslideshow`
- Messages: `com.apple.MobileSMS`
- Home Screen: `com.apple.springboard`

## Wireless Android (No USB)

```bash
# Pair (from Wireless debugging screen)
adb pair <PHONE_IP:PAIRING_PORT>

# Connect (from Wireless debugging screen)
adb connect <PHONE_IP:ADB_PORT>

# Verify
adb devices -l
```

Then start Android bridge with that network serial:

```bash
./.agents/skills/phoneagent/scripts/start_android_rpc_bridge_local.sh --serial <PHONE_IP:ADB_PORT>
```

## Security Model

- RPC bridge is localhost-oriented (`127.0.0.1`)
- iOS physical-device workflow uses localhost forwarding
- Android bridge executes only through selected `adb` serial
- In-app API key is stored in iOS Keychain

## Repository Pointers

- iOS app entry: `PhoneAgent/PhoneAgentApp.swift`
- iOS app UI/state: `PhoneAgent/ContentView.swift`, `PhoneAgent/PromptView.swift`, `PhoneAgent/SettingsView.swift`
- iOS bridge server: `PhoneAgentUITests/SimulatorRPCServer.swift`, `PhoneAgentUITests/PhoneAgent.swift`
- RPC CLI: `.agents/skills/phoneagent/scripts/rpc.py`
- iOS bridge launcher: `.agents/skills/phoneagent/scripts/start_rpc_bridge_local.sh`
- Android bridge launcher: `.agents/skills/phoneagent/scripts/start_android_rpc_bridge_local.sh`
- Android bridge server: `.agents/skills/phoneagent/scripts/android_rpc_bridge.py`

## Known Limitations

- Android bridge does **not** yet implement `submit_prompt` agent loop
- UI tree snapshots can be noisy/stale during animations
- Keyboard/text reliability can vary by app and platform
- Long-running tasks may require explicit polling/retries

## Disclaimer

- Experimental software
- Personal project
- App contents may be sent to OpenAI API when using agent flow
- Model/tool actions can be incorrect; verify important operations


## FAQ

### What is PhoneAgent?

PhoneAgent is an **experimental mobile automation project** that provides AI agents with control over iOS and Android devices. It offers two operating modes: an in-app iPhone agent and an external bridge for Codex/OpenClaw control.

### What devices are supported?

| Platform | Device Type | Requirements |
|----------|-------------|--------------|
| iOS | Simulator, Physical iPhone | Xcode, Developer setup |
| Android | Emulator, Physical device | USB/wireless debugging, adb |

### What can AI agents do with PhoneAgent?

| Action | Description |
|--------|-------------|
| `get_tree` | Get UI element hierarchy |
| `get_screen_image` | Capture screen screenshot |
| `get_context` | Get current app context |
| `open_app` | Launch an application |
| `tap` | Tap at coordinates |
| `tap_element` | Tap UI element by selector |
| `enter_text` | Input text into field |
| `scroll` | Scroll in direction |
| `swipe` | Swipe gesture |
| `stop` | Stop automation |

### How does the in-app iPhone agent work?

- SwiftUI app with OpenAI Responses API
- XCTest runner for UI automation
- Keychain-stored API key
- Prompt via keyboard or microphone
- Optional always-on mode with wake word
- Notification completion + quick-reply loop

### How do I use PhoneAgent with Codex/OpenClaw?

PhoneAgent provides skill docs for AI agent integration:
- iOS bridge launcher with localhost forwarding
- Android bridge launcher with adb auto-discovery
- Generic RPC CLI (`rpc.py`) for both platforms

### What are the system requirements?

**macOS host:**
- Xcode (for iOS app/UITest bridge)
- Python 3
- Android SDK tools (`adb`) for Android bridge

**Devices:**
- iOS: Simulator or physical iPhone with Developer setup
- Android: Emulator or device with USB/wireless debugging

### Is PhoneAgent free?

Yes! PhoneAgent is **free and open source**.

### Where can I see demos?

| Demo | Link |
|------|------|
| Self-contained iOS app | [YouTube Shorts](https://www.youtube.com/shorts/4rnv6dN-2Lg) |
| OpenClaw controlling iPhone | [YouTube Shorts](https://youtube.com/shorts/MMAjh1xqsdM) |
| OpenClaw controlling Android | [YouTube Shorts](https://www.youtube.com/shorts/gN7ZJtl0byM) |
| Codex controlling iPhone | [YouTube](https://youtu.be/D44AWOQI74I) |

### How do I contribute?

1. Fork the repo
2. Create a feature branch
3. Submit a pull request

### Where can I get help?

| Resource | Link |
|----------|------|
| GitHub Issues | [PhoneAgent Issues](https://github.com/rounak/PhoneAgent/issues) |
| Skill Docs | See repository for Codex/OpenClaw skill documentation |