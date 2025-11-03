# Nix for Termux (aarch64-linux)

Run the Nix package manager on Android through Termux without root access. Uses a custom prefix at `/data/data/com.termux/files/nix` instead of `/nix`.

**aarch64 (ARM64) devices only.**

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/mio-19/nix-termux/main/install-nix-termux.sh | bash
```

**Requirements:** aarch64 Android device, Termux installed, 2-3 GB free space.

After installation: `source ~/.bashrc` (or restart Termux)

---

> **Note**: This project follows the guides at:
> - [Bootstrapping Nix](https://dram.page/p/bootstrapping-nix/) by dramforever
> - [Cross compilation tutorial](https://nix.dev/tutorials/cross-compilation.html) from nix.dev (official tutorial)
> - [Cross-compilation infrastructure](https://nixos.org/manual/nixpkgs/stable/#chap-cross) from the Nixpkgs manual (official reference)
> - [Cross Compiling](https://nixos.wiki/wiki/Cross_Compiling) from NixOS Wiki (community examples)
> - [Beginner's guide to cross compilation](https://matthewbauer.us/blog/beginners-guide-to-cross.html) by Matthew Bauer (2018 - historical context)
>
> Created with assistance from Claude Sonnet 4.5.

## Background

This project combines two powerful Nix techniques:

1. **Custom Store Prefix**: Based on dramforever's ["Bootstrapping Nix"](https://dram.page/p/bootstrapping-nix/), we build Nix to work with `/data/data/com.termux/files/nix` instead of `/nix`

2. **Cross Compilation**: Following the [official Nix cross-compilation guide](https://nix.dev/tutorials/cross-compilation.html), we build for `aarch64-unknown-linux-gnu` from any platform

**Important**: We configure Nix at build time with custom `--with-store-dir`, `--localstatedir`, and `--sysconfdir` options to match Termux's prefix. This ensures all paths (including the critical ELF interpreter path) point to `/data/data/com.termux/files/nix/store` instead of `/nix/store`. This is essential because the ELF interpreter path is hardcoded at build time and cannot be changed with environment variables.

### Why Custom Prefix?

The standard Nix installation uses `/nix/store`, which requires root access to create. By using a custom prefix at `/data/data/com.termux/files/nix`, we can:
- Install Nix without root access
- Run entirely within Termux's accessible filesystem
- Maintain full Nix functionality including store management and garbage collection

### The Bootstrap Process

This bootstrap uses a simplified two-stage approach (saving one stage thanks to NIX_STORE override):

1. **Cross-compile**: Use an existing Nix installation (on any platform, e.g., x86_64) to cross-compile Nix and dependencies for `aarch64-unknown-linux-gnu` using the `crossSystem` parameter
2. **Package**: Bundle the cross-compiled Nix with all stdenv bootstrap stages and essential tools into a tarball
3. **Deploy**: Extract and install on Termux device, using environment variables (NIX_STORE_DIR, etc.) to point to the custom store location

**Key approach**:
- **Cross-compilation**: Following [nix.dev's guide](https://nix.dev/tutorials/cross-compilation.html), we can build for ARM64 from any platform
- **Custom prefix configuration**: We configure Nix at build time with the correct store paths so all binaries (including their ELF interpreter paths) point to `/data/data/com.termux/files/nix/store`

### How We Follow the nix.dev Cross-Compilation Guide

The nix.dev guide teaches us about **platforms** in cross-compilation:

- **Build platform**: Where we compile (e.g., x86_64-linux)
- **Host platform**: Where the compiled binary runs (aarch64-unknown-linux-gnu for Termux)
- **Target platform**: For compilers only (we assume host = target)

We follow the guide's recommended approach exactly:

```nix
# In bootstrap.nix - as shown in the guide
{ crossSystem ? null
, pkgs ? 
    if crossSystem != null
    then import <nixpkgs> { inherit crossSystem; }
    else import <nixpkgs> {}
}:
```

Then we build using:

```bash
nix-build bootstrap.nix -A installer \
  --arg crossSystem '{ config = "aarch64-unknown-linux-gnu"; }'
