#!/usr/bin/env bash

# smol-exe-bootstrap install.sh
# Bootstrap a development environment on exe.dev with Nix and Home Manager

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$(dirname "$SCRIPT_DIR")"
SMOL_EXE_DIR="$MODULES_DIR/smol-exe"

log_info "Starting smol-exe-bootstrap installation..."
log_info "Script directory: $SCRIPT_DIR"
log_info "Modules directory: $MODULES_DIR"

# Check if running on Linux (exe.dev runs on Linux)
if [[ "$(uname -s)" != "Linux" ]]; then
    log_warn "This script is designed for Linux (exe.dev). Detected: $(uname -s)"
    log_warn "Continuing anyway, but some steps may fail..."
fi

# Step 1: Install Nix if not already installed
install_nix() {
    if command -v nix &> /dev/null; then
        log_info "Nix is already installed: $(nix --version)"
        return 0
    fi

    log_info "Installing Nix package manager..."
    
    # Check if we have necessary prerequisites
    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed. Please install curl first."
        return 1
    fi

    # Install Nix using the official installer (multi-user installation)
    log_info "Running Nix installer..."
    sh <(curl -L https://nixos.org/nix/install) --daemon
    
    # Source the Nix profile
    if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        log_info "Nix daemon profile sourced"
    fi
    
    # Verify installation
    if command -v nix &> /dev/null; then
        log_info "Nix successfully installed: $(nix --version)"
    else
        log_error "Nix installation failed. Please check the logs above."
        return 1
    fi
}

# Step 2: Install Home Manager if not already installed
install_home_manager() {
    # First, ensure Nix is available in the current session
    if ! command -v nix &> /dev/null; then
        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
            . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        fi
    fi

    if command -v home-manager &> /dev/null; then
        log_info "Home Manager is already installed: $(home-manager --version)"
        return 0
    fi

    log_info "Installing Home Manager..."
    
    # Determine the Nix channel for the current system
    local NIX_CHANNEL="nixpkgs-unstable"
    
    # Add the home-manager channel
    log_info "Adding home-manager channel..."
    nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
    nix-channel --update
    
    # Install Home Manager
    log_info "Installing Home Manager via nix-shell..."
    nix-shell '<home-manager>' -A install
    
    # Source the Home Manager session variables
    if [ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
        . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
    fi
    
    # Verify installation
    if command -v home-manager &> /dev/null; then
        log_info "Home Manager successfully installed: $(home-manager --version)"
    else
        log_error "Home Manager installation failed. Please check the logs above."
        return 1
    fi
}

# Step 3: Install gh-pm from the repository
install_gh_pm() {
    log_info "Installing gh-pm from repository..."
    
    local GH_PM_DIR="$MODULES_DIR/gh-pm"
    
    if [ ! -f "$GH_PM_DIR/install.sh" ]; then
        log_error "gh-pm install script not found at: $GH_PM_DIR/install.sh"
        return 1
    fi
    
    # Create gh-pm directory if it doesn't exist
    mkdir -p "$HOME/.gh-pm"
    
    # Install gh-pm as a systemd service
    log_info "Running gh-pm install script..."
    bash "$GH_PM_DIR/install.sh" --exec-start "$GH_PM_DIR/bin/gh-pm"
    
    log_info "gh-pm successfully installed!"
}

# Step 4: Apply the smol-exe Nix profile
apply_smol_profile() {
    log_info "Applying smol-exe Nix profile..."
    
    # Ensure Home Manager is available
    if ! command -v home-manager &> /dev/null; then
        log_error "Home Manager is not available. Cannot apply profile."
        return 1
    fi
    
    # Check if the smol-exe home.nix exists
    if [ ! -f "$SMOL_EXE_DIR/home.nix" ]; then
        log_error "smol-exe profile not found at: $SMOL_EXE_DIR/home.nix"
        return 1
    fi
    
    # Create or update the Home Manager configuration directory
    local HM_CONFIG_DIR="$HOME/.config/home-manager"
    mkdir -p "$HM_CONFIG_DIR"
    
    # Backup existing configuration if it exists
    if [ -f "$HM_CONFIG_DIR/home.nix" ]; then
        log_warn "Backing up existing home.nix to home.nix.backup"
        cp "$HM_CONFIG_DIR/home.nix" "$HM_CONFIG_DIR/home.nix.backup"
    fi
    
    # Copy the smol-exe profile
    log_info "Copying smol-exe profile to $HM_CONFIG_DIR/home.nix"
    cp "$SMOL_EXE_DIR/home.nix" "$HM_CONFIG_DIR/home.nix"
    
    # Apply the Home Manager configuration
    log_info "Activating Home Manager configuration..."
    home-manager switch
    
    log_info "smol-exe profile successfully applied!"
}

# Step 5: Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    local errors=0
    
    # Check Nix
    if command -v nix &> /dev/null; then
        log_info "✓ Nix: $(nix --version)"
    else
        log_error "✗ Nix is not installed or not in PATH"
        errors=$((errors + 1))
    fi
    
    # Check Home Manager
    if command -v home-manager &> /dev/null; then
        log_info "✓ Home Manager: $(home-manager --version)"
    else
        log_error "✗ Home Manager is not installed or not in PATH"
        errors=$((errors + 1))
    fi
    
    # Check Go
    if command -v go &> /dev/null; then
        log_info "✓ Go: $(go version)"
    else
        log_warn "✗ Go is not installed or not in PATH (may require shell restart)"
    fi
    
    # Check Node.js
    if command -v node &> /dev/null; then
        log_info "✓ Node.js: $(node --version)"
    else
        log_warn "✗ Node.js is not installed or not in PATH (may require shell restart)"
    fi
    
    # Check Python
    if command -v python3 &> /dev/null; then
        log_info "✓ Python: $(python3 --version)"
    else
        log_warn "✗ Python is not installed or not in PATH (may require shell restart)"
    fi
    
    # Check gh-pm
    if [ -f "$HOME/.config/systemd/user/gh-pm.service" ]; then
        log_info "✓ gh-pm service installed"
    else
        log_warn "✗ gh-pm service not found"
    fi
    
    # Check Git configuration
    local git_user=$(git config --global user.name 2>/dev/null || echo "")
    local git_email=$(git config --global user.email 2>/dev/null || echo "")
    
    if [[ "$git_user" == "smol" ]]; then
        log_info "✓ Git user.name: $git_user"
    else
        log_warn "✗ Git user.name is not set to 'smol' (current: $git_user)"
    fi
    
    if [[ "$git_email" == "smol@ss.isbuild.ing" ]]; then
        log_info "✓ Git user.email: $git_email"
    else
        log_warn "✗ Git user.email is not set to 'smol@ss.isbuild.ing' (current: $git_email)"
    fi
    
    if [ $errors -gt 0 ]; then
        log_error "Installation completed with $errors critical errors"
        return 1
    else
        log_info "All critical components verified successfully!"
        log_warn "Note: You may need to restart your shell or source your profile for all tools to be available in PATH"
        return 0
    fi
}

# Main installation flow
main() {
    log_info "========================================"
    log_info "smol-exe-bootstrap Installation Script"
    log_info "========================================"
    echo ""
    
    # Run installation steps
    install_nix || {
        log_error "Nix installation failed. Aborting."
        exit 1
    }
    
    echo ""
    install_home_manager || {
        log_error "Home Manager installation failed. Aborting."
        exit 1
    }
    
    echo ""
    apply_smol_profile || {
        log_error "Failed to apply smol-exe profile. Aborting."
        exit 1
    }
    
    echo ""
    install_gh_pm || {
        log_warn "gh-pm installation failed. Continuing anyway..."
    }
    
    echo ""
    verify_installation || {
        log_warn "Installation completed with some warnings. Please review the output above."
    }
    
    echo ""
    log_info "========================================"
    log_info "Installation Complete!"
    log_info "========================================"
    log_info "Please restart your shell or run:"
    log_info "  source ~/.nix-profile/etc/profile.d/hm-session-vars.sh"
    log_info "  source ~/.nix-profile/etc/profile.d/nix.sh"
    log_info "to make all tools available in your current session."
}

# Run main function
main "$@"
