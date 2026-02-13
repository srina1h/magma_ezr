#!/bin/bash
# Setup script for local Linux execution (no Docker)
# Installs dependencies and prepares the system for fuzzing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Magma EZR Local Setup"
echo "=========================================="

# Detect Linux distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Warning: Cannot detect Linux distribution"
    OS="unknown"
fi

echo "Detected OS: $OS"

# Install system dependencies
echo ""
echo "Installing system dependencies..."

if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    sudo apt-get update
    sudo apt-get install -y \
        util-linux \
        inotify-tools \
        git \
        python3 \
        python3-pip \
        build-essential \
        make \
        gcc \
        g++ \
        || echo "Warning: Some packages may have failed to install"
elif [ "$OS" = "fedora" ] || [ "$OS" = "rhel" ] || [ "$OS" = "centos" ]; then
    sudo dnf install -y \
        util-linux \
        inotify-tools \
        git \
        python3 \
        python3-pip \
        gcc \
        gcc-c++ \
        make \
        || echo "Warning: Some packages may have failed to install"
elif [ "$OS" = "arch" ] || [ "$OS" = "manjaro" ]; then
    sudo pacman -S --noconfirm \
        util-linux \
        inotify-tools \
        git \
        python \
        python-pip \
        base-devel \
        || echo "Warning: Some packages may have failed to install"
else
    echo "Warning: Unknown distribution. Please install manually:"
    echo "  - util-linux (for flock)"
    echo "  - inotify-tools (for inotifywait)"
    echo "  - git"
    echo "  - python3, python3-pip"
    echo "  - build-essential / gcc, g++, make"
fi

# Install Python dependencies
echo ""
echo "Installing Python dependencies..."
pip3 install --user pandas matplotlib || pip3 install pandas matplotlib

# Check for magma directory
echo ""
echo "Checking for magma directory..."
if [ ! -d "$REPO_ROOT/magma" ]; then
    echo "Warning: magma directory not found!"
    echo "You may need to clone it manually:"
    echo "  git submodule update --init --recursive"
    echo "  OR"
    echo "  git clone https://github.com/HexHive/magma.git $REPO_ROOT/magma"
    echo ""
    read -p "Do you want to clone magma now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cd "$REPO_ROOT"
        if [ -f ".gitmodules" ]; then
            git submodule update --init --recursive
        else
            git clone https://github.com/HexHive/magma.git magma
        fi
    fi
else
    echo "✓ magma directory found"
fi

# Verify magma structure
if [ -d "$REPO_ROOT/magma" ]; then
    if [ -f "$REPO_ROOT/magma/tools/captain/run.sh" ]; then
        echo "✓ magma structure looks correct"
    else
        echo "Warning: magma structure may be incomplete"
        echo "  Expected: $REPO_ROOT/magma/tools/captain/run.sh"
    fi
fi

# Create necessary directories
echo ""
echo "Creating directories..."
mkdir -p "$REPO_ROOT/dataset_results"
mkdir -p "$REPO_ROOT/workdir"

# Make scripts executable
echo ""
echo "Making scripts executable..."
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
chmod +x "$SCRIPT_DIR"/*.py 2>/dev/null || true

echo ""
echo "=========================================="
echo "Setup complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Review scripts/afl_params.json (5 binary parameters)"
echo "  2. Run: python3 scripts/build_dataset.py --budget 20m"
echo "  3. Resume if needed: python3 scripts/build_dataset.py --resume"
echo "  4. Aggregate results: python3 scripts/aggregate_results.py"
echo ""