```

The platform config string `aarch64-unknown-linux-gnu` follows the standard format `<cpu>-<vendor>-<os>-<abi>` where:
- `aarch64` = ARM 64-bit CPU
- `unknown` = vendor (often unknown or pc)
- `linux` = operating system
- `gnu` = GNU ABI (glibc-based)

This is identical to what you'd get by running `config.guess` on an aarch64 Android/Linux system, and matches the `pkgsCross.aarch64-multiplatform` pre-defined platform in nixpkgs.

**Historical note**: Cross-compilation support in Nixpkgs has evolved significantly. Matthew Bauer's 2018 guide introduced many developers to the `pkgsCross` attribute and established patterns for build vs. runtime dependencies. Since then (particularly since 18.09), the framework has matured with more elegant handling and better integration. Our implementation uses the current best practices from the official documentation.

### Understanding Build, Host, and Target Platforms

Following the [Nixpkgs cross-compilation infrastructure](https://nixos.org/manual/nixpkgs/stable/#chap-cross), we distinguish between three platform types:

- **Build platform** (`buildPlatform`): Where the compilation happens (e.g., your x86_64-linux laptop)
- **Host platform** (`hostPlatform`): Where the compiled program will run (aarch64-linux for Termux)
- **Target platform** (`targetPlatform`): Only relevant for compilers themselves; we assume host = target

In our case:
- **Build**: x86_64-linux (or whatever you're building on)
- **Host**: aarch64-unknown-linux-gnu (Termux on Android ARM64)
- **Target**: aarch64-unknown-linux-gnu (same as host, since we're not building a cross-compiler)

The Nixpkgs manual explains that dependencies are categorized by which platforms they involve:

- **`nativeBuildInputs`** (build-time dependencies): Tools that run during build on the **build platform** (e.g., compilers, pkg-config, makeWrapper)
- **`buildInputs`** (runtime dependencies): Libraries that the program links against on the **host platform** (e.g., zlib, openssl)

This distinction, as Matthew Bauer explained in his 2018 guide, is crucial: "build-time dependencies should be put in nativeBuildInputs. Runtime dependencies should be put in buildInputs." While this had no effect on native compilation initially, it's now fundamental for correct cross-compilation.

Our bootstrap process correctly handles these distinctions automatically when we set `crossSystem`, ensuring that build tools come from the build platform while target libraries come from the host platform.

> **Note on documentation sources**: We primarily follow the official Nixpkgs manual and nix.dev tutorial, as they represent the current authoritative guidance. Historical resources (like Bauer's 2018 guide) provide valuable context but may use outdated syntax. The NixOS Wiki provides additional community examples but may contain outdated information (it notes itself as "a stub"). When in doubt, we defer to the official documentation.

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

### Option 1: One-Line Install (Recommended)

The easiest way to install is using the automated installer script:

```bash
curl -fsSL https://raw.githubusercontent.com/mio-19/nix-termux/main/install-nix-termux.sh | bash
```

Or with `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/mio-19/nix-termux/main/install-nix-termux.sh | bash
```

The script will handle everything automatically, including downloading the latest release, verifying your system, and configuring your environment.

### Option 2: Manual Installation

If you prefer to install manually or want more control:

1. **Download the latest release tarball**:
   
   Visit the [releases page](https://github.com/mio-19/nix-termux/releases/latest) and download the `nix-termux-aarch64-*.tar.gz` file, or use:
   
   ```bash
   # Example (replace with actual latest release URL from GitHub)
   curl -LO https://github.com/mio-19/nix-termux/releases/download/dev-20251103-034509/nix-termux-aarch64-dev-20251103-034509.tar.gz
   ```

2. **Extract the tarball**:
   ```bash
   tar -xzf nix-termux-aarch64-*.tar.gz
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

## Important Notes and Design Decisions

### Why Cross-Compilation?

We use cross-compilation from x86_64 to aarch64 because:
1. **Faster builds**: x86_64 development machines are typically more powerful than Android devices
2. **Reproducibility**: Building on a controlled environment ensures consistent results
3. **Convenience**: No need to compile for hours on a mobile device with limited battery

### Why the Custom Prefix?

Android/Termux cannot access `/nix/store` without root. The custom prefix at `/data/data/com.termux/files/nix` allows:
- Installation without root privileges
- Full Nix functionality within Termux's sandbox
- Standard Nix operations (store management, garbage collection, etc.)

