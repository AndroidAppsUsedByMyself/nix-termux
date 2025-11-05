#!/data/data/com.termux/files/usr/bin/bash
# One-line installer for Nix on Termux
# 
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/mio-19/nix-termux/main/install-nix-termux.sh | bash
# Or:
#   wget -qO- https://raw.githubusercontent.com/mio-19/nix-termux/main/install-nix-termux.sh | bash

set -e

# Configuration
REPO_OWNER="AndroidAppsUsedByMyself"
REPO_NAME="nix-termux"
GITHUB_API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
TERMUX_PREFIX="/data/data/com.termux/files"
TMP_DIR="${TERMUX_PREFIX}/tmp/nix-install-$$"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${BLUE}==>${NC} $1"
}

success() {
    echo -e "${GREEN}==>${NC} $1"
}

warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

error() {
    echo -e "${RED}Error:${NC} $1" >&2
}

die() {
    error "$1"
    exit 1
}

# Banner
echo ""
echo "╔════════════════════════════════════════╗"
echo "║     Nix for Termux Installer           ║"
echo "╔════════════════════════════════════════╝"
echo "║"
echo "║  Repository: ${REPO_OWNER}/${REPO_NAME}"
echo "║"
echo "╚════════════════════════════════════════"
echo ""

# Check if running on Termux
info "Checking environment..."

if [ ! -d "${TERMUX_PREFIX}" ]; then
    die "This script must be run in Termux on Android"
fi

# Check architecture
ARCH=$(uname -m)
SUPPORTED_ARCHS=("aarch64" "armv7l" "x86_64" "i686")

if [[ ! " ${SUPPORTED_ARCHS[*]} " =~ " ${ARCH} " ]]; then
    die "Unsupported architecture: $ARCH. Supported: ${SUPPORTED_ARCHS[*]}"
fi

success "Environment check passed (${ARCH})"

# Check for required tools
info "Checking for required tools..."
MISSING_TOOLS=""

for tool in curl tar gzip; do
    if ! command -v "$tool" &> /dev/null; then
        MISSING_TOOLS="$MISSING_TOOLS $tool"
    fi
done

if [ -n "$MISSING_TOOLS" ]; then
    warning "Missing tools:$MISSING_TOOLS"
    info "Installing missing tools with pkg..."
    pkg install -y $MISSING_TOOLS || die "Failed to install required tools"
fi

success "All required tools available"

# Check available disk space
info "Checking disk space..."
AVAILABLE_KB=$(df "${TERMUX_PREFIX}" | awk 'NR==2 {print $4}')
AVAILABLE_GB=$((AVAILABLE_KB / 1024 / 1024))

if [ "$AVAILABLE_GB" -lt 2 ]; then
    warning "Low disk space: ${AVAILABLE_GB}GB available"
    warning "At least 2GB recommended for Nix installation"
    echo -n "Continue anyway? [y/N] "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        die "Installation cancelled by user"
    fi
else
    success "Sufficient disk space: ${AVAILABLE_GB}GB available"
fi

# Fetch latest release information from GitHub API
info "Fetching latest release information..."
RELEASE_JSON=$(mktemp)

if ! curl -fsSL "$GITHUB_API" -o "$RELEASE_JSON"; then
    die "Failed to fetch release information from GitHub API"
fi

# Parse release information
RELEASE_TAG=$(grep -o '"tag_name": *"[^"]*"' "$RELEASE_JSON" | head -1 | sed 's/"tag_name": *"\([^"]*\)"/\1/')

# Find the download URL for the specific architecture
DOWNLOAD_URL=$(grep -o '"browser_download_url": *"[^"]*'${ARCH}'[^"]*\.tar\.gz"' "$RELEASE_JSON" | head -1 | sed 's/"browser_download_url": *"\([^"]*\)"/\1/')

rm -f "$RELEASE_JSON"

if [ -z "$RELEASE_TAG" ] || [ -z "$DOWNLOAD_URL" ]; then
    die "Failed to parse release information for architecture $ARCH. Please check the repository has releases for this architecture."
fi

success "Found latest release: ${RELEASE_TAG}"
echo "  Architecture: $ARCH"
echo "  Download URL: $DOWNLOAD_URL"

# Create temporary directory
info "Creating temporary directory..."
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

# Download the release
info "Downloading Nix tarball..."
echo ""

