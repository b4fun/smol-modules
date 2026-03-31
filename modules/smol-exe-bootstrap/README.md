# smol-exe-bootstrap

Bootstrap a complete development environment on exe.dev with Nix and Home Manager.

## Overview

This module provides a single installation script that sets up a fully-featured development environment on exe.dev hosts. It automates the installation of:

- **Nix Package Manager** - A powerful package manager for reproducible builds
- **Home Manager** - Declarative dotfile and package management for Nix
- **Development Tools** - Go, Node.js, and Python with specific versions
- **Git Configuration** - Pre-configured user settings

## Quick Start

```bash
# Clone the repository
git clone https://github.com/b4fun/smol-modules.git
cd smol-modules

# Run the installation script
./modules/smol-exe-bootstrap/install.sh
```

After installation completes, restart your shell or source the Nix profiles:

```bash
source ~/.nix-profile/etc/profile.d/hm-session-vars.sh
source ~/.nix-profile/etc/profile.d/nix.sh
```

## What Gets Installed

### Nix Package Manager
- Multi-user installation with daemon support
- Installed to `/nix`
- Provides reproducible package management

### Home Manager
- Declarative configuration for user packages and dotfiles
- Configuration stored in `~/.config/home-manager/home.nix`
- Enables easy package version management

### Development Tools
The following tools are installed via the `smol-exe` Nix profile:

- **Go 1.23** (closest available to requested 1.25)
- **Node.js 22**
- **Python 3.14**

### Git Configuration
Git is automatically configured with:
- `user.name`: "smol"
- `user.email`: "smol@ss.isbuild.ing"

## Prerequisites

- Linux operating system (tested on Ubuntu on exe.dev)
- `curl` installed (for downloading Nix installer)
- Internet connection
- Sudo access (required for Nix multi-user installation)

## How It Works

The installation script performs the following steps:

1. **Environment Check**: Validates the system is Linux-based
2. **Nix Installation**: 
   - Checks if Nix is already installed (idempotent)
   - Downloads and runs the official Nix installer with daemon support
   - Sources the Nix profile to make it available
3. **Home Manager Installation**:
   - Checks if Home Manager is already installed (idempotent)
   - Adds the home-manager channel
   - Installs Home Manager via nix-shell
4. **Profile Application**:
   - Copies the `smol-exe` Nix profile to `~/.config/home-manager/home.nix`
   - Backs up any existing configuration
   - Activates the configuration with `home-manager switch`
5. **Verification**:
   - Checks that all components are installed correctly
   - Verifies Git configuration
   - Reports any issues or warnings

## Idempotency

The installation script is designed to be **idempotent** - you can safely run it multiple times:

- If Nix is already installed, it skips the Nix installation step
- If Home Manager is already installed, it skips that step
- Existing Home Manager configurations are backed up before being replaced

This makes the script safe to use for both initial installations and updates.

## Customization

To customize the installed packages or configuration:

1. Edit `modules/smol-exe/home.nix` to add or remove packages
2. Run the installation script again to apply changes
3. Or manually edit `~/.config/home-manager/home.nix` and run `home-manager switch`

See the [smol-exe README](../smol-exe/README.md) for details on customizing the Nix profile.

## Troubleshooting

### Tools not found in PATH after installation

**Symptoms**: Commands like `go`, `node`, or `python3` return "command not found" after installation.

**Solution**: You need to restart your shell or source the Nix profiles:

```bash
source ~/.nix-profile/etc/profile.d/hm-session-vars.sh
source ~/.nix-profile/etc/profile.d/nix.sh
```

Or simply open a new terminal session.

### Nix installation requires sudo password

**Symptoms**: The installer prompts for a sudo password during Nix installation.

**Solution**: This is expected. The Nix multi-user installation requires sudo to:
- Create the `/nix` directory
- Set up the Nix daemon
- Configure system-wide services

Enter your sudo password when prompted.

### Home Manager fails to build

**Symptoms**: `home-manager switch` fails with build errors.

**Solution**: 
1. Check that your `home.nix` syntax is correct
2. Ensure all package names are spelled correctly
3. Try updating your channels: `nix-channel --update`
4. Check the Home Manager documentation for your specific error

### Installation fails on non-Linux systems

**Symptoms**: The script warns about non-Linux OS and fails later.

**Solution**: This script is specifically designed for Linux systems (exe.dev uses Linux). While Nix supports macOS, the installation process differs. Use the official Nix installer for macOS directly.

## exe.dev Integration

This module is designed for use on [exe.dev](https://exe.dev/) hosts. To integrate it into your exe.dev customization:

1. Add the installation script to your exe.dev startup scripts
2. Or run it manually after provisioning a new exe.dev instance
3. See [exe.dev customization docs](https://exe.dev/docs/customization) for more details

## References

- [Nix Package Manager](https://nixos.org/)
- [Home Manager](https://github.com/nix-community/home-manager)
- [exe.dev Documentation](https://exe.dev/docs/customization)
- [Nix Installation Guide](https://dev.to/jajera/installing-nix-on-ubuntu-a0o)
- [Alternative Nix Setup](https://gist.github.com/stuart-warren/66bea8c9b23fdac317598ea46b3b97d0)

## License

See the repository's main LICENSE file.
