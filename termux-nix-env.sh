#!/data/data/com.termux/files/usr/bin/bash
# Termux environment setup for Nix
# Add this to your ~/.bashrc or ~/.zshrc in Termux

# Nix paths
export NIX_PREFIX="/data/data/com.termux/files/nix"
export NIX_STORE_DIR="$NIX_PREFIX/store"
export NIX_STATE_DIR="$NIX_PREFIX/var"
export NIX_CONF_DIR="$NIX_PREFIX/etc"

# SSL certificates
export NIX_SSL_CERT_FILE="$NIX_STORE_DIR/$(ls $NIX_STORE_DIR | grep cacert | head -n1)/etc/ssl/certs/ca-bundle.crt"

# Add Nix profile to PATH
export PATH="$NIX_STATE_DIR/nix/profiles/default/bin:$PATH"

# Optional: Set up manpath
export MANPATH="$NIX_STATE_DIR/nix/profiles/default/share/man:$MANPATH"

# Nix convenience aliases
alias nix-update-profile='nix-env -u "*"'
alias nix-gc='nix-collect-garbage'
alias nix-gc-old='nix-collect-garbage --delete-old'
alias nix-list='nix-env -q'
alias nix-search='nix-env -qaP'

# Display Nix info on first load
if [ -z "$NIX_TERMUX_SETUP_DONE" ]; then
    export NIX_TERMUX_SETUP_DONE=1
    echo "Nix environment loaded"
    echo "Store: $NIX_STORE_DIR"
    
    # Check if nix is actually available
    if command -v nix-env &> /dev/null; then
        echo "Nix version: $(nix-env --version)"
    else
        echo "WARNING: Nix binaries not found in PATH"
        echo "Have you run the installer?"
    fi
fi
