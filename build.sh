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

# Help message
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Build Nix for Termux for specified architecture(s)"
    echo ""
    echo "Options:"
    echo "  -a, --arch ARCH       Build for specific architecture (aarch64, armv7l, x86_64, i686)"
    echo "  -A, --all             Build for all supported architectures"
    echo "  -l, --list            List supported architectures"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Build for aarch64 (default)"
    echo "  $0 -a armv7l          # Build for armv7l only"
    echo "  $0 -A                 # Build for all architectures"
    echo "  $0 -a aarch64 -a x86_64  # Build for aarch64 and x86_64"
}

# Supported architectures
SUPPORTED_ARCHS=("aarch64" "armv7l" "x86_64" "i686")

# Architecture to target platform mapping
declare -A TARGET_PLATFORMS
TARGET_PLATFORMS["aarch64"]="aarch64-unknown-linux-gnu"
TARGET_PLATFORMS["armv7l"]="armv7l-unknown-linux-gnueabihf"
TARGET_PLATFORMS["x86_64"]="x86_64-unknown-linux-gnu"
TARGET_PLATFORMS["i686"]="i686-unknown-linux-gnu"

# Parse command line arguments
ARCHS_TO_BUILD=()
BUILD_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--arch)
            if [[ " ${SUPPORTED_ARCHS[*]} " =~ " $2 " ]]; then
                ARCHS_TO_BUILD+=("$2")
                shift 2
            else
                error "Unsupported architecture: $2"
                error "Supported architectures: ${SUPPORTED_ARCHS[*]}"
                exit 1
            fi
            ;;
        -A|--all)
            BUILD_ALL=true
            shift
            ;;
        -l|--list)
            echo "Supported architectures:"
            for arch in "${SUPPORTED_ARCHS[@]}"; do
                echo "  - $arch (${TARGET_PLATFORMS[$arch]})"
            done
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# If no arch specified, build for aarch64 by default (maintain backward compatibility)
if [ ${#ARCHS_TO_BUILD[@]} -eq 0 ] && [ "$BUILD_ALL" = false ]; then
    ARCHS_TO_BUILD=("aarch64")
fi

# If --all specified, build for all architectures
if [ "$BUILD_ALL" = true ]; then
    ARCHS_TO_BUILD=("${SUPPORTED_ARCHS[@]}")
fi

# Check if we have Nix available
if ! command -v nix-build &> /dev/null; then
    error "nix-build not found. You need a working Nix installation to bootstrap."
    error "Please install Nix first: https://nixos.org/download.html"
    exit 1
fi

# Check current system
CURRENT_SYSTEM=$(nix-instantiate --eval -E 'builtins.currentSystem' | tr -d '"')
log "Current system: $CURRENT_SYSTEM"

# Create output directory
OUTPUT_DIR="$(pwd)/result"
mkdir -p "$OUTPUT_DIR"

log "Starting Nix bootstrap process for architectures: ${ARCHS_TO_BUILD[*]}"
log ""
log "WHAT THIS SCRIPT DOES:"
log "  1. Cross-compiles Nix and dependencies for specified architectures"
log "  2. Collects all stdenv bootstrap stages (to avoid toolchain rebuilds)"
log "  3. Bundles essential utilities (bash, coreutils, git, etc.)"
log "  4. Creates tarballs with installation scripts"
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

# Function to build for a specific architecture
build_for_arch() {
    local arch=$1
    local target_platform=${TARGET_PLATFORMS[$arch]}
    
    log "Building Nix installer for Termux ($arch)..."
    log "Using crossSystem: { config = \"$target_platform\"; }"
    log ""
    log "Note: This may take a LONG time (several hours) as it builds:"
    log "  - The entire GCC toolchain for $arch"
    log "  - Glibc and system libraries"
    log "  - All stdenv bootstrap stages"
    log "  - Nix and dependencies"
    log "  - Essential utilities"
    log ""
    log "Following the cross-compilation approach from:"
    log "  https://nix.dev/tutorials/cross-compilation.html"
    log ""
    
    local arch_output_dir="$OUTPUT_DIR/$arch"
    mkdir -p "$arch_output_dir"
    
    if nix-build bootstrap.nix -A "installer.$arch.installer" \
        --arg crossSystem "{ config = \"$target_platform\"; }" \
        -o "$arch_output_dir/installer" 2>&1 | tee "$arch_output_dir/build.log"; then
        success "Installer built successfully for $arch!"
        
        # Find the tarball (following symlinks with -L)
        TARBALL=$(find -L "$arch_output_dir/installer" -maxdepth 1 -name "nix-termux-$arch.tar.gz" -type f | head -n 1)
        
        if [ -n "$TARBALL" ]; then
            TARBALL_SIZE=$(du -h "$TARBALL" | cut -f1)
            success "Tarball found: $TARBALL"
            log "Tarball size: $TARBALL_SIZE"
            
            # Copy to a more convenient location
            cp "$TARBALL" "$OUTPUT_DIR/nix-termux-$arch.tar.gz"
            success "Copied to: $OUTPUT_DIR/nix-termux-$arch.tar.gz"
        else
            error "Could not find tarball in installer output for $arch"
            log "Contents of installer output:"
            ls -la "$arch_output_dir/installer"
            return 1
        fi
    else
        error "Build failed for $arch!"
        return 1
    fi
}

# Build for each architecture
FAILED_ARCHS=()
for arch in "${ARCHS_TO_BUILD[@]}"; do
    echo ""
    log "=========================================="
    log "Building for architecture: $arch"
    log "=========================================="
    echo ""
    
    if ! build_for_arch "$arch"; then
        FAILED_ARCHS+=("$arch")
    fi
done

# Summary
echo ""
log "=========================================="
log "Build process complete!"
log "=========================================="
echo ""

if [ ${#FAILED_ARCHS[@]} -eq 0 ]; then
    success "All builds completed successfully!"
    
    log "Generated installers:"
    for arch in "${ARCHS_TO_BUILD[@]}"; do
        if [ -f "$OUTPUT_DIR/nix-termux-$arch.tar.gz" ]; then
            log "  - $OUTPUT_DIR/nix-termux-$arch.tar.gz"
        fi
    done
    
    echo ""
    log "Next steps:"
    log "1. Transfer the tarballs to your Termux devices"
    for arch in "${ARCHS_TO_BUILD[@]}"; do
        log "   $OUTPUT_DIR/nix-termux-$arch.tar.gz"
    done
    echo ""
    log "2. On Termux, extract and run the installer:"
    log "   tar -xzf nix-termux-<arch>.tar.gz"
    log "   cd tarball"
    log "   ./install.sh"
    echo ""
    log "3. Follow the instructions displayed by the installer"
    echo ""
else
    error "Builds failed for architectures: ${FAILED_ARCHS[*]}"
    exit 1
fi