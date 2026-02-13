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
echo "NOTE: Docker is required for building magma targets (but not for running fuzzing)"

if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    sudo apt-get update
    sudo apt-get install -y \
        docker.io \
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
    
    # Start docker service
    if command -v systemctl >/dev/null 2>&1; then
        echo ""
        echo "Starting Docker service..."
        sudo systemctl enable docker 2>/dev/null || true
        sudo systemctl start docker 2>/dev/null || true
    fi
    
    # Add user to docker group if docker is installed
    if command -v docker >/dev/null 2>&1; then
        echo ""
        echo "Adding user to docker group (may require logout/login)..."
        sudo usermod -aG docker "$USER" 2>/dev/null || echo "Warning: Could not add user to docker group"
        echo "You may need to logout and login again, or run: newgrp docker"
    fi
elif [ "$OS" = "fedora" ] || [ "$OS" = "rhel" ] || [ "$OS" = "centos" ]; then
    sudo dnf install -y \
        docker \
        util-linux \
        inotify-tools \
        git \
        python3 \
        python3-pip \
        gcc \
        gcc-c++ \
        make \
        || echo "Warning: Some packages may have failed to install"
    
    # Start docker service
    sudo systemctl enable docker 2>/dev/null || true
    sudo systemctl start docker 2>/dev/null || true
    
    # Add user to docker group
    if command -v docker >/dev/null 2>&1; then
        echo ""
        echo "Adding user to docker group (may require logout/login)..."
        sudo usermod -aG docker "$USER" 2>/dev/null || echo "Warning: Could not add user to docker group"
    fi
elif [ "$OS" = "arch" ] || [ "$OS" = "manjaro" ]; then
    sudo pacman -S --noconfirm \
        docker \
        util-linux \
        inotify-tools \
        git \
        python \
        python-pip \
        base-devel \
        || echo "Warning: Some packages may have failed to install"
    
    # Start docker service
    sudo systemctl enable docker 2>/dev/null || true
    sudo systemctl start docker 2>/dev/null || true
    
    # Add user to docker group
    if command -v docker >/dev/null 2>&1; then
        echo ""
        echo "Adding user to docker group (may require logout/login)..."
        sudo usermod -aG docker "$USER" 2>/dev/null || echo "Warning: Could not add user to docker group"
    fi
else
    echo "Warning: Unknown distribution. Please install manually:"
    echo "  - docker (required for building magma targets)"
    echo "  - util-linux (for flock)"
    echo "  - inotify-tools (for inotifywait)"
    echo "  - git"
    echo "  - python3, python3-pip"
    echo "  - build-essential / gcc, g++, make"
fi

# Verify and configure Docker
echo ""
echo "Verifying Docker installation..."
if command -v docker >/dev/null 2>&1; then
    # Start Docker service if systemd is available
    if command -v systemctl >/dev/null 2>&1; then
        echo "Starting Docker service..."
        sudo systemctl enable docker 2>/dev/null || true
        sudo systemctl start docker 2>/dev/null || true
    fi
    
    # Test Docker access
    if docker ps >/dev/null 2>&1; then
        echo "✓ Docker is installed and accessible"
    else
        echo "⚠ Docker is installed but not accessible"
        echo "  Attempting to fix..."
        
        # Try adding user to docker group again
        sudo usermod -aG docker "$USER" 2>/dev/null || true
        
        echo ""
        echo "  Docker setup complete, but you need to:"
        echo "    1. Logout and login again, OR"
        echo "    2. Run: newgrp docker"
        echo ""
        echo "  Then test with: docker ps"
        echo "  After that, run: ./scripts/check_build.sh"
    fi
else
    echo "✗ Docker is not installed"
    echo "  Docker is required for building magma targets"
    echo "  Please install Docker manually:"
    echo "    Ubuntu/Debian: sudo apt-get install docker.io"
    echo "    Fedora/RHEL: sudo dnf install docker"
    echo "    Arch: sudo pacman -S docker"
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
        echo "Applying magma patches (fixes timeout/sleep defaults)..."
        "$SCRIPT_DIR/apply_magma_patches.sh" 2>/dev/null || echo "  (patches applied or skipped)"
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
echo "IMPORTANT: If Docker was just installed, you may need to:"
echo "  1. Logout and login again, OR"
echo "  2. Run: newgrp docker"
echo ""
echo "Then verify Docker works:"
echo "  docker ps"
echo ""
echo "Fix core_pattern (required for AFL, run once with sudo):"
echo "  sudo ./scripts/fix_core_pattern.sh"
echo ""
echo "Next steps:"
echo "  1. Fix core_pattern: sudo ./scripts/fix_core_pattern.sh"
echo "  2. Test build: ./scripts/check_build.sh"
echo "  3. Run dataset: python3 scripts/build_dataset.py --budget 20m"
echo "  4. Resume if needed: python3 scripts/build_dataset.py --resume"
echo "  5. Aggregate results: python3 scripts/aggregate_results.py"
echo ""
