#!/usr/bin/env bash

# cccleaner uninstallation script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Installation paths
BIN_DIR="/usr/local/bin"
ZSH_COMPLETION_DIR="/usr/local/share/zsh/site-functions"

# Files to remove
SCRIPT_NAME="cccleaner"
COMPLETION_NAME="_cccleaner"

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        if ! command -v sudo &> /dev/null; then
            print_error "This script requires sudo privileges, but sudo is not installed."
        fi
        print_info "This uninstallation requires sudo privileges."
        if ! sudo -v; then
            print_error "Failed to obtain sudo privileges."
        fi
        SUDO="sudo"
    else
        SUDO=""
    fi
}

confirm_uninstall() {
    echo "This will remove:"
    echo "  - $BIN_DIR/$SCRIPT_NAME"
    echo "  - $ZSH_COMPLETION_DIR/$COMPLETION_NAME"
    echo
    read -p "Are you sure you want to uninstall cccleaner? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Uninstallation cancelled."
        exit 0
    fi
}

remove_file() {
    local file="$1"
    local name="$2"

    if [ -f "$file" ]; then
        print_info "Removing $name..."
        $SUDO rm -f "$file"
        print_success "Removed $name"
    else
        print_info "$name not found, skipping"
    fi
}

main() {
    echo "cccleaner uninstallation script"
    echo "================================"
    echo

    # Confirm uninstallation
    confirm_uninstall

    # Check sudo access
    check_sudo

    # Remove files
    remove_file "$BIN_DIR/$SCRIPT_NAME" "$SCRIPT_NAME"
    remove_file "$ZSH_COMPLETION_DIR/$COMPLETION_NAME" "zsh completion"

    echo
    print_success "Uninstallation completed successfully!"
    echo
    echo "Note: Your ~/.claude.json and ~/.claude_backups/ remain untouched."
    echo "If you want to remove them, run:"
    echo "  rm -rf ~/.claude_backups/"
    echo
}

main "$@"
