# smol-exe-bootstrap

Bootstrap module for setting up development environment on exe.dev VMs.

## Usage

To enable this bootstrap script when creating a new exe.dev VM:

```bash
ssh exe.dev new --setup-script "$(curl -fsSL https://raw.githubusercontent.com/b4fun/smol-modules/main/modules/smol-exe-bootstrap/install.sh)"
```

Or set it as your default for all new VMs:

```bash
curl -fsSL https://raw.githubusercontent.com/b4fun/smol-modules/main/modules/smol-exe-bootstrap/install.sh | \
  ssh exe.dev defaults write dev.exe new.setup-script
```

To clear the default:

```bash
ssh exe.dev defaults delete dev.exe new.setup-script
```

## What Gets Installed

This setup script installs:
- Nix package manager
- Home Manager
- Development tools: Go 1.23, Node.js 22, Python 3.14
- GitHub CLI and related tools
- gh-pm (GitHub Project Manager)
- Git configuration (smol user)
