# MicBar

A lightweight macOS menu bar app that shows microphone usage status.

When any app (Zoom, FaceTime, etc.) is using your microphone, MicBar displays a red **REC** indicator in the menu bar. When the microphone is inactive, it shows a gray **MIC** label.

## Features

- Real-time microphone usage detection via CoreAudio
- Menu bar indicator with customizable display styles (Text / Icon+Text / Icon)
- Shows active device name and estimated app using the mic
- Duration tracking for active microphone sessions
- Launch at Login support
- No Xcode required — builds with swiftc + Make

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode Command Line Tools (`xcode-select --install`)

## Build & Run

```bash
git clone https://github.com/kishisan/MicBar.git
cd MicBar
make run
```

### Available Make targets

| Target    | Description                          |
|-----------|--------------------------------------|
| `build`   | Build optimized binary with swiftc   |
| `app`     | Create .app bundle                   |
| `sign`    | Ad-hoc codesign with entitlements    |
| `run`     | Build, sign, and launch              |
| `install` | Copy .app to /Applications           |
| `clean`   | Clean build artifacts                |

## How It Works

MicBar uses the CoreAudio HAL API to monitor input device status:

1. Enumerates audio devices with input streams
2. Listens for `kAudioDevicePropertyDeviceIsRunningSomewhere` changes
3. Falls back to 3-second polling for Bluetooth devices
4. Matches running apps against known microphone-using bundle IDs

## Display Styles

- **Text Only**: `● REC` (active) / `MIC` (inactive)
- **Icon & Text**: Mic icon + text
- **Icon Only**: SF Symbols mic icon

## License

MIT
