# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cropaway is a professional video cropping tool available on **macOS** and **Windows**. Both apps support four crop modes (rectangle, circle, freehand mask, AI tracking), keyframe animation, and hardware-accelerated export.

## Build Commands

### macOS

```bash
# Build release from command line (requires Xcode 26 for Liquid Glass APIs)
xcodebuild -scheme Cropaway -configuration Release build

# Create DMG for distribution
./scripts/build-dmg.sh 1.0.0

# Open in Xcode
open cropaway.xcodeproj
```

**Development requirement:** FFmpeg must be installed via Homebrew (`brew install ffmpeg`) for video export to work during development. The production app bundles FFmpeg.

### Windows

```bash
cd CropawayWindows

# Build
dotnet build CropawayWindows/CropawayWindows.csproj

# Publish self-contained
dotnet publish CropawayWindows/CropawayWindows.csproj -c Release -r win-x64 --self-contained true -o publish

# Create installer (requires Inno Setup 6)
iscc /DMyAppVersion=1.0.0 installer.iss
```

**Development requirement:** .NET 8 SDK and FFmpeg must be available on PATH.

### Releasing

Releases are automated via GitHub Actions. Run from `main` branch:

```bash
./scripts/release.sh 1.2.0
```

This pushes a `v1.2.0` tag. CI builds both platforms (`macos-26` and `windows-latest` runners) and publishes a unified GitHub Release with DMG, installer, and portable ZIP.

Key CI files:
- `.github/workflows/release.yml` — Unified release (triggered by `v*` tags)
- `.github/workflows/build-windows.yml` — Windows CI on push/PR (no release)
- `scripts/release.sh` — Tag-and-push helper
- `scripts/build-dmg.sh` — macOS DMG builder
- `CropawayWindows/installer.iss` — Inno Setup installer script

## macOS App Architecture

Native SwiftUI app in `cropaway.xcodeproj`. Requires macOS 14+ and Xcode 26 (uses macOS 26 Liquid Glass `.glassEffect()` APIs — do NOT add `#if compiler` guards to these).

### Data Flow

```
ProjectViewModel (video list, selection)
       ↓
    VideoItem (source URL, metadata, CropConfiguration)
       ↓
    CropConfiguration (crop state, keyframes, export settings)
       ↓
    KeyframeInterpolator (time-based crop interpolation)
       ↓
    FFmpegExportService (video processing)
```

### Key Architectural Patterns

**Notification-based commands:** Menu commands and keyboard shortcuts use `NotificationCenter` to communicate with views. All notification names are defined as extensions on `Notification.Name` in `cropawayApp.swift`. Views subscribe using `.onReceive()` in ViewModifier handlers (see `MainContentView.swift`).

**Normalized coordinates:** All crop coordinates (rectangle, circle center, freehand points) are stored as normalized 0-1 values relative to video dimensions. Conversion to pixel coordinates happens at export time using `denormalized(to:)` extensions in `Utilities/CGExtensions.swift`.

**Per-video crop persistence:** Crop data auto-saves to Application Support (via `CropDataStorageService`). Use File → Export Crop JSON to copy data to a user-chosen folder. Settings restore when reopening videos. Legacy `.cropaway` sidecar data is migrated on first load.

### ViewModels

- `ProjectViewModel` — Video list management, selection state, drag-drop handling
- `VideoPlayerViewModel` — AVPlayer control, JKL shuttle, frame stepping
- `CropEditorViewModel` — Current crop mode/state, bound to selected video's `CropConfiguration`
- `KeyframeViewModel` — Keyframe timeline, interpolation triggering
- `ExportViewModel` — Export queue, progress tracking
- `CropUndoManager` — Undo/redo for crop operations

### Services

