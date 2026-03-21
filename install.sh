#!/usr/bin/env bash

# cccleaner installation script
# Usage:
#   curl -s https://raw.githubusercontent.com/geminiwen/cccleaner/master/install.sh | bash
#   curl -s https://raw.githubusercontent.com/geminiwen/cccleaner/master/install.sh | bash -s -- --set-us-timezone
#   curl -s https://raw.githubusercontent.com/geminiwen/cccleaner/master/install.sh | bash -s -- --unset-timezone

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
TZ_LAUNCH_AGENT_LABEL="com.cccleaner.env-tz"
TZ_LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/${TZ_LAUNCH_AGENT_LABEL}.plist"
US_TIMEZONE="America/Los_Angeles"

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

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

write_if_changed() {
    local candidate="$1"
    local target="$2"

    if [ -f "$target" ] && cmp -s "$candidate" "$target"; then
        rm -f "$candidate"
        return 1
    fi

    mv "$candidate" "$target"
    return 0
}

remove_tz_exports() {
    local file="$1"
    local candidate

    if [ ! -f "$file" ]; then
        return 1
    fi

    candidate=$(mktemp "${TMP_DIR}/tz-file.XXXXXX")

    awk '
        /^[[:space:]]*export[[:space:]]+TZ=/ { next }
        { lines[++n] = $0 }
        END {
            while (n > 0 && lines[n] ~ /^[[:space:]]*$/) {
                n--
            }
            for (i = 1; i <= n; i++) {
                print lines[i]
            }
            if (n > 0) {
                printf "\n"
            }
        }
    ' "$file" > "$candidate"

    write_if_changed "$candidate" "$file"
}

ensure_tz_export_at_top() {
    local file="$1"
    local timezone="$2"
    local filtered
    local candidate

    mkdir -p "$(dirname "$file")"
    [ -f "$file" ] || : > "$file"

    filtered=$(mktemp "${TMP_DIR}/tz-file.XXXXXX")
    candidate=$(mktemp "${TMP_DIR}/tz-file.XXXXXX")
    awk '
        /^[[:space:]]*export[[:space:]]+TZ=/ { next }
        !started && /^[[:space:]]*$/ { next }
        {
            started = 1
            print
        }
    ' "$file" > "$filtered"

    {
        printf 'export TZ="%s"\n' "$timezone"
        printf '\n'
        cat "$filtered"
    } > "$candidate"

    rm -f "$filtered"
    write_if_changed "$candidate" "$file"
}

ensure_tz_export_at_end() {
    local file="$1"
    local timezone="$2"
    local filtered
    local candidate

    mkdir -p "$(dirname "$file")"
    [ -f "$file" ] || : > "$file"

    filtered=$(mktemp "${TMP_DIR}/tz-file.XXXXXX")
    candidate=$(mktemp "${TMP_DIR}/tz-file.XXXXXX")

    awk '
        /^[[:space:]]*export[[:space:]]+TZ=/ { next }
        { lines[++n] = $0 }
        END {
            while (n > 0 && lines[n] ~ /^[[:space:]]*$/) {
                n--
            }
            for (i = 1; i <= n; i++) {
                print lines[i]
            }
        }
    ' "$file" > "$filtered"

    {
        if [ -s "$filtered" ]; then
            cat "$filtered"
            printf '\n\n'
        fi
        printf 'export TZ="%s"\n' "$timezone"
    } > "$candidate"

    rm -f "$filtered"
    write_if_changed "$candidate" "$file"
}

write_timezone_launch_agent() {
    local timezone="$1"

    if [ "$(uname -s)" != "Darwin" ]; then
        return 0
    fi

    mkdir -p "$(dirname "$TZ_LAUNCH_AGENT_PATH")"

    cat > "$TZ_LAUNCH_AGENT_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${TZ_LAUNCH_AGENT_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>launchctl</string>
    <string>setenv</string>
    <string>TZ</string>
    <string>${timezone}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF
}

refresh_launchctl_timezone() {
    local timezone="$1"
    local gui_domain

    if [ "$(uname -s)" != "Darwin" ]; then
        return 0
    fi

    if ! command -v launchctl > /dev/null 2>&1; then
        print_warning "launchctl not found, skipped macOS session timezone sync."
        return 0
    fi

    if ! launchctl setenv TZ "$timezone" > /dev/null 2>&1; then
        print_warning "Failed to update launchctl environment for TZ."
    fi

    gui_domain="gui/$(id -u)"
    launchctl bootout "$gui_domain" "$TZ_LAUNCH_AGENT_PATH" > /dev/null 2>&1 || true

    if ! launchctl bootstrap "$gui_domain" "$TZ_LAUNCH_AGENT_PATH" > /dev/null 2>&1; then
        print_warning "Failed to bootstrap LaunchAgent ${TZ_LAUNCH_AGENT_LABEL}."
    fi

    if ! launchctl kickstart -k "${gui_domain}/${TZ_LAUNCH_AGENT_LABEL}" > /dev/null 2>&1; then
        print_warning "Failed to kickstart LaunchAgent ${TZ_LAUNCH_AGENT_LABEL}."
    fi
}

