# Cropaway

Professional video cropping tool with rectangle, circle, freehand mask, and AI object tracking. Available for macOS and Windows.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Windows](https://img.shields.io/badge/Windows-10+-0078D6)
![License](https://img.shields.io/badge/license-MIT-green)

## Download

Get the latest release from [Releases](../../releases/latest):

| Platform | File | Description |
|----------|------|-------------|
| macOS | `Cropaway-x.x.x.dmg` | Drag to Applications to install |
| Windows | `CropawaySetup-x.x.x.exe` | Installer with Start Menu shortcuts |
| Windows | `Cropaway-Windows-Portable-x.x.x.zip` | Portable build, no install needed |

**Requirements:**
- **macOS:** macOS 14 Sonoma or later, Apple Silicon or Intel
- **Windows:** Windows 10 or later (64-bit)
- FFmpeg is bundled with all downloads

## Features

- **Rectangle Crop** — Precise rectangular cropping with draggable handles
- **Circle Crop** — Circular masks with adjustable center and radius
- **Freehand Mask** — NLE-style point-based mask tool with bezier curves
- **AI Track (SAM3)** — Object tracking via fal.ai SAM3 cloud API with text or box prompts
- **Keyframe Animation** — Animate crop changes over time with easing interpolation
- **Hardware Accelerated Export** — VideoToolbox on macOS; NVENC/QSV/AMF on Windows
- **Batch Export** — Export multiple videos at once
- **Bounding Box Export** — Per-frame crop data to JSON or Python pickle
- **Mask Adjustments** — Smoothness, radius, and denoise controls for mask refinement
- **Zoom & Pan** — Zoomable video preview (25%–400%) with fit-to-window
- **Auto-Save** — Crop data persists automatically per video
- **Inspector Panel** — Numeric crop property editing
- **JKL Shuttle** — Professional shuttle playback controls

## Keyboard Shortcuts

### macOS

| Action | Shortcut |
|--------|----------|
| Rectangle Mode | `Cmd+1` |
| Circle Mode | `Cmd+2` |
| Freehand Mode | `Cmd+3` |
| AI Track Mode | `Cmd+4` |
| Export Video | `Cmd+E` |
| Export All | `Cmd+Shift+E` |
| Add Keyframe | `Cmd+K` |
| Undo / Redo | `Cmd+Z` / `Cmd+Shift+Z` |
| Reset Crop | `Cmd+Shift+R` |
| Play/Pause | `Space` |
| Step Forward/Back | `→` / `←` |
| J/K/L Shuttle | `J` / `K` / `L` |

### Windows

| Action | Shortcut |
|--------|----------|
| Open Videos | `Ctrl+O` |
| Rectangle Mode | `Ctrl+1` |
| Circle Mode | `Ctrl+2` |
| Freehand Mode | `Ctrl+3` |
| AI Track Mode | `Ctrl+4` |
| Export Video | `Ctrl+E` |
| Export All | `Ctrl+Shift+E` |
| Add Keyframe | `Ctrl+K` |
| Remove Keyframe | `Ctrl+Shift+K` |
| Previous/Next Keyframe | `Ctrl+[` / `Ctrl+]` |
| Auto-Keyframe Toggle | `Ctrl+Shift+A` |
| Undo / Redo | `Ctrl+Z` / `Ctrl+Shift+Z` |
| Reset Crop | `Ctrl+Shift+R` |
| Copy/Paste Crop | `Ctrl+C` / `Ctrl+V` |
| Play/Pause | `Space` |
| Step Forward/Back | `→` / `←` |
| Jump 1s Forward/Back | `Shift+→` / `Shift+←` |
| Jump 10s Forward/Back | `Ctrl+Shift+→` / `Ctrl+Shift+←` |
| J/K/L Shuttle | `J` / `K` / `L` |
| Nudge Crop | `Alt+Arrow Keys` |
| Zoom In/Out | `Ctrl++` / `Ctrl+-` |
| Fit to Window | `Ctrl+9` |
| Actual Size | `Ctrl+0` |
| Toggle Sidebar | `Ctrl+\` |
| Toggle Inspector | `Ctrl+Alt+I` |
| Set In/Out Point | `I` / `O` |
| Split Clip | `Ctrl+B` |
| Toggle Loop | `Ctrl+L` |
| Slow/Normal/Fast | `Ctrl+Alt+S` / `Ctrl+Alt+D` / `Ctrl+Alt+F` |

## AI Video Tracking

Both platforms support cloud-based object tracking via [fal.ai](https://fal.ai) SAM3:

1. Switch to AI Track mode (`Cmd+4` / `Ctrl+4`)
2. Enter a text prompt describing the object (e.g., "person", "car") or draw a bounding box
3. The service tracks the object across frames and generates keyframes automatically

Requires a fal.ai API key — configure in the app settings. Pricing is approximately $0.005 per 16 frames.

## Export

### Video Export
- **macOS:** H.264, HEVC, and ProRes via VideoToolbox hardware encoding
- **Windows:** H.264 and HEVC with automatic hardware detection:
  - NVIDIA NVENC (`h264_nvenc` / `hevc_nvenc`)
  - Intel Quick Sync (`h264_qsv` / `hevc_qsv`)
  - AMD VCE (`h264_amf` / `hevc_amf`)
  - Software fallback (`libx264` / `libx265`)
- Alpha channel export for circle and freehand modes (preserves transparency)

### Data Export
- **JSON** — Per-frame `[x1, y1, x2, y2]` bounding box coordinates
- **Pickle** — Python-compatible pickle format for ML pipelines

## Building from Source

### macOS

Requires Xcode 26 (for Liquid Glass APIs) and FFmpeg.

```bash
brew install ffmpeg

# Build release
xcodebuild -scheme Cropaway -configuration Release build

# Create DMG
./scripts/build-dmg.sh 1.0.0
```

### Windows

Requires .NET 8 SDK and FFmpeg.

```bash
cd CropawayWindows

# Restore and build
dotnet build CropawayWindows/CropawayWindows.csproj

# Publish self-contained
dotnet publish CropawayWindows/CropawayWindows.csproj -c Release -r win-x64 --self-contained true -o publish
```

To create an installer, install [Inno Setup 6](https://jrsoftware.org/isinfo.php) and run:

```bash
iscc /DMyAppVersion=1.0.0 installer.iss
```

## Tech Stack

### macOS
- SwiftUI with macOS 26 Liquid Glass
- AVFoundation for video playback
- FFmpeg (bundled) with VideoToolbox hardware acceleration
- Core Graphics for mask rendering

### Windows
- WPF (.NET 8) with CommunityToolkit.Mvvm
- MediaElement for video playback
- FFmpeg (bundled) with NVENC/QSV/AMF hardware acceleration
- System.Drawing for mask rendering

### Shared
- fal.ai SAM3 API for AI object tracking
- JSON-based crop data persistence

## Releasing

Releases are fully automated via GitHub Actions. To create a new release:

```bash
./scripts/release.sh 1.2.0
```

This tags the commit on `main` and pushes it. CI builds both platforms in parallel (`macos-26` and `windows-latest` runners) and publishes a unified GitHub Release with the DMG, installer, and portable ZIP.

## License

MIT License
