# smol-exe

Home Manager profile for the smol development environment on exe.dev.

## Usage

This module is normally applied by `smol-exe-bootstrap`.

To apply it manually:

```bash
mkdir -p ~/.config/home-manager
cp modules/smol-exe/home.nix ~/.config/home-manager/home.nix
home-manager switch
```

## What It Configures

- Git identity: `smol <smol@ss.isbuild.ing>`
- Development packages:
  - Go 1.25
  - Node.js 22
  - Python 3.14
  - GitHub CLI
  - `jq`
  - `toml2json`
- A starter `~/.gh-pm/gh-pm.toml`

## How An LLM Agent Should Invoke It

Use this profile through Home Manager:

```bash
home-manager switch
```

If bootstrapping a fresh exe.dev VM, prefer `modules/smol-exe-bootstrap/install.sh` instead.
