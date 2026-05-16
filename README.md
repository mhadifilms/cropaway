# Cropaway

Professional video cropping tool with rectangle, circle, freehand mask, and AI object tracking. Available for macOS and Windows.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Windows](https://img.shields.io/badge/Windows-10+-0078D6)
![License](https://img.shields.io/badge/license-MIT-green)


## Recent changes

![Keyframe Timeline](assets/cropaway_new.gif)
![Keyframe Timeline](assets/cropaway_timeline.png)
- ### Keyframe Timeline Enhancements
    - **Color-coded keyframe spans** - Timeline now shows colored spans indicating each keyframe's active duration until the next keyframe
    - **"None" keyframe type** - Add keyframes that disable the bounding box for a duration (shown in white on the timeline)
    - **Update keyframe button** - New button to update the selected keyframe with the current bounding box; disabled when no changes pending
    - **Keyframe bar open by default** - Timeline is now visible by default when loading a video

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

The published GitHub Releases are unsigned/ad-hoc-signed. If you want to verify the source, ship a personal build, or self-sign with your own Developer ID, follow the instructions below.

### macOS

**Prerequisites**
- macOS 14 Sonoma or later
- Xcode 26 or newer (required for the Liquid Glass APIs used in the UI). Install from the Mac App Store, then run `sudo xcode-select -s /Applications/Xcode.app` and accept the license: `sudo xcodebuild -license accept`.
- [Homebrew](https://brew.sh)
- FFmpeg (`brew install ffmpeg`) — used at runtime via the system PATH or the bundled binary.

**1. Clone and open in Xcode**

```bash
git clone https://github.com/mhadifilms/cropaway.git
cd cropaway
open cropaway.xcodeproj
```

In Xcode, pick the **Cropaway** scheme and **My Mac** as the destination, then press ⌘R to run a Debug build. The first build downloads SwiftPM dependencies and may take a couple of minutes.

**2. Command-line Debug build**

```bash
xcodebuild -scheme Cropaway -configuration Debug \
    -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Cropaway.app
```

**3. Release DMG (ad-hoc / unsigned)**

```bash
./scripts/build-dmg.sh 1.0.0
```

This produces `build/Cropaway-1.0.0.dmg` ad-hoc-signed. The DMG opens normally, but Gatekeeper will block first launch because the app is not signed with a Developer ID or notarized. To run it:

- **Right-click** the app in `/Applications` → **Open** → **Open** in the confirmation dialog (only required the first time), or
- Run once from Terminal to strip the quarantine flag: `xattr -dr com.apple.quarantine /Applications/Cropaway.app`

**4. Release DMG (signed with your own Developer ID, optional)**

If you have a paid Apple Developer account and a **Developer ID Application** certificate installed in your login keychain, you can produce a fully signed (and optionally notarized) DMG by exporting the required environment variables before invoking the build script:

```bash
# Signing only — produces a Developer-ID-signed DMG (still triggers Gatekeeper unless notarized)
export DEVELOPMENT_TEAM="ABCDE12345"               # Your 10-char Team ID
export CODE_SIGN_IDENTITY="Developer ID Application: Your Name (ABCDE12345)"

# Optional: also notarize and staple
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="ABCDE12345"
export APPLE_APP_SPECIFIC_PASSWORD="abcd-efgh-ijkl-mnop"   # App-Specific Password, not your Apple ID password

./scripts/build-dmg.sh 1.0.0
```

You can find your identity string with:

```bash
security find-identity -p codesigning -v | grep "Developer ID Application"
```

App-Specific Passwords are generated at [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords. Notarization uploads the DMG to Apple and waits for the result; it typically takes 1–5 minutes.

### Windows

**Prerequisites**
- Windows 10 or later (64-bit)
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Inno Setup 6](https://jrsoftware.org/isinfo.php) (only if you want to build the installer `.exe`)
- FFmpeg — the build expects `ffmpeg.exe` and `ffprobe.exe` in `CropawayWindows/ffmpeg-bin/`. Download a static build from [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds/releases/latest) and copy the two binaries into that folder.

**1. Clone and build**

```powershell
git clone https://github.com/mhadifilms/cropaway.git
cd cropaway\CropawayWindows

dotnet restore CropawayWindows\CropawayWindows.csproj
dotnet build  CropawayWindows\CropawayWindows.csproj -c Release
```

**2. Self-contained publish (portable folder)**

```powershell
dotnet publish CropawayWindows\CropawayWindows.csproj `
    -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=false `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -o publish

# Bundle FFmpeg with the build
New-Item -ItemType Directory -Path publish\ffmpeg -Force | Out-Null
Copy-Item ffmpeg-bin\ffmpeg.exe  publish\ffmpeg\ffmpeg.exe
Copy-Item ffmpeg-bin\ffprobe.exe publish\ffmpeg\ffprobe.exe
```

Run `publish\CropawayWindows.exe` directly, or zip the `publish` folder for a portable distribution.

**3. Installer (.exe)**

With Inno Setup installed:

```powershell
iscc /DMyAppVersion=1.0.0 installer.iss
# Output appears in CropawayWindows\output\CropawaySetup-1.0.0.exe
```

The installer is unsigned by default; SmartScreen may show a "Windows protected your PC" warning on first run. Click **More info** → **Run anyway** to proceed, or sign the installer yourself with `signtool` if you have an EV/OV code-signing certificate.

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
