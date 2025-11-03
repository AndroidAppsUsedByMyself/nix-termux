# Nix Bootstrap for Termux (aarch64-linux)

Bootstrap Nix package manager for Termux on Android with a custom prefix at `/data/data/com.termux/files/nix`.

This project enables running Nix on Android devices through Termux without requiring root access or modifying `/nix`. It's specifically designed for **aarch64 (ARM64) devices only**.

> **Note**: This project follows the guide at https://dram.page/p/bootstrapping-nix/ and was created with assistance from Claude Sonnet 4.5.

## Background

Based on the excellent blog post ["Bootstrapping Nix"](https://dram.page/p/bootstrapping-nix/) by dramforever, this project adapts the bootstrap process for Termux environments.

**Important**: We use the `NIX_STORE` variable override approach, which means we can skip one stage of the bootstrap! As dramforever noted: "the NIX_STORE variable can override the pre-configured settings within Nix. In other words, Nix does not require rebuilding for a 'cross-compiling' scenario like this. We can save one stage of Nix."

### Why Custom Prefix?

The standard Nix installation uses `/nix/store`, which requires root access to create. By using a custom prefix at `/data/data/com.termux/files/nix`, we can:
- Install Nix without root access
- Run entirely within Termux's accessible filesystem
- Maintain full Nix functionality including store management and garbage collection

### The Bootstrap Process

This bootstrap uses a simplified two-stage approach (saving one stage thanks to NIX_STORE override):

1. **Stage 1**: Use an existing Nix installation to build a custom Nix configured for `/data/data/com.termux/files/nix/store` - this Nix can be used directly with NIX_STORE environment variable override
2. **Package**: Bundle the Nix with all stdenv bootstrap stages and essential tools into a tarball
3. **Deploy**: Extract and install on Termux device, using environment variables to point to the custom store location

The original three-stage approach is not needed because Nix respects the `NIX_STORE_DIR` environment variable, allowing a single build to work with any store location.

## Requirements

### For Building (Development Machine)

- A working Nix installation (NixOS, or Nix on Linux/macOS)
- Internet connection
- Adequate disk space (~10-20 GB for build artifacts)
- Time and patience (multi-hour build process)

### For Running (Termux on Android)

- Android device with **aarch64 (ARM64) architecture**
- Termux app installed
- At least 2-3 GB free storage
- Internet connection (for future package builds)

## Building the Bootstrap

On a machine with Nix installed:

```bash
# Clone this repository
git clone https://github.com/your-username/nix-termux.git
cd nix-termux

# Make the build script executable
chmod +x build.sh

# Start the build process
./build.sh
```

This will:
- Build a custom Nix configured for Termux paths
- Include all stdenv bootstrap stages (to avoid toolchain rebuilds later)
- Bundle essential utilities (bash, coreutils, git, etc.)
- Create an installer tarball

**Note**: The build can take several hours depending on your hardware, as it compiles:
- Nix itself
- GCC and the complete toolchain
- Glibc and system libraries
- Essential utilities

The output will be: `result/nix-termux-aarch64.tar.gz`

## Installation on Termux

1. **Transfer the tarball to your Android device**:
   ```bash
   # Via USB, cloud storage, or directly with termux
   # Example using curl if hosted somewhere:
   curl -LO https://your-server.com/nix-termux-aarch64.tar.gz
   ```

2. **Extract the tarball**:
   ```bash
   tar -xzf nix-termux-aarch64.tar.gz
   cd tarball
   ```

3. **Run the installer**:
   ```bash
   ./install.sh
   ```

4. **Set up your environment**:
   
   Add to your `~/.bashrc` or `~/.zshrc`:
   ```bash
   # Source Nix environment
   source ~/path/to/termux-nix-env.sh
   ```

   Or manually add:
   ```bash
   export NIX_PREFIX="/data/data/com.termux/files/nix"
   export NIX_STORE_DIR="$NIX_PREFIX/store"
   export NIX_STATE_DIR="$NIX_PREFIX/var"
   export NIX_CONF_DIR="$NIX_PREFIX/etc"
   export PATH="$NIX_STATE_DIR/nix/profiles/default/bin:$PATH"
   ```

5. **Reload your shell**:
   ```bash
   source ~/.bashrc  # or ~/.zshrc
   ```

6. **Verify installation**:
   ```bash
   nix-env --version
   nix-store --verify --check-contents
   ```

## Usage

### Installing Packages

Since we're using a custom store path, the official binary cache won't work. All packages must be built from source:

```bash
# Install a package (will build from source)
nix-env -iA nixpkgs.hello

# Search for packages
nix-env -qaP | grep python

# Update all packages
nix-env -u '*'
```

### Using with nixpkgs

Clone nixpkgs for local package builds:

```bash
cd ~
git clone https://github.com/NixOS/nixpkgs.git --depth 1
cd nixpkgs

# Install from local nixpkgs
nix-env -f . -iA hello
```

### Garbage Collection

Free up space by removing unused packages:

```bash
# List old generations
nix-env --list-generations

# Delete old generations
nix-env --delete-generations old

# Run garbage collector
nix-collect-garbage

# Aggressive cleanup (remove everything not currently in use)
nix-collect-garbage -d
```

### Configuration

Edit `/data/data/com.termux/files/nix/etc/nix/nix.conf` to customize:
- Build settings (max-jobs, cores)
- Storage optimizations
- Custom binary caches (if you set up your own)

## Limitations

1. **No Binary Cache**: The official Nix binary cache serves packages for `/nix/store`. With our custom prefix, we must build everything from source.

2. **Build Time**: First-time installation of packages will be slow as they compile from source.

3. **Architecture**: Only aarch64-linux is supported. No x86_64 or armv7l.

4. **Storage**: Nix store can grow large. Monitor storage and use garbage collection regularly.

5. **Link Rot**: Some packages may fail to build if source URLs are dead. Use `tarballs.nixos.org` mirror when possible.

## Troubleshooting

### "nix-env: command not found"

Ensure you've sourced the environment setup:
```bash
source ~/termux-nix-env.sh
```

### Database Errors

Re-initialize the database:
```bash
nix-store --init
nix-store --load-db < /data/data/com.termux/files/nix/var/nix/db/db.sqlite
```

### Build Failures

Check logs:
```bash
# View build logs
nix-store --read-log /nix/store/...-package-name
```

### Out of Space

Run garbage collection:
```bash
nix-collect-garbage -d
```

## Advanced: Creating Your Own Binary Cache

To speed up future installations, you can set up a binary cache:

1. Build packages on a build server
2. Sign and push to an S3 bucket or HTTP server
3. Configure `substituters` in `nix.conf`

See: https://nixos.org/manual/nix/stable/package-management/binary-cache-substituter.html

## Project Structure

```
nix-termux/
├── bootstrap.nix           # Main Nix expression for bootstrap
├── build.sh                # Build automation script
├── nix.conf.template       # Template Nix configuration
├── termux-nix-env.sh      # Environment setup script
└── README.md              # This file
```

## Contributing

Contributions welcome! Areas for improvement:
- Cross-compilation support for building on x86_64
- Automated testing in Termux containers
- Pre-built binary cache hosting
- Additional architecture support (if feasible)

## License

This project is provided as-is for educational and practical purposes. The Nix package manager itself is licensed under the LGPL 2.1.

## References

- [Bootstrapping Nix](https://dramforever.com/blog/bootstrap-nix.html) by dramforever
- [Nix Manual](https://nixos.org/manual/nix/stable/)
- [Nixpkgs Manual](https://nixos.org/manual/nixpkgs/stable/)
- [Termux Wiki](https://wiki.termux.com/)

## Acknowledgments

- **dramforever** for the original bootstrap approach and detailed blog post
- The Nix community for creating an amazing package manager
- Termux developers for bringing Linux environment to Android
