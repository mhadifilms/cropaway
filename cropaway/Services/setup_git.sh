#!/bin/bash

# Initialize Git repository and make initial commit

set -e

echo "🚀 Setting up Git repository for cropaway..."

# Initialize git if not already initialized
if [ ! -d .git ]; then
    echo "📦 Initializing Git repository..."
    git init
    echo "✅ Git initialized"
else
    echo "ℹ️  Git repository already exists"
fi

# Configure git to ignore Xcode user-specific files
git config --local core.excludesfile .gitignore

# Add all files
echo "📝 Adding files to Git..."
git add .

# Create initial commit if no commits exist
if ! git rev-parse HEAD >/dev/null 2>&1; then
    echo "💾 Creating initial commit..."
    git commit -m "Initial commit: cropaway video cropping app

- SwiftUI-based macOS app for video cropping
- Support for rectangle, circle, and freehand crops
- Keyframe animation system
- FFmpeg integration for export
- Hardware-accelerated encoding (VideoToolbox)
- Professional playback controls
- Real-time preview"
    echo "✅ Initial commit created"
else
    echo "ℹ️  Repository already has commits"
    
    # Check if there are staged changes
    if ! git diff --cached --quiet; then
        echo "💾 Committing current changes..."
        git commit -m "Update: project files and documentation"
        echo "✅ Changes committed"
    else
        echo "ℹ️  No changes to commit"
    fi
fi

# Show status
echo ""
echo "📊 Git Status:"
git status

echo ""
echo "✅ Git setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Create a GitHub repository"
echo "2. Add remote: git remote add origin https://github.com/yourusername/cropaway.git"
echo "3. Push: git push -u origin main"
echo ""
echo "Or create new branch for features:"
echo "git checkout -b feature/your-feature-name"
