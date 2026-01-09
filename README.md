<p align="center">
  <img src=".github/images/app-icon.png" alt="ScreenCapture" width="128" height="128">
</p>

<h1 align="center">ScreenCapture</h1>

<p align="center">
  A fast, lightweight macOS menu bar app for capturing and annotating screenshots.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-13.0%2B-brightgreen.svg" alt="macOS"></a>
  <a href="https://swift.org/"><img src="https://img.shields.io/badge/Swift-6.2-orange.svg" alt="Swift"></a>
</p>

## Features

- **Multiple Capture Modes** - Full screen, region selection, window, and window with shadow
- **Annotation Tools** - Rectangles, arrows, freehand drawing, and text with floating style panel
- **Multi-Monitor Support** - Works seamlessly across all connected displays
- **Auto-Save** - Screenshots automatically saved when closing preview (configurable)
- **Recent Captures** - Quick access to recent screenshots from menu bar and editor sidebar
- **Quick Export** - Save to disk or copy to clipboard instantly
- **Lightweight** - Runs quietly in your menu bar with minimal resources

## Installation

### Requirements

- macOS 13.0 (Ventura) or later
- Screen Recording permission

### Download

Download the latest release from the [Releases](../../releases) page.

### Build from Source

```bash
# Clone the repository
git clone https://github.com/diegoavarela/screencapture.git
cd screencapture

# Open in Xcode
open ScreenCapture.xcodeproj

# Build and run (Cmd+R)
```

## Usage

### Global Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+Ctrl+3` | Capture full screen |
| `Cmd+Ctrl+4` | Capture selection |
| `Cmd+Ctrl+6` | Capture window |
| `Cmd+Ctrl+7` | Capture window with shadow |

> **Note**: Shortcuts can be customized in Settings.

### In Preview Window

| Shortcut | Action |
|----------|--------|
| `Enter` / `Cmd+S` | Save screenshot |
| `Cmd+C` | Copy to clipboard |
| `Escape` | Dismiss (auto-saves if enabled) |
| `R` / `1` | Rectangle tool |
| `D` / `2` | Freehand tool |
| `A` / `3` | Arrow tool |
| `T` / `4` | Text tool |
| `C` | Crop mode |
| `G` | Toggle recent captures gallery |
| `Cmd+Z` | Undo |
| `Cmd+Shift+Z` | Redo |
| `Delete` | Delete selected annotation |

## Documentation

Detailed documentation is available in the [docs](./docs) folder:

- [Architecture](./docs/architecture.md) - System design and patterns
- [Components](./docs/components.md) - Feature documentation
- [API Reference](./docs/api-reference.md) - Public APIs
- [Developer Guide](./docs/developer-guide.md) - Contributing guide
- [User Guide](./docs/user-guide.md) - End-user documentation

## Tech Stack

- **Swift 6.2** with strict concurrency
- **SwiftUI** + **AppKit** for native macOS UI
- **ScreenCaptureKit** for system-level capture
- **CoreGraphics** for image processing

## Contributing

Contributions are welcome! Please read our contributing guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_FORK/ScreenCapture.git

# Open in Xcode
open ScreenCapture.xcodeproj

# Grant Screen Recording permission when prompted
```

See the [Developer Guide](./docs/developer-guide.md) for detailed setup instructions.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

```
MIT License - Copyright (c) 2026 Serdar Albayrak
```

## Acknowledgments

- Built with [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
- Icons from [SF Symbols](https://developer.apple.com/sf-symbols/)

---

Made with Swift for macOS
