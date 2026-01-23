#!/bin/bash
#
# Cropaway AI Setup Script
# Installs Python dependencies for SAM AI segmentation
#

set -e

echo "========================================"
echo "  Cropaway AI Mask Setup"
echo "========================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for Python 3.10+
check_python() {
    echo "Checking Python installation..."

    # Try common Python paths
    PYTHON_PATHS=(
        "/opt/homebrew/bin/python3"
        "/usr/local/bin/python3"
        "/usr/bin/python3"
        "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3"
        "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3"
        "/Library/Frameworks/Python.framework/Versions/3.10/bin/python3"
    )

    PYTHON_PATH=""
    for path in "${PYTHON_PATHS[@]}"; do
        if [ -f "$path" ]; then
            # Check version
            VERSION=$("$path" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
            MAJOR=$(echo "$VERSION" | cut -d. -f1)
            MINOR=$(echo "$VERSION" | cut -d. -f2)

            if [ "$MAJOR" -ge 3 ] && [ "$MINOR" -ge 10 ]; then
                PYTHON_PATH="$path"
                echo -e "${GREEN}✓ Found Python $VERSION at $path${NC}"
                break
            fi
        fi
    done

    if [ -z "$PYTHON_PATH" ]; then
        echo -e "${RED}✗ Python 3.10+ not found${NC}"
        echo ""
        echo "Please install Python 3.10 or later:"
        echo ""
        echo "  Using Homebrew (recommended):"
        echo "    brew install python@3.12"
        echo ""
        echo "  Or download from:"
        echo "    https://www.python.org/downloads/"
        echo ""
        exit 1
    fi

    export PYTHON_PATH
}

# Install pip if needed
check_pip() {
    echo ""
    echo "Checking pip..."

    if ! "$PYTHON_PATH" -m pip --version &> /dev/null; then
        echo "Installing pip..."
        "$PYTHON_PATH" -m ensurepip --upgrade
    fi

    echo -e "${GREEN}✓ pip is available${NC}"
}

# Install requirements
install_requirements() {
    echo ""
    echo "Installing Python packages..."
    echo "This may take a few minutes..."
    echo ""

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REQUIREMENTS_FILE="$SCRIPT_DIR/requirements.txt"

    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        echo -e "${RED}✗ requirements.txt not found at $REQUIREMENTS_FILE${NC}"
        exit 1
    fi

    "$PYTHON_PATH" -m pip install --user -r "$REQUIREMENTS_FILE"

    echo ""
    echo -e "${GREEN}✓ Packages installed successfully${NC}"
}

# Verify installation
verify_installation() {
    echo ""
    echo "Verifying installation..."

    PACKAGES=("torch" "transformers" "flask" "PIL" "numpy")
    ALL_OK=true

    for pkg in "${PACKAGES[@]}"; do
        if "$PYTHON_PATH" -c "import $pkg" &> /dev/null; then
            echo -e "  ${GREEN}✓ $pkg${NC}"
        else
            echo -e "  ${RED}✗ $pkg${NC}"
            ALL_OK=false
        fi
    done

    if [ "$ALL_OK" = true ]; then
        echo ""
        echo -e "${GREEN}========================================"
        echo "  Setup Complete!"
        echo "========================================${NC}"
        echo ""
        echo "You can now use AI Mask in Cropaway:"
        echo "  1. Open Cropaway"
        echo "  2. Press ⌘4 to switch to AI mode"
        echo "  3. Click 'Start AI' in the toolbar"
        echo "  4. Click on objects to select them"
        echo ""
        echo -e "${YELLOW}Note: The AI model (~2GB) will be downloaded"
        echo -e "automatically on first use.${NC}"
    else
        echo ""
        echo -e "${RED}Some packages failed to install.${NC}"
        echo "Please check the error messages above."
        exit 1
    fi
}

# Main
main() {
    check_python
    check_pip
    install_requirements
    verify_installation
}

main "$@"
