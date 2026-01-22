# Contributing to cropaway

Thank you for your interest in contributing to cropaway! This document provides guidelines and instructions for contributing.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/yourusername/cropaway.git`
3. Install FFmpeg: `brew install ffmpeg`
4. Open in Xcode and build

## Code Style

- Follow Swift API Design Guidelines
- Use SwiftLint (if configured)
- Write clear, descriptive commit messages
- Add comments for complex logic

## Swift Guidelines

- Prefer Swift Concurrency (async/await) over callbacks
- Use `@MainActor` for UI-related classes
- Avoid force unwrapping (`!`) unless truly safe
- Use guard statements for early returns
- Prefer value types (struct) over reference types (class) when appropriate

## Project Architecture

```
Models: Data structures (VideoItem, CropConfiguration, etc.)
ViewModels: Business logic (@ObservableObject classes)
Views: SwiftUI views
Services: Core functionality (FFmpeg, metadata extraction)
Extensions: Helper methods on existing types
```

## Making Changes

1. Create a feature branch: `git checkout -b feature/your-feature`
2. Make your changes
3. Test thoroughly
4. Commit with clear messages: `git commit -m "Add: circle crop feathering"`
5. Push to your fork: `git push origin feature/your-feature`
6. Open a Pull Request

## Commit Message Format

Use conventional commits:

- `Add: new feature`
- `Fix: bug description`
- `Update: improved behavior`
- `Refactor: code restructuring`
- `Docs: documentation changes`
- `Test: add or update tests`

## Testing

- Test with various video formats (H.264, HEVC, ProRes)
- Test with different resolutions and aspect ratios
- Test keyframe animation
- Test export with all crop modes
- Verify performance with large files

## Pull Request Process

1. Update CHANGELOG.md with your changes
2. Ensure code builds without warnings
3. Update documentation if needed
4. Request review from maintainers

## Bug Reports

When filing a bug report, include:

- macOS version
- App version
- Steps to reproduce
- Expected vs actual behavior
- Video format/codec if relevant
- Console logs (if applicable)

## Feature Requests

- Check if the feature already exists
- Describe the use case
- Explain why it would be valuable
- Consider implementation complexity

## Code Review

All submissions require review. We aim to:

- Respond to PRs within 3 days
- Provide constructive feedback
- Merge approved PRs within 1 week

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (MIT).

## Questions?

Open an issue or discussion for questions about contributing.
