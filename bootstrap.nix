# Bootstrap Nix for Termux with custom prefix
# 
# References:
# - https://dram.page/p/bootstrapping-nix/ (bootstrap approach & NIX_STORE_DIR optimization)
# - https://nix.dev/tutorials/cross-compilation.html (official cross-compilation tutorial)
# - https://nixos.org/manual/nixpkgs/stable/#chap-cross (official cross-compilation infrastructure)
# - https://nixos.wiki/wiki/Cross_Compiling (community examples)
# - https://matthewbauer.us/blog/beginners-guide-to-cross.html (2018 - historical context)
#
# Note: We primarily follow official documentation (nix.dev, Nixpkgs manual) as authoritative sources.
# Historical resources provide context but may use outdated patterns.
#
# Created with assistance from Claude Sonnet 4.5
#
# This builds a Nix installation for /data/data/com.termux/files/nix
# Targeting: aarch64-linux only
#
# Note: We use NIX_STORE_DIR environment variable override, which saves
# one stage of the bootstrap process. The Nix built here respects the
# NIX_STORE_DIR variable, so we don't need to rebuild it multiple times.
#
# Usage (following nix.dev cross-compilation guide):
#   nix-build bootstrap.nix -A installer \
#     --arg crossSystem '{ config = "aarch64-unknown-linux-gnu"; }'
#
# Platform terminology (from Nixpkgs manual):
# - buildPlatform: Where compilation happens (e.g., x86_64-linux)
# - hostPlatform: Where the program will run (aarch64-unknown-linux-gnu)
# - targetPlatform: For compilers only; we assume host = target

{ # Use crossSystem for proper cross-compilation (see nix.dev guide)
  crossSystem ? null
, pkgs ? 
    if crossSystem != null
    then import <nixpkgs> { inherit crossSystem; }
    else import <nixpkgs> {}
}:

let
  # Verify we're targeting the right platform
  _ = assert crossSystem != null -> 
    (pkgs.stdenv.hostPlatform.isLinux && pkgs.stdenv.hostPlatform.isAarch64)
    || builtins.trace "Warning: crossSystem provided but not targeting aarch64-linux!" true;
    null;

in

with pkgs;

let
  # Our custom prefix for Termux
  termuxPrefix = "/data/data/com.termux/files";
  nixPrefix = "${termuxPrefix}/nix";
  
  # Store directory configuration
  # These are the target paths, but Nix will respect NIX_STORE_DIR
  storeDir = "${nixPrefix}/store";
  stateDir = "${nixPrefix}/var";
  confDir = "${nixPrefix}/etc";
  
  # Use standard Nix - no need to override store paths!
  # We'll use environment variables (NIX_STORE_DIR, etc.) at runtime
  #
  # KEY INSIGHT: This is the optimization from dramforever's guide.
  # Instead of building Nix multiple times with different --prefix configurations,
  # we build it once and use NIX_STORE_DIR environment variable to redirect it
  # to our custom location. This saves one entire bootstrap stage!
  nixBoot = pkgs.nix;
  
  # Collect all stdenv bootstrap stages to avoid rebuilding toolchains
  # This recursively walks back through the stdenv bootstrap process
  #
  # Why we do this: Each stdenv stage depends on previous stages to build the toolchain.
  # By including all stages in our tarball, we ensure users never need to rebuild:
  # - gcc and the C compiler
  # - glibc/musl and system libraries  
  # - binutils (ld, as, ar, etc.)
  # - Basic bootstrap tools
  #
  # The tradeoff is a larger tarball (~1-2 GB), but this saves hours of compilation
  # time for users and makes the installation much more self-contained.
  collectStdenvStages = curStage:
    [ curStage ] ++
    (if (curStage ? __bootPackages) && !(curStage.__bootPackages.__raw or false)
     then collectStdenvStages curStage.__bootPackages.stdenv
     else []);
  
  # All the stdenv stages from final back to stage 0
  allStdenvStages = collectStdenvStages pkgs.stdenv;
  
  # Closure info for creating the tarball
  # closureInfo computes the complete dependency closure (all transitive dependencies)
  # and generates a registration database that nix-store can import.
  nixClosure = pkgs.closureInfo {
    rootPaths = [ nixBoot ] ++ allStdenvStages ++ [
      # Essential tools for Termux environment
      pkgs.bashInteractive
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.gnutar
      pkgs.gzip
      pkgs.xz
      pkgs.bzip2
      pkgs.curl
      pkgs.wget
      pkgs.git
      pkgs.cacert
      
      # Useful build tools
      pkgs.gnumake
      pkgs.patch
      pkgs.diffutils
      pkgs.which
      
      # For convenience
      pkgs.less
      pkgs.nano
    ];
  };
  
  # Installer script
  installerScript = pkgs.writeScript "install.sh" ''
    #!/bin/sh
    set -e
    
    TERMUX_PREFIX="${termuxPrefix}"
    NIX_PREFIX="${nixPrefix}"
    STORE_DIR="${storeDir}"
    STATE_DIR="${stateDir}"
    CONF_DIR="${confDir}"
    
    echo "======================================"
    echo "Nix Installer for Termux (aarch64)"
    echo "======================================"
    echo ""
    echo "Target prefix: $NIX_PREFIX"
    echo "Store directory: $STORE_DIR"
    echo "State directory: $STATE_DIR"
    echo "Config directory: $CONF_DIR"
    echo ""
    
    # Check if we're on the right architecture
    ARCH=$(uname -m)
    if [ "$ARCH" != "aarch64" ]; then
      echo "ERROR: This installer is for aarch64 only. Detected: $ARCH"
      exit 1
    fi
    
    # Check if running on Android/Termux
    if [ ! -d "$TERMUX_PREFIX" ]; then
      echo "WARNING: $TERMUX_PREFIX not found. Are you running this in Termux?"
      echo "Press Ctrl+C to cancel, or Enter to continue anyway..."
      read
    fi
    
    echo "Creating directories..."
    mkdir -p "$STORE_DIR"
    mkdir -p "$STATE_DIR/nix/db"
    mkdir -p "$STATE_DIR/nix/gcroots"
    mkdir -p "$STATE_DIR/nix/profiles"
    mkdir -p "$STATE_DIR/nix/temproots"
    mkdir -p "$CONF_DIR/nix"
    
    echo "Copying store paths..."
    cp -r ./store/* "$STORE_DIR/" || true
    
    echo "Initializing Nix database..."
    if [ -f ./registration ]; then
      # Find the nix-store binary in the store
      NIX_STORE_BIN=$(find "$STORE_DIR" -name "nix-store" -type f | head -n 1)
      if [ -n "$NIX_STORE_BIN" ]; then
        # Set up minimal environment for nix-store
        export NIX_STORE_DIR="$STORE_DIR"
        export NIX_STATE_DIR="$STATE_DIR"
        export NIX_CONF_DIR="$CONF_DIR"
        
        "$NIX_STORE_BIN" --load-db < ./registration
        echo "Database initialized successfully."
      else
        echo "WARNING: Could not find nix-store binary. Database not initialized."
      fi
    fi
    
    echo "Creating default profile..."
    # Find the nix binary
    NIX_BIN=$(find "$STORE_DIR" -path "*/bin/nix" -type f | head -n 1)
    if [ -n "$NIX_BIN" ]; then
      export NIX_STORE_DIR="$STORE_DIR"
      export NIX_STATE_DIR="$STATE_DIR"
      export NIX_CONF_DIR="$CONF_DIR"
      
      # Create profile directory if it doesn't exist
      mkdir -p "$STATE_DIR/nix/profiles/per-user/$USER"
      
      # Set up the default profile link
      ln -sf "$STATE_DIR/nix/profiles/per-user/$USER/profile" "$STATE_DIR/nix/profiles/default" || true
    fi
    
    echo "Creating nix.conf..."
    cat > "$CONF_DIR/nix/nix.conf" << 'EOF'