- `FFmpegExportService` — FFmpeg filter chains, VideoToolbox hardware encoding (h264/hevc/prores)
- `FalAIService` — Cloud-based AI video tracking via fal.ai SAM3 API
- `KeyframeInterpolator` — Singleton, interpolates between keyframes with easing
- `CropMaskRenderer` — Generates mask images for circle/freehand crops
- `VideoMetadataExtractor` — Reads video properties via AVFoundation
- `CropDataStorageService` — JSON in Application Support

### Export Pipeline

FFmpeg export uses VideoToolbox hardware encoders (`h264_videotoolbox`, `hevc_videotoolbox`, `prores_videotoolbox`). Codec selection matches source format. Circle and freehand modes generate PNG masks that FFmpeg composites using `alphamerge` or `blend` filters.

## Windows App Architecture

WPF (.NET 8) app in `CropawayWindows/` folder. Uses CommunityToolkit.Mvvm 8.2.2 for MVVM infrastructure.

### Project Structure

- **Solution:** `CropawayWindows/CropawayWindows.sln`
- **Project:** `CropawayWindows/CropawayWindows/CropawayWindows.csproj`
- **Namespace:** `CropawayWindows`
- **Pattern:** MVVM with `MainViewModel` coordinating sub-ViewModels

### Key Convention: CommunityToolkit.Mvvm Naming

`[ObservableProperty]` on `_aiMaskData` generates property `AiMaskData` (NOT `AIMaskData`). Manually defined types (KeyframeData, InterpolatedCropState) use `AIMaskData`/`AIBoundingBox`. This inconsistency is intentional.

### ViewModels

- `MainViewModel` — Top-level coordinator for all sub-VMs and commands
- `ProjectViewModel` — Video list and selection management
- `VideoPlayerViewModel` — MediaElement playback, JKL shuttle, frame stepping
- `CropEditorViewModel` — Current crop state bound to selected video
- `KeyframeViewModel` — Keyframe timeline, auto-keyframe creation, interpolation
- `ExportViewModel` — Export queue, progress tracking
- `TimelineViewModel` — Multi-track timeline editing
- `InspectorViewModel` — Property inspection and numeric input
- `CropUndoManager` — Undo/redo state management

### Key Services

- `FFmpegExportService` — NVENC/QSV/AMF hardware encoding with software fallback
- `FalAIService` — fal.ai SAM3 cloud AI tracking (~890 lines)
- `CropDataStorageService` — JSON persistence in `%LocalAppData%\Cropaway\crop-data`
- `BoundingBoxExportService` — JSON and pickle export of per-frame crop data

### Key Controls

- `CropOverlayControl` — Full interactive crop overlay supporting all 4 modes
- `VideoSidebarView` — Video list with context menus and drag-drop
- `MainWindow` — All keyboard shortcuts defined as InputBindings

### Export Pipeline

FFmpeg with automatic hardware encoder detection. Tries NVENC → QSV → AMF → software fallback. Supports H.264 and HEVC. Circle and freehand modes generate mask images for FFmpeg alpha compositing.

### Data Persistence

Crop configurations auto-save to JSON in `%LocalAppData%\Cropaway\crop-data` with 500ms debounce. Per-video state restores when reopening.

## AI Video Tracking (fal.ai) — Both Platforms

The AI mode (`Cmd+4` / `Ctrl+4`) uses fal.ai's cloud-based SAM3 video API:
- Text prompt: Describe the object to track (e.g., "person", "car")
- Box prompt: Draw a bounding box around the object in the first frame
- Results are automatically converted to keyframes for the tracked bounding box
- API key: macOS stores in UserDefaults (`FalAIAPIKey`), Windows stores in app settings

## Code Conventions

- All crop coordinates are normalized 0-1 (not pixels) on both platforms
- Keyframe interpolation types: `linear`, `easeIn`, `easeOut`, `easeInOut`, `hold`
- Video dimensions must be even numbers for FFmpeg compatibility
- macOS uses Liquid Glass APIs (macOS 26) — do NOT wrap in `#if compiler` guards
- Windows uses `Ctrl` where macOS uses `Cmd` for keyboard shortcuts
