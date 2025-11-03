#!/usr/bin/env bash
# Build script for bootstrapping Nix for Termux
# This automates the cross-compilation bootstrap process
#
# References:
# - https://nix.dev/tutorials/cross-compilation.html (official tutorial)
# - https://nixos.org/manual/nixpkgs/stable/#chap-cross (official infrastructure)
# - https://nixos.wiki/wiki/Cross_Compiling (community examples)
# - https://matthewbauer.us/blog/beginners-guide-to-cross.html (2018 - historical context)

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

# Target platform configuration (following nix.dev guide)
# Using the standard platform config string format: <cpu>-<vendor>-<os>-<abi>
# This is the LLVM target triple format, recognized by GCC, Clang, and other toolchains
TARGET_PLATFORM="aarch64-unknown-linux-gnu"

# Note: We use 'unknown' as the vendor because:
# 1. It's a convention for systems without a specific vendor (like PC or Apple)
# 2. It's what config.guess returns on generic ARM Linux systems
# 3. It matches nixpkgs' pkgsCross.aarch64-multiplatform definition

if [ "$CURRENT_SYSTEM" != "aarch64-linux" ]; then
    warn "Current system ($CURRENT_SYSTEM) differs from target (aarch64-linux)"
    log "Will cross-compile to: $TARGET_PLATFORM"
    log "Using crossSystem configuration as per https://nix.dev/tutorials/cross-compilation.html"
    
    # Check if we have binfmt support for running aarch64 binaries
    if [ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
        success "QEMU binfmt support detected - can run aarch64 binaries"
    else
        warn "No QEMU binfmt support detected"
        log "This is OK - cross-compilation will work, but you won't be able to test binaries locally"
    fi
fi

# Create output directory
OUTPUT_DIR="$(pwd)/result"
mkdir -p "$OUTPUT_DIR"

log "Starting Nix bootstrap process..."
log ""
log "WHAT THIS SCRIPT DOES:"
log "  1. Cross-compiles Nix and dependencies for aarch64-linux"
log "  2. Collects all stdenv bootstrap stages (to avoid toolchain rebuilds)"
log "  3. Bundles essential utilities (bash, coreutils, git, etc.)"
log "  4. Creates a tarball with installation script"
log ""
log "This will take a while (potentially hours) as it builds:"
log "  - Nix itself"
log "  - All stdenv bootstrap stages"
log "  - Essential utilities"
log ""
log "TECHNICAL NOTE:"
log "  We use patchelf during the build to rewrite ELF interpreter paths."
log "  Binaries are built for /nix/store, then patched to use"
log "  /data/data/com.termux/files/nix/store before packaging."
echo ""

# Stage 1: Build the installer using cross-compilation
log "Building Nix installer for Termux..."
log "Using crossSystem: { config = \"$TARGET_PLATFORM\"; }"
log ""
log "Note: This may take a LONG time (several hours) as it builds:"
log "  - The entire GCC toolchain for aarch64"
log "  - Glibc and system libraries"
log "  - All stdenv bootstrap stages"
log "  - Nix and dependencies"
log "  - Essential utilities"
log ""
log "Following the cross-compilation approach from:"
log "  https://nix.dev/tutorials/cross-compilation.html"
log ""

if nix-build bootstrap.nix -A installer \
    --arg crossSystem "{ config = \"$TARGET_PLATFORM\"; }" \
    -o "$OUTPUT_DIR/installer" 2>&1 | tee "$OUTPUT_DIR/build.log"; then
    success "Installer built successfully!"
    
    # Find the tarball (following symlinks with -L)
    TARBALL=$(find -L "$OUTPUT_DIR/installer" -maxdepth 1 -name "nix-termux-aarch64.tar.gz" -type f | head -n 1)
    
    if [ -n "$TARBALL" ]; then
        TARBALL_SIZE=$(du -h "$TARBALL" | cut -f1)
        success "Tarball found: $TARBALL"
        log "Tarball size: $TARBALL_SIZE"
        
        # Copy to a more convenient location
        cp "$TARBALL" "$OUTPUT_DIR/nix-termux-aarch64.tar.gz"
        success "Copied to: $OUTPUT_DIR/nix-termux-aarch64.tar.gz"
    else
        error "Could not find tarball in installer output"
        log "Contents of installer output:"
        ls -la "$OUTPUT_DIR/installer"
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