remove_timezone_launch_agent() {
    local gui_domain

    if [ "$(uname -s)" != "Darwin" ]; then
        return 0
    fi

    if ! command -v launchctl > /dev/null 2>&1; then
        print_warning "launchctl not found, skipped macOS session timezone cleanup."
        return 0
    fi

    gui_domain="gui/$(id -u)"
    launchctl bootout "$gui_domain" "$TZ_LAUNCH_AGENT_PATH" > /dev/null 2>&1 || true

    if [ -f "$TZ_LAUNCH_AGENT_PATH" ]; then
        rm -f "$TZ_LAUNCH_AGENT_PATH"
    fi

    if ! launchctl unsetenv TZ > /dev/null 2>&1; then
        print_warning "Failed to unset launchctl environment variable TZ."
    fi
}

set_timezone() {
    local timezone="$1"
    local shell_files=(
        "$HOME/.zshenv"
        "$HOME/.zprofile"
        "$HOME/.bash_profile"
        "$HOME/.bashrc"
        "$HOME/.profile"
    )
    local file

    [ -n "$timezone" ] || print_error "set_timezone requires a timezone value."

    print_info "Persisting TZ=${timezone} in shell startup files..."
    for file in "${shell_files[@]}"; do
        if ensure_tz_export_at_top "$file" "$timezone"; then
            print_info "Updated $file"
        else
            print_info "No change for $file"
        fi
    done

    if ensure_tz_export_at_end "$HOME/.zshrc" "$timezone"; then
        print_info "Updated $HOME/.zshrc (tail guard)"
    else
        print_info "No change for $HOME/.zshrc"
    fi

    if [ "$(uname -s)" = "Darwin" ]; then
        print_info "Writing macOS LaunchAgent..."
        write_timezone_launch_agent "$timezone"
    else
        print_info "Skipping LaunchAgent setup on non-macOS system"
    fi

    print_info "Refreshing current macOS login session environment..."
    refresh_launchctl_timezone "$timezone"

    print_success "Timezone has been pinned to ${timezone}"
    echo
    echo "Verification in a fresh shell:"
    echo "  zsh -lc 'echo \$TZ'"
    echo "  bash -lc 'node -e \"console.log(process.env.TZ, Intl.DateTimeFormat().resolvedOptions().timeZone, new Date().toString())\"'"
    echo "  launchctl getenv TZ"
    echo
    echo "Already-open terminals keep their current TZ until you refresh them:"
    echo "  export TZ=\"${timezone}\""
    echo "  exec \$SHELL -l"
}

unset_timezone() {
    local shell_files=(
        "$HOME/.zshenv"
        "$HOME/.zprofile"
        "$HOME/.bash_profile"
        "$HOME/.bashrc"
        "$HOME/.profile"
        "$HOME/.zshrc"
    )
    local file

    print_info "Removing TZ overrides from shell startup files..."
    for file in "${shell_files[@]}"; do
        if remove_tz_exports "$file"; then
            print_info "Updated $file"
        else
            print_info "No change for $file"
        fi
    done

    print_info "Removing macOS LaunchAgent and clearing current login session TZ..."
    remove_timezone_launch_agent

    print_success "Timezone override has been removed"
    echo
    echo "Verification in a fresh shell:"
    echo "  zsh -lc 'echo \${TZ:-<unset>}'"
    echo "  bash -lc 'node -e '\''console.log(process.env.TZ || \"<unset>\", Intl.DateTimeFormat().resolvedOptions().timeZone, new Date().toString())'\'''"
    echo "  launchctl getenv TZ"
}

handle_timezone_command() {
    case "${1:-}" in
        --set-us-timezone)
            set_timezone "$US_TIMEZONE"
            exit 0
            ;;
        --unset-timezone)
            unset_timezone
            exit 0
            ;;
    esac
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
    handle_timezone_command "${1:-}"

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
    echo "  cccleaner --set-us-timezone"
    echo "  cccleaner --unset-timezone"
    echo
    echo "Install-script timezone helpers:"
    echo "  bash install.sh --set-us-timezone"
    echo "  bash install.sh --unset-timezone"
    echo
}

main "$@"