### Custom Prefix Configuration

We configure Nix at build time with custom paths using `overrideAttrs`:

```nix
nixBoot = pkgs.nix.overrideAttrs (old: {
  configureFlags = (old.configureFlags or []) ++ [
    "--with-store-dir=/data/data/com.termux/files/nix/store"
    "--localstatedir=/data/data/com.termux/files/nix/var"
    "--sysconfdir=/data/data/com.termux/files/nix/etc"
  ];
});
```

This is **critical** because:
- **ELF interpreter path**: The dynamic linker path is hardcoded in ELF binaries at build time (e.g., `/data/data/com.termux/files/nix/store/.../lib/ld-linux-aarch64.so.1`)
- **Cannot be changed at runtime**: Unlike some Nix paths that can be overridden with environment variables, the interpreter path is baked into the binary
- **Must match the actual location**: If the interpreter path points to `/nix/store/...` but files are in `/data/data/com.termux/files/nix/store/...`, the binary won't run

While `NIX_STORE_DIR` environment variable can override some Nix behavior at runtime, it cannot change the hardcoded ELF interpreter path, which is why proper build-time configuration is essential.

### Dependency Categorization

Following the official Nixpkgs manual and Matthew Bauer's guidance:

- **`nativeBuildInputs`**: Programs executed during build (on build platform)
  - Examples: gcc, pkg-config, makeWrapper, autoconf
  - These must be executable on your x86_64 machine

- **`buildInputs`**: Libraries linked into the final binary (on host platform)
  - Examples: zlib, openssl, ncurses
  - These must be compiled for aarch64 (the target)

Mixing these up causes "Exec format error" (trying to run aarch64 binary on x86_64) or linking errors (linking x86_64 library into aarch64 binary).

### Why We Include All stdenv Bootstrap Stages

The `collectStdenvStages` function recursively collects all stages of the standard environment bootstrap. This ensures:
- **No toolchain rebuilds**: Users won't need to rebuild GCC, glibc, binutils, etc.
- **Faster first installs**: Common build tools are pre-installed
- **Better offline support**: More self-contained installation

The tradeoff is a larger tarball (~1-2 GB), but this is worth it for the time saved.

### Platform Triple Format

We use `aarch64-unknown-linux-gnu` following the LLVM target triple format:
- `aarch64`: 64-bit ARM CPU architecture
- `unknown`: Vendor field (often "unknown" or "pc" - not critical)
- `linux`: Operating system kernel
- `gnu`: ABI/C library (glibc-based GNU toolchain)

This is more precise than Nix's simpler `aarch64-linux` system string and is recognized by all modern toolchains (GCC, Clang, Rust, etc.).

### Why Not Use Binary Cache?

The official Nix binary cache (cache.nixos.org) serves packages for `/nix/store`. Our packages are in `/data/data/com.termux/files/nix/store`. The paths are **embedded in the binaries** as part of Nix's functional dependency tracking, so we cannot use pre-built binaries.

Options for faster builds:
1. Set up your own binary cache for the custom prefix
2. Use the "lazy cross-compiling" technique from the NixOS Wiki (fetch some dependencies from official aarch64 cache)
3. Build on a powerful server and transfer the store paths

### Documentation Evolution

