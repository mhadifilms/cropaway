# cropaway

A professional video cropping app for macOS with support for rectangle, circle, and custom mask crops.

## Features

- 🎬 **Multiple Crop Modes**: Rectangle, Circle, and Custom Freehand masks
- 🎯 **Keyframe Animation**: Animate crops over time with interpolation
- ⚡ **Hardware Acceleration**: Uses VideoToolbox for fast encoding
- 🎨 **Alpha Channel Support**: Export with transparency using ProRes 4444
- 📊 **Real-time Preview**: See your crop before exporting
- 🎮 **Professional Controls**: JKL shuttle, frame stepping, zoom
- 📝 **Metadata Export**: JSON sidecar files with crop data

## Requirements

- macOS 13.0 or later
- FFmpeg (bundled with app, or install via Homebrew for development)

## Development Setup

1. Clone the repository:
```bash
git clone https://github.com/yourusername/cropaway.git
cd cropaway
```

2. Install FFmpeg (for development):
```bash
brew install ffmpeg
```

3. Open in Xcode:
```bash
open cropaway.xcodeproj
```

4. Build and run (⌘R)

## Building for Distribution

To bundle FFmpeg with the app:

```bash
./download_ffmpeg.sh
```

Then in Xcode:
1. Target → Build Phases
2. Add "Copy Files" phase with Destination: Resources
3. Add `Resources/ffmpeg` to the phase
4. Enable "Code Sign On Copy"

## Usage

### Import Videos
- Drag and drop video files into the app
- Or use File → Add Videos (⌘N)

### Crop Video
1. Select crop mode (Rectangle/Circle/Custom Mask)
2. Adjust the crop region
3. Add keyframes (⌘K) to animate crops over time
4. Export (⌘E)

### Keyboard Shortcuts

**Playback**
- Space: Play/Pause
- J/K/L: Shuttle reverse/stop/forward
- ←/→: Step backward/forward
- Shift+←/→: Jump 1 second
- ⌘+Shift+←/→: Jump 10 seconds

**Crop**
- ⌘1/2/3: Rectangle/Circle/Custom Mask mode
- ⌘K: Add keyframe
- ⌘+Shift+K: Remove keyframe
- Option+Arrows: Nudge crop position
- ⌘+Shift+R: Reset crop

**View**
- ⌘+/⌘-: Zoom in/out
- ⌘0: Actual size
- ⌘9: Fit to window

## Technologies

- **Swift** and **SwiftUI**
- **AVFoundation** for video playback and metadata
- **FFmpeg** for video export with advanced filtering
- **VideoToolbox** for hardware-accelerated encoding
- **AppKit** for native macOS UI

## Project Structure

```
cropaway/
├── Models/
│   ├── VideoItem.swift
│   ├── CropConfiguration.swift
│   ├── ExportConfiguration.swift
│   ├── Keyframe.swift
│   └── VideoMetadata.swift
├── ViewModels/
│   ├── ProjectViewModel.swift
│   ├── ExportViewModel.swift
│   └── VideoPlayerViewModel.swift
├── Views/
│   ├── MainContentView.swift
│   ├── VideoSidebarView.swift
│   ├── VideoPlayerView.swift
│   └── CropControlsView.swift
├── Services/
│   ├── FFmpegExportService.swift
│   ├── VideoMetadataExtractor.swift
│   └── CropMaskRenderer.swift
└── Extensions/
    ├── CGExtensions.swift
    └── AVExtensions.swift
```

## License

[Your License Here]

## Credits

- FFmpeg (LGPL 2.1+): https://ffmpeg.org
- Built with Swift and SwiftUI
