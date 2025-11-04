# Bootstrap Nix for Termux with custom prefix
# 
# References:
# - https://dram.page/p/bootstrapping-nix/ (bootstrap approach)
#
# Created with assistance from Claude Sonnet 4.5
#
# This builds a Nix installation for /data/data/com.termux/files/nix
# Targeting: multiple architectures for Termux
#
# Approach: Build for /nix/store, then use patchelf to rewrite interpreter paths.
# This avoids the complexity of multi-stage bootstrapping while ensuring binaries
# work correctly with the custom store directory.
#
# Usage:
#   nix-build bootstrap.nix -A installer.<arch>

{ pkgs ? import <nixpkgs> {} }:

with pkgs;

let
  # Define supported architectures and their target platforms
  supportedArchs = {
    aarch64 = {
      targetPlatform = "aarch64-unknown-linux-gnu";
      name = "aarch64";
    };
    armv7l = {
      targetPlatform = "armv7l-unknown-linux-gnueabihf";
      name = "armv7l";
    };
    x86_64 = {
      targetPlatform = "x86_64-unknown-linux-gnu";
      name = "x86_64";
    };
    i686 = {
      targetPlatform = "i686-unknown-linux-gnu";
      name = "i686";
    };
  };

  # Function to create installer for specific architecture
  makeInstaller = { targetPlatform, name }: 
  let
    termuxPrefix = "/data/data/com.termux/files";
    nixPrefix = "${termuxPrefix}/nix";
    storeDir = "${nixPrefix}/store";
    stateDir = "${nixPrefix}/var";
    confDir = "${nixPrefix}/etc";
    
    # Build Nix configured for custom store paths
    nixBoot = let
      nixComponents = pkgs.nixVersions.nixComponents_2_31;
      
      nixComponentsWithCustomPaths = nixComponents.overrideAllMesonComponents (finalAttrs: prevAttrs: {
        mesonFlags = (prevAttrs.mesonFlags or []) ++ [
          (lib.mesonOption "libstore:store-dir" storeDir)
          (lib.mesonOption "libstore:localstatedir" stateDir)
          (lib.mesonOption "libstore:sysconfdir" confDir)
        ];
      });
    in
    nixComponentsWithCustomPaths.nix-everything;
    
    # Collect all stdenv bootstrap stages to avoid rebuilding toolchains
    collectStdenvStages = curStage:
      [ curStage ] ++
      (if (curStage ? __bootPackages) && !(curStage.__bootPackages.__raw or false)
       then collectStdenvStages curStage.__bootPackages.stdenv
       else []);
    
    # All the stdenv stages from final back to stage 0
    allStdenvStages = collectStdenvStages pkgs.stdenv;
    
    # Closure info for creating the tarball
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
        
        # For fixing ELF interpreter paths
        pkgs.patchelf
        pkgs.file
        
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
      echo "Nix Installer for Termux (${name})"
      echo "======================================"
      echo ""
      echo "Target prefix: $NIX_PREFIX"
      echo "Store directory: $STORE_DIR"
      echo "State directory: $STATE_DIR"
      echo "Config directory: $CONF_DIR"
      echo ""
      
      # Check if we're on the right architecture
      ARCH=$(uname -m)
      if [ "$ARCH" != "${name}" ]; then
        echo "ERROR: This installer is for ${name} only. Detected: $ARCH"
        exit 1
      fi
      
      # Check if running on Android/Termux
      if [ ! -d "$TERMUX_PREFIX" ]; then
        echo "WARNING: $TERMUX_PREFIX not found. Are you running this in Termux?"
        echo "Press Ctrl+C to cancel, or Enter to continue anyway..."
        read
      fi
      
      echo "Creating directories..."
      
      # If reinstalling, make existing store writable and remove it
      if [ -d "$STORE_DIR" ]; then
        echo "Existing store found. Removing old installation..."
        chmod -R u+w "$STORE_DIR" 2>/dev/null || true
        rm -rf "$STORE_DIR"
      fi
      
      mkdir -p "$STORE_DIR"
      mkdir -p "$STATE_DIR/nix/db"
      mkdir -p "$STATE_DIR/nix/gcroots"
      mkdir -p "$STATE_DIR/nix/profiles"
      mkdir -p "$STATE_DIR/nix/temproots"
      mkdir -p "$CONF_DIR/nix"
      
      echo "Copying store paths..."
      echo "(ELF interpreter paths have been pre-patched during build)"
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
    installer = pkgs.stdenv.mkDerivation {
      name = "nix-termux-installer-${name}";
      nativeBuildInputs = with pkgs.buildPackages; [ 
        gnutar 
        gzip 
        coreutils 
        patchelf 
        file 
      ];
      
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
        
        echo ""
        echo "Patching ELF interpreter paths..."
        echo "Rewriting /nix/store -> ${storeDir} in all binaries"
        echo ""
        
        PATCHED_COUNT=0
        TOTAL_ELF=0
        SKIPPED_COUNT=0
        
        # Find all ELF executables and patch them
        while IFS= read -r file; do
          # Check if it's an ELF file with interpreter
          FILE_TYPE=$(file "$file" 2>/dev/null || echo "")
          if echo "$FILE_TYPE" | grep -q "ELF.*interpreter"; then
            TOTAL_ELF=$((TOTAL_ELF + 1))
            
            # Get the interpreter path
            INTERP=$(patchelf --print-interpreter "$file" 2>/dev/null || true)
            
            if [ -n "$INTERP" ] && echo "$INTERP" | grep -q "^/nix/store"; then
              # Calculate the new interpreter path
              NEW_INTERP=$(echo "$INTERP" | sed 's|^/nix/store|${storeDir}|')
              
              # Extract relative path to check if interpreter exists
              INTERP_RELATIVE=$(echo "$INTERP" | sed 's|^/nix/store/||')
              
              if [ -f "store/$INTERP_RELATIVE" ] || [ -L "store/$INTERP_RELATIVE" ]; then
                # Patch the interpreter
                if patchelf --set-interpreter "$NEW_INTERP" "$file" 2>/dev/null; then
                  PATCHED_COUNT=$((PATCHED_COUNT + 1))
                  if [ $PATCHED_COUNT -le 10 ]; then
                    echo "  ✓ $(basename $file): $NEW_INTERP"
                  elif [ $PATCHED_COUNT -eq 11 ]; then
                    echo "  ... (showing first 10, continuing silently)"
                  fi
                fi
              else
                SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                if [ $SKIPPED_COUNT -le 3 ]; then
                  echo "  ⚠ Skipped $(basename $file): interpreter not in closure"
                fi
              fi
            fi
          fi
        done < <(find store -type f -executable)
        
        echo ""
        echo "Results:"
        echo "  Successfully patched: $PATCHED_COUNT"
        if [ $SKIPPED_COUNT -gt 0 ]; then
          echo "  Skipped (interpreter not in closure): $SKIPPED_COUNT"
        fi
        
        if [ $PATCHED_COUNT -eq 0 ] && [ $TOTAL_ELF -gt 0 ]; then
          echo ""
          echo "ERROR: Found ELF files with interpreters but patched none!"
          echo "This likely means the patching logic has a bug."
          exit 1
        fi
        echo ""
        
        # Copy registration info
        cp ${nixClosure}/registration registration
        
        # Copy installer script
        cp ${installerScript} install.sh
        chmod +x install.sh
        
        # Create README
        cat > README.txt << 'EOF'
Nix Bootstrap Installer for Termux (${name})
===================================================

This tarball contains a Nix installation configured for:
  - Store: ${storeDir}
  - State: ${stateDir}
  - Config: ${confDir}

Installation:
1. Extract this tarball
2. Run: ./install.sh

Requirements:
- Termux on Android (${name})
- At least 2GB of free space
- Internet connection (for future package builds)

For more information, see the nix-termux repository.
EOF
        
        # Create the final tarball
        cd $out
        echo "Creating tarball..."
        tar -czf nix-termux-${name}.tar.gz tarball/
        
        # Also create a symlink for easy access
        ln -s nix-termux-${name}.tar.gz tarball.tar.gz
        
        echo "Installer tarball created successfully!"
        ls -lh nix-termux-${name}.tar.gz
      '';
    };
  in {
    inherit installer;
  };

  # Generate installers for all supported architectures
  archInstallers = lib.mapAttrs (name: config: makeInstaller config) supportedArchs;
  
in {
  # Export installers for each architecture
  installer = archInstallers;
  
  # Convenience attributes
  inherit supportedArchs;
}