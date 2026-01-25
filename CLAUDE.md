# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build release from command line
xcodebuild -scheme Cropaway -configuration Release build

# Create DMG for distribution
./scripts/build-dmg.sh 1.0.0

# Open in Xcode
open cropaway.xcodeproj
```

**Development requirement:** FFmpeg must be installed via Homebrew (`brew install ffmpeg`) for video export to work during development. The production app bundles FFmpeg.

## Architecture Overview

Cropaway is a native macOS SwiftUI app for video cropping with four crop modes: rectangle, circle, freehand mask, and AI tracking. It supports keyframe animation for animated crops over time.

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

- `ProjectViewModel` - Video list management, selection state, drag-drop handling
- `VideoPlayerViewModel` - AVPlayer control, JKL shuttle, frame stepping
- `CropEditorViewModel` - Current crop mode/state, bound to selected video's `CropConfiguration`
- `KeyframeViewModel` - Keyframe timeline, interpolation triggering
- `ExportViewModel` - Export queue, progress tracking
- `CropUndoManager` - Undo/redo for crop operations

### Services

- `FFmpegExportService` - Builds FFmpeg filter chains, handles hardware encoding (VideoToolbox)
- `FalAIService` - Cloud-based AI video tracking via fal.ai SAM3 API
- `KeyframeInterpolator` - Singleton that interpolates between keyframes with easing
- `CropMaskRenderer` - Generates mask images for circle/freehand crops
- `VideoMetadataExtractor` - Reads video properties via AVFoundation
- `CropDataStorageService` - JSON in Application Support; Export Crop JSON copies to user-chosen location

### AI Video Tracking (fal.ai)

The AI mode (Cmd+4) uses fal.ai's cloud-based SAM3 video API for object tracking:
- Text prompt: Describe the object to track (e.g., "person", "car")
- Box prompt: Draw a bounding box around the object in the first frame
- Results are automatically converted to keyframes for the tracked bounding box
- API key stored in UserDefaults (`FalAIAPIKey`)

### Export Pipeline

FFmpeg export uses VideoToolbox hardware encoders (`h264_videotoolbox`, `hevc_videotoolbox`, `prores_videotoolbox`). Codec selection matches source format. Circle and freehand modes generate PNG masks that FFmpeg composites using `alphamerge` or `blend` filters.

## Code Conventions

- All crop coordinates are normalized 0-1 (not pixels)
- Keyframe interpolation types: `linear`, `easeIn`, `easeOut`, `easeInOut`, `hold`
- Video dimensions must be even numbers for FFmpeg compatibility
