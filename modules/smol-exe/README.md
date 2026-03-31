# smol-exe

A Nix Home Manager profile for smol development environments.

## Overview

This module provides a declarative Nix configuration for setting up a consistent development environment. It's designed to be used with Home Manager to manage user packages and configurations.

## What's Included

The `home.nix` configuration includes:

### Development Tools

- **Go 1.23** - Go programming language (latest stable version close to 1.25)
- **Node.js 22** - JavaScript runtime with npm
- **Python 3.14** - Python programming language

### Git Configuration

Git is automatically configured with:
- **user.name**: "smol"
- **user.email**: "smol@ss.isbuild.ing"

### Home Manager Settings

- **home.stateVersion**: "23.11" - Ensures compatibility with Home Manager releases
- **programs.home-manager.enable**: true - Allows Home Manager to manage itself

## Usage

### Automatic Installation

This profile is automatically applied when using the [smol-exe-bootstrap](../smol-exe-bootstrap/README.md) module:

```bash
./modules/smol-exe-bootstrap/install.sh
```

### Manual Installation

If you want to use this profile manually:

1. Install Nix and Home Manager:
   ```bash
   # Install Nix
   sh <(curl -L https://nixos.org/nix/install) --daemon
   
   # Add Home Manager channel
   nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
   nix-channel --update
   
   # Install Home Manager
   nix-shell '<home-manager>' -A install
   ```

2. Copy the profile to your Home Manager configuration:
   ```bash
   mkdir -p ~/.config/home-manager
   cp modules/smol-exe/home.nix ~/.config/home-manager/home.nix
   ```

3. Apply the configuration:
   ```bash
   home-manager switch
   ```

## Customization

### Adding Packages

To add more packages to your environment, edit `home.nix` and add them to the `home.packages` list:

```nix
home.packages = with pkgs; [
  go_1_23
  nodejs_22
  python314
  # Add your packages here:
  ripgrep
  jq
  docker
];
```

### Changing Package Versions

To use different versions of the included packages:

1. Check available versions:
   ```bash
   nix search nixpkgs go
   nix search nixpkgs nodejs
   nix search nixpkgs python
   ```

2. Update the package name in `home.nix`:
   ```nix
   home.packages = with pkgs; [
     go_1_22  # Changed from go_1_23
     nodejs_20  # Changed from nodejs_22
     python312  # Changed from python314
   ];
   ```

3. Apply the changes:
   ```bash
   home-manager switch
   ```

### Modifying Git Configuration

To change the Git user settings, edit the `programs.git` section:

```nix
programs.git = {
  enable = true;
  userName = "Your Name";
  userEmail = "your.email@example.com";
  
  # You can also add more Git configuration:
  extraConfig = {
    init.defaultBranch = "main";
    pull.rebase = false;
  };
};
```

### Adding Programs Configuration

Home Manager can configure many programs declaratively. For example:

```nix
# Add shell configuration
programs.bash = {
  enable = true;
  shellAliases = {
    ll = "ls -la";
    gs = "git status";
  };
};

# Add editor configuration
programs.vim = {
  enable = true;
  settings = {
    number = true;
    relativenumber = true;
  };
};
```

## Version Notes

### Go Version

- **Requested**: Go 1.25
- **Provided**: Go 1.23
- **Reason**: As of the creation of this module, Go 1.23 is the latest stable version in nixpkgs. Go 1.25 may not be released yet or may not be available in the current nixpkgs channel.

**To use the absolute latest Go version:**
```nix
home.packages = with pkgs; [
  go  # Always uses the latest stable Go version
];
```

### Node.js Version

- **Requested**: Node.js 22
- **Provided**: Node.js 22
- **Status**: Available in nixpkgs as `nodejs_22`

### Python Version

- **Requested**: Python 3.14
- **Provided**: Python 3.14
- **Status**: Available in nixpkgs as `python314`

## File Structure

```
modules/smol-exe/
├── README.md       # This file
└── home.nix        # Home Manager configuration
```

## Updating the Profile

After making changes to `home.nix`:

1. If you edited the file in the repository:
   ```bash
   # Copy the updated configuration
   cp modules/smol-exe/home.nix ~/.config/home-manager/home.nix
   
   # Apply changes
   home-manager switch
   ```

2. If you edited `~/.config/home-manager/home.nix` directly:
   ```bash
   # Just apply changes
   home-manager switch
   ```

## Rollback

If something goes wrong after applying changes, Home Manager supports rollback:

```bash
# List generations
home-manager generations

# Rollback to previous generation
home-manager switch --rollback

# Or switch to a specific generation
/nix/store/<path-to-generation>/activate
```

## Troubleshooting

### Package Not Found

**Error**: `error: attribute 'package_name' missing`

**Solution**: The package name might be incorrect. Search for the correct name:
```bash
nix search nixpkgs package_name
```

### Build Failures

**Error**: Various build errors when running `home-manager switch`

**Solution**:
1. Update your channels: `nix-channel --update`
2. Clear the cache: `rm -rf ~/.cache/nix`
3. Try again: `home-manager switch`

### Configuration Syntax Errors

**Error**: Syntax error in Nix expression

**Solution**: Validate your Nix syntax:
```bash
nix-instantiate --parse ~/.config/home-manager/home.nix
```

## Resources

- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Home Manager Options](https://nix-community.github.io/home-manager/options.html)
- [Nixpkgs Search](https://search.nixos.org/packages)
- [Nix Language Basics](https://nixos.org/manual/nix/stable/language/)

## Related Modules

- [smol-exe-bootstrap](../smol-exe-bootstrap/README.md) - Automated installation script for this profile

## License

See the repository's main LICENSE file.
