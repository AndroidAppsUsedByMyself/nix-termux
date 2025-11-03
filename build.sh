#!/usr/bin/env bash
# Build script for bootstrapping Nix for Termux
# This automates the multi-stage bootstrap process

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

# Check if we have Nix available
if ! command -v nix-build &> /dev/null; then
    error "nix-build not found. You need a working Nix installation to bootstrap."
    error "Please install Nix first: https://nixos.org/download.html"
    exit 1
fi

# Check current system
CURRENT_SYSTEM=$(nix-instantiate --eval -E 'builtins.currentSystem' | tr -d '"')
log "Current system: $CURRENT_SYSTEM"

# We need to build for aarch64-linux
TARGET_SYSTEM="aarch64-linux"

if [ "$CURRENT_SYSTEM" != "$TARGET_SYSTEM" ]; then
    warn "Current system ($CURRENT_SYSTEM) differs from target ($TARGET_SYSTEM)"
    warn "Cross-compilation may be required or you may need to build on target system."
    
    # Check if we can cross-compile
    if ! nix-instantiate --eval -E "builtins.hasAttr \"$TARGET_SYSTEM\" (import <nixpkgs> {}).pkgsCross" &> /dev/null; then
        error "Cross-compilation to $TARGET_SYSTEM may not be supported."
        exit 1
    fi
fi

# Create output directory
OUTPUT_DIR="$(pwd)/result"
mkdir -p "$OUTPUT_DIR"

log "Starting Nix bootstrap process..."
log "This will take a while (potentially hours) as it builds:"
log "  - Nix itself"
log "  - All stdenv bootstrap stages"
log "  - Essential utilities"
echo ""

# Stage 1: Build the installer
log "Building Nix installer for Termux..."
log "Building with: nix-build bootstrap.nix -A installer --argstr system $TARGET_SYSTEM"

if nix-build bootstrap.nix -A installer --argstr system "$TARGET_SYSTEM" -o "$OUTPUT_DIR/installer"; then
    success "Installer built successfully!"
    
    # Find the tarball
    TARBALL=$(find "$OUTPUT_DIR/installer" -name "*.tar.gz" | head -n 1)
    
    if [ -n "$TARBALL" ]; then
        TARBALL_SIZE=$(du -h "$TARBALL" | cut -f1)
        success "Tarball created: $TARBALL"
        log "Tarball size: $TARBALL_SIZE"
        
        # Copy to a more convenient location
        cp "$TARBALL" "$OUTPUT_DIR/nix-termux-aarch64.tar.gz"
        success "Copied to: $OUTPUT_DIR/nix-termux-aarch64.tar.gz"
    else
        error "Could not find tarball in installer output"
        exit 1
    fi
    
    echo ""
    log "=========================================="
    log "Bootstrap build complete!"
    log "=========================================="
    echo ""
    log "Next steps:"
    log "1. Transfer the tarball to your Termux device:"
    log "   $OUTPUT_DIR/nix-termux-aarch64.tar.gz"
    echo ""
    log "2. On Termux, extract and run the installer:"
    log "   tar -xzf nix-termux-aarch64.tar.gz"
    log "   cd tarball"
    log "   ./install.sh"
    echo ""
    log "3. Follow the instructions displayed by the installer"
    echo ""
    
else
    error "Build failed!"
    exit 1
fi