if ! curl -fL --progress-bar "$DOWNLOAD_URL" -o nix-termux.tar.gz; then
    die "Failed to download release tarball"
fi

success "Download complete"

# Verify the tarball
info "Verifying tarball..."
if ! tar -tzf nix-termux.tar.gz > /dev/null 2>&1; then
    die "Downloaded file is not a valid tar.gz archive"
fi

success "Tarball verified"

# Extract the tarball
info "Extracting tarball..."
if ! tar -xzf nix-termux.tar.gz; then
    die "Failed to extract tarball"
fi

success "Extraction complete"

# Check if installer exists
if [ ! -f "tarball/install.sh" ]; then
    die "Installer script not found in tarball"
fi

# Run the installer
info "Running Nix installer..."
echo ""

cd tarball
if ! bash ./install.sh; then
    die "Installation failed"
fi

echo ""
success "Nix installation completed successfully!"

# Set up environment
info "Setting up environment..."

SHELL_RC=""
if [ -n "$SHELL" ]; then
    case "$SHELL" in
        */bash)
            SHELL_RC="$HOME/.bashrc"
            ;;
        */zsh)
            SHELL_RC="$HOME/.zshrc"
            ;;
        *)
            SHELL_RC="$HOME/.bashrc"
            ;;
    esac
else
    SHELL_RC="$HOME/.bashrc"
fi

# Check if already configured
if ! grep -q "NIX_STORE_DIR" "$SHELL_RC" 2>/dev/null; then
    info "Adding Nix environment to $SHELL_RC..."
    
    cat >> "$SHELL_RC" << 'EOF'

# Nix environment for Termux
export NIX_PREFIX="/data/data/com.termux/files/nix"
export NIX_STORE_DIR="$NIX_PREFIX/store"
export NIX_STATE_DIR="$NIX_PREFIX/var"
export NIX_CONF_DIR="$NIX_PREFIX/etc"
export PATH="$NIX_STATE_DIR/nix/profiles/default/bin:$PATH"

# SSL certificates (adjust if needed)
if [ -d "$NIX_STORE_DIR" ]; then
    NIX_CACERT_PATH=$(find "$NIX_STORE_DIR" -maxdepth 1 -name '*-nss-cacert-*' -type d | head -n1)
    if [ -n "$NIX_CACERT_PATH" ]; then
        export NIX_SSL_CERT_FILE="$NIX_CACERT_PATH/etc/ssl/certs/ca-bundle.crt"
    fi
fi
EOF

    success "Environment configuration added to $SHELL_RC"
else
    info "Nix environment already configured in $SHELL_RC"
fi

# Clean up
info "Cleaning up temporary files..."
cd /
rm -rf "$TMP_DIR"

# Final instructions
echo ""
echo "╔════════════════════════════════════════╗"
echo "║         Installation Complete!         ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "To start using Nix, run:"
echo ""
echo "  ${GREEN}source $SHELL_RC${NC}"
echo ""
echo "Or restart your terminal."
echo ""
echo "Then verify the installation:"
echo ""
echo "  ${BLUE}nix-env --version${NC}"
echo ""
echo "Quick start:"
echo ""
echo "  # Install a package"
echo "  ${BLUE}nix-env -iA nixpkgs.hello${NC}"
echo ""
echo "  # Search for packages"
echo "  ${BLUE}nix-env -qaP | grep python${NC}"
echo ""
echo "  # List installed packages"
echo "  ${BLUE}nix-env -q${NC}"
echo ""
echo "  # Garbage collection"
echo "  ${BLUE}nix-collect-garbage -d${NC}"
echo ""
echo "Important notes:"
echo ""
echo "  • Binary caches are disabled (custom prefix)"
echo "  • All packages will be built from source"
echo "  • First builds may take significant time"
echo "  • Use 'nix-collect-garbage' regularly to free space"
echo ""
echo "For more information:"
echo "  https://github.com/${REPO_OWNER}/${REPO_NAME}"
echo ""

# Source the environment for this session if possible
if [ -f "$SHELL_RC" ]; then
    info "Loading Nix environment for current session..."
    # shellcheck disable=SC1090
    . "$SHELL_RC" 2>/dev/null || true
    
    # Test if nix is available
    if command -v nix-env &> /dev/null; then
        echo ""
        success "Nix is ready to use!"
        echo "  Version: $(nix-env --version)"
    fi
fi

echo ""