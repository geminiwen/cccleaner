#!/usr/bin/env bash

# cccleaner installation script
# Usage: curl -s https://raw.githubusercontent.com/geminiwen/cccleaner/master/install.sh | bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# GitHub repository
REPO="geminiwen/cccleaner"
BRANCH="master"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

# Installation paths
BIN_DIR="/usr/local/bin"
ZSH_COMPLETION_DIR="/usr/local/share/zsh/site-functions"

# Files to install
SCRIPT_NAME="cccleaner"
COMPLETION_NAME="_cccleaner"

# Temporary directory for downloads
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

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
        print_info "This installation requires sudo privileges."
        if ! sudo -v; then
            print_error "Failed to obtain sudo privileges."
        fi
        SUDO="sudo"
    else
        SUDO=""
    fi
}

check_dependencies() {
    if ! command -v jq &> /dev/null; then
        print_error "jq is required but not installed. Please install jq first:\n  macOS: brew install jq\n  Linux: apt-get install jq or yum install jq"
    fi
}

download_file() {
    local url="$1"
    local dest="$2"
    local name="$3"

    print_info "Downloading $name..."

    if command -v curl &> /dev/null; then
        if ! curl -fsSL "$url" -o "$dest"; then
            print_error "Failed to download $name from $url"
        fi
    elif command -v wget &> /dev/null; then
        if ! wget -q "$url" -O "$dest"; then
            print_error "Failed to download $name from $url"
        fi
    else
        print_error "Neither curl nor wget is available. Please install one of them."
    fi
}

install_script() {
    local src="$1"
    local dest="$2"
    local name="$3"

    print_info "Installing $name to $dest..."

    # Create directory if it doesn't exist
    $SUDO mkdir -p "$(dirname "$dest")"

    # Install file
    $SUDO cp "$src" "$dest"

    # Set permissions
    if [[ "$name" == "$SCRIPT_NAME" ]]; then
        $SUDO chmod 755 "$dest"
    else
        $SUDO chmod 644 "$dest"
    fi

    print_success "Installed $name"
}

main() {
    echo "cccleaner installation script"
    echo "=============================="
    echo

    # Check if running from local directory or remote
    if [ -f "$SCRIPT_NAME" ] && [ -f "$COMPLETION_NAME" ]; then
        print_info "Local installation detected"
        LOCAL_INSTALL=true
    else
        print_info "Remote installation from GitHub"
        LOCAL_INSTALL=false
    fi

    # Check dependencies
    check_dependencies

    # Check sudo access
    check_sudo

    # Get files
    if [ "$LOCAL_INSTALL" = true ]; then
        SCRIPT_FILE="$SCRIPT_NAME"
        COMPLETION_FILE="$COMPLETION_NAME"
    else
        print_info "Downloading files from GitHub..."

        SCRIPT_FILE="$TMP_DIR/$SCRIPT_NAME"
        COMPLETION_FILE="$TMP_DIR/$COMPLETION_NAME"

        download_file "$RAW_URL/$SCRIPT_NAME" "$SCRIPT_FILE" "$SCRIPT_NAME"
        download_file "$RAW_URL/$COMPLETION_NAME" "$COMPLETION_FILE" "$COMPLETION_NAME"
    fi

    # Install script
    install_script "$SCRIPT_FILE" "$BIN_DIR/$SCRIPT_NAME" "$SCRIPT_NAME"

    # Create zsh completion directory if it doesn't exist
    print_info "Creating zsh completion directory..."
    $SUDO mkdir -p "$ZSH_COMPLETION_DIR"

    # Install zsh completion
    install_script "$COMPLETION_FILE" "$ZSH_COMPLETION_DIR/$COMPLETION_NAME" "$COMPLETION_NAME"

    echo
    print_success "Installation completed successfully!"
    echo
    echo "Next steps:"
    echo "  1. The cccleaner command is now available in your PATH"
    echo "  2. For zsh completion to work, make sure fpath includes $ZSH_COMPLETION_DIR"
    echo "  3. Restart your shell or run: exec zsh"
    echo
    echo "Usage:"
    echo "  cccleaner --help"
    echo "  cccleaner --list"
    echo "  cccleaner --all"
    echo
}

main "$@"
