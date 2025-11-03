# Bootstrap Nix for Termux with custom prefix
# Based on: https://dram.page/p/bootstrapping-nix/
# Created with assistance from Claude Sonnet 4.5
#
# This builds a Nix installation for /data/data/com.termux/files/nix
# Targeting: aarch64-linux only
#
# Note: We use NIX_STORE_DIR environment variable override, which saves
# one stage of the bootstrap process. The Nix built here respects the
# NIX_STORE_DIR variable, so we don't need to rebuild it multiple times.

{ pkgs ? import <nixpkgs> { system = "aarch64-linux"; }
}:

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
  nixBoot = nix;
  
  # Collect all stdenv bootstrap stages to avoid rebuilding toolchains
  # This recursively walks back through the stdenv bootstrap process
  stdenvStages = curStage:
    [ curStage ] ++
    (if ! (curStage.__bootPackages.__raw or false)
     then stdenvStages curStage.__bootPackages.stdenv
     else []);
  
  # All the stdenv stages from final back to stage 0
  allStdenvStages = stdenvStages stdenv;
  
  # Closure info for creating the tarball
  nixClosure = closureInfo {
    rootPaths = [ nixBoot ] ++ allStdenvStages ++ [
      # Essential tools for Termux environment
      bashInteractive
      coreutils
      findutils
      gnugrep
      gnused
      gawk
      gnutar
      gzip
      xz
      bzip2
      curl
      wget
      git
      cacert
      
      # Useful build tools
      gnumake
      patch
      diffutils
      which
      
      # For convenience
      less
      nano
    ];
  };
  
  # Installer script
  installerScript = writeScript "install.sh" ''
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
  installer = stdenv.mkDerivation {
    name = "nix-termux-installer";
    buildInputs = [ nixBoot ];
    
    buildCommand = ''
      mkdir -p $out/tarball
      cd $out/tarball
      
      # Copy all store paths
      mkdir -p store
      echo "Copying store paths..."
      for path in $(cat ${nixClosure}/store-paths); do
        echo "  $path"
        cp -r "$path" store/
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
      tar -czf nix-termux-aarch64.tar.gz tarball/
      
      echo "Installer tarball created: $out/nix-termux-aarch64.tar.gz"
    '';
  };

in {
  inherit nixBoot installer nixClosure allStdenvStages;
  
  # Convenience attributes
  inherit storeDir stateDir confDir;
}