Cross-compilation in Nixpkgs has evolved significantly:
- **2018 (18.09)**: Basic `pkgsCross` support established (Matthew Bauer's era)
- **2023-2024**: Refined with better splicing, cleaner API, more robust handling
- **Current**: Official tutorial (nix.dev) and comprehensive manual (Nixpkgs) are authoritative

When reading older resources (including some of our referenced guides), be aware that:
- Syntax may have changed (e.g., `system` vs `crossSystem` parameter handling)
- Some workarounds are no longer needed
- Best practices have evolved

We follow current official documentation and note when historical resources differ.

## Limitations

1. **No Binary Cache**: The official Nix binary cache serves packages for `/nix/store`. With our custom prefix, we must build everything from source.

2. **Build Time**: First-time installation of packages will be slow as they compile from source.

3. **Architecture**: Only aarch64-linux is supported. No x86_64 or armv7l.

4. **Storage**: Nix store can grow large. Monitor storage and use garbage collection regularly.

5. **Link Rot**: Some packages may fail to build if source URLs are dead. Use `tarballs.nixos.org` mirror when possible.

6. **Android Limitations**: Some packages may not work due to Android's non-standard environment (different filesystem layout, no systemd, limited /proc, etc.)

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

### High Priority
- **Binary cache setup**: Instructions or automation for setting up a custom binary cache
- **Automated testing**: CI/CD pipeline to test builds and installation
- **Installation improvements**: Better error handling, progress indicators, recovery from partial installs

### Medium Priority
- **Package compatibility matrix**: Document which common packages work/don't work on Termux
- **Lazy cross-compilation**: Implement the wiki's technique to fetch some dependencies from official aarch64 cache
- **Size optimization**: Reduce tarball size by identifying truly essential vs. nice-to-have packages

### Low Priority / Research Needed
- **armv7l support**: Older 32-bit ARM devices (significant work, limited benefit)
- **x86_64 Android**: Android emulators and some tablets (niche use case)
- **Dynamic vs. static linking**: Trade-offs for Termux environment

### Documentation Improvements
- Step-by-step troubleshooting for common build failures
- Video walkthrough of installation process
- Comparison with other Nix-on-Android approaches (NixOnDroid, etc.)

## License

This project is provided as-is for educational and practical purposes. The Nix package manager itself is licensed under the LGPL 2.1.

## References

### Cross-Compilation Guides

- [Bootstrapping Nix](https://dram.page/p/bootstrapping-nix/) by dramforever - Core bootstrap approach and NIX_STORE_DIR optimization
- [Cross compilation tutorial](https://nix.dev/tutorials/cross-compilation.html) - Official nix.dev tutorial with practical examples
- [Cross-compilation infrastructure](https://nixos.org/manual/nixpkgs/stable/#chap-cross) - Official Nixpkgs manual: deep dive into cross-compilation internals
- [Cross Compiling](https://nixos.wiki/wiki/Cross_Compiling) - Community wiki with practical examples and tips
- [Beginner's guide to cross compilation](https://matthewbauer.us/blog/beginners-guide-to-cross.html) by Matthew Bauer (2018) - Historical introduction to Nixpkgs cross-compilation; note that syntax has evolved since 18.09

### Official Documentation

- [Nix Manual](https://nixos.org/manual/nix/stable/) - Core Nix functionality
- [Nixpkgs Manual](https://nixos.org/manual/nixpkgs/stable/) - Package collection and stdenv
- [NixOS Manual](https://nixos.org/manual/nixos/stable/) - NixOS-specific features

### Platform Resources

- [Termux Wiki](https://wiki.termux.com/) - Android terminal emulator documentation
- [GNU Autoconf Platform Types](https://www.gnu.org/software/autoconf/manual/autoconf-2.69/html_node/Specifying-Target-Triplets.html) - Platform configuration strings

## Related Projects and Alternatives

If you're interested in Nix on Android, you might also want to check out:

- **[Nix-on-Droid](https://github.com/nix-community/nix-on-droid)**: A more integrated approach that provides a NixOS-like environment on Android. Uses a similar custom prefix approach but with additional Android integration.
  
- **[Standard Termux packages](https://github.com/termux/termux-packages)**: Termux's native package manager. Simpler to use but less flexible than Nix. Good for most users who don't need Nix's reproducibility guarantees.

- **[proot-distro](https://github.com/termux/proot-distro)**: Run full Linux distributions in Termux using proot (no root required). Can run NixOS inside, but with performance overhead.

**Why choose this project?**
- You want vanilla Nix (not a wrapper or integration layer)
- You need reproducible builds and declarative package management
- You want to learn how Nix cross-compilation and bootstrapping works
- You're comfortable with building from source and don't need extensive Android integration

## Acknowledgments

- **dramforever** for the original bootstrap approach and detailed blog post
- **Matthew Bauer** for pioneering work on Nixpkgs cross-compilation and documentation
- The Nix community for creating an amazing package manager and maintaining excellent documentation
- Termux developers for bringing Linux environment to Android
- All contributors to Nixpkgs cross-compilation infrastructure
