# smol-exe-bootstrap

Bootstrap module for setting up development environment on exe.dev VMs.

## Usage

To enable this bootstrap script when creating a new exe.dev VM:

```bash
ssh exe.dev new --setup-script "$(curl -fsSL https://raw.githubusercontent.com/b4fun/smol-modules/main/modules/smol-exe-bootstrap/install.sh)"
```

The script uses the `smol-modules` repo as the source of truth. When fetched standalone, it downloads the selected repo ref, applies `modules/smol-exe/home.nix`, and `smol-exe` resolves `gh-pm` from that same repo/ref.

```bash
curl -fsSL https://raw.githubusercontent.com/b4fun/smol-modules/main/modules/smol-exe-bootstrap/install.sh | \
  SMOL_MODULES_REF=feature/smol-exe-bootstrap bash
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
- Development tools: Go 1.25, Node.js 22, Python 3.14
- GitHub CLI and related tools
- gh-pm (GitHub Project Manager)
- Git configuration (smol user)