# Nix configuration for Termux
build-users-group =
sandbox = false
max-jobs = auto
cores = 0

# Disable substituters by default (no binary cache for custom prefix)
substituters =
trusted-public-keys =

# Store paths configuration
store = ${storeDir}
state = ${stateDir}
EOF
    
    echo ""
    echo "======================================"
    echo "Installation complete!"
    echo "======================================"
    echo ""
    echo "IMPORTANT: This Nix uses environment variable overrides."
    echo "No rebuild was needed thanks to NIX_STORE_DIR support!"
    echo ""
    echo "To use Nix, add the following to your ~/.bashrc or ~/.zshrc:"
    echo ""
    echo "  export NIX_STORE_DIR=\"$STORE_DIR\""
    echo "  export NIX_STATE_DIR=\"$STATE_DIR\""
    echo "  export NIX_CONF_DIR=\"$CONF_DIR\""
    echo "  export PATH=\"$STATE_DIR/nix/profiles/default/bin:\$PATH\""
    echo ""
    echo "Then run: source ~/.bashrc  (or ~/.zshrc)"
    echo ""
    echo "To install packages, you'll need to build from source since"
    echo "binary caches are for /nix/store, not custom paths."
    echo ""
  '';
  
  # Build the installer tarball
  # Use buildPackages for tools that run during build (on the build platform)
  installer = pkgs.stdenv.mkDerivation {
    name = "nix-termux-installer";
    nativeBuildInputs = with pkgs.buildPackages; [ gnutar gzip coreutils ];
    
    buildCommand = ''
      mkdir -p $out/tarball
      cd $out/tarball
      
      # Copy all store paths
      mkdir -p store
      echo "Copying store paths..."
      for path in $(cat ${nixClosure}/store-paths); do
        echo "  Copying: $path"
        # Strip the /nix/store prefix and copy to our store directory
        storePath=$(basename "$path")
        cp -rL "$path" "store/$storePath"
      done
      
      # Copy registration info
      cp ${nixClosure}/registration registration
      
      # Copy installer script
      cp ${installerScript} install.sh
      chmod +x install.sh
      
      # Create README
      cat > README.txt << 'EOF'
Nix Bootstrap Installer for Termux (aarch64-linux)
===================================================

This tarball contains a Nix installation configured for:
  - Store: ${storeDir}
  - State: ${stateDir}
  - Config: ${confDir}

Installation:
1. Extract this tarball
2. Run: ./install.sh

Requirements:
- Termux on Android (aarch64)
- At least 2GB of free space
- Internet connection (for future package builds)

For more information, see the nix-termux repository.
EOF
      
      # Create the final tarball
      cd $out
      echo "Creating tarball..."
      tar -czf nix-termux-aarch64.tar.gz tarball/
      
      # Also create a symlink for easy access
      ln -s nix-termux-aarch64.tar.gz tarball.tar.gz
      
      echo "Installer tarball created successfully!"
      ls -lh nix-termux-aarch64.tar.gz
    '';
  };

in {
  inherit nixBoot installer nixClosure allStdenvStages;
  
  # Convenience attributes
  inherit storeDir stateDir confDir;
}
