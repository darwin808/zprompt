#!/bin/bash
# zprompt installer
# Usage: curl -fsSL https://raw.githubusercontent.com/darwin808/zprompt/main/install.sh | bash

set -euo pipefail

ZPROMPT_VERSION="${ZPROMPT_VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
REPO_URL="https://github.com/darwin808/zprompt"
REPO_RAW="https://raw.githubusercontent.com/darwin808/zprompt/main"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Detect OS and architecture
detect_platform() {
    local os arch

    case "$(uname -s)" in
        Darwin)
            os="macos"
            ;;
        Linux)
            os="linux"
            ;;
        *)
            error "Unsupported operating system: $(uname -s)"
            ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64)
            arch="x86_64"
            ;;
        arm64|aarch64)
            arch="aarch64"
            ;;
        *)
            error "Unsupported architecture: $(uname -m)"
            ;;
    esac

    echo "${os}-${arch}"
}

# Check for required tools
check_dependencies() {
    local missing=()

    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        missing+=("curl or wget")
    fi

    if ! command -v tar &> /dev/null; then
        missing+=("tar")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        error "Missing required tools: ${missing[*]}"
    fi
}

# Download file
download() {
    local url="$1"
    local dest="$2"

    if command -v curl &> /dev/null; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget &> /dev/null; then
        wget -q "$url" -O "$dest"
    fi
}

# Build from source (fallback if no prebuilt binary)
build_from_source() {
    info "Building from source..."

    # Check for Zig
    if ! command -v zig &> /dev/null; then
        warn "Zig not found. Installing via package manager..."
        install_zig
    fi

    # Clone and build
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT

    info "Cloning repository..."
    git clone --depth 1 "$REPO_URL" "$tmp_dir/zprompt" 2>/dev/null || {
        # If repo doesn't exist yet, try local build
        if [ -f "build.zig" ]; then
            info "Building local copy..."
            zig build -Doptimize=ReleaseFast
            mkdir -p "$INSTALL_DIR"
            cp "zig-out/bin/zprompt" "$INSTALL_DIR/zprompt"
            return 0
        else
            error "Could not clone repository and no local build.zig found"
        fi
    }

    cd "$tmp_dir/zprompt"
    zig build -Doptimize=ReleaseFast
    mkdir -p "$INSTALL_DIR"
    cp "zig-out/bin/zprompt" "$INSTALL_DIR/zprompt"
}

# Install Zig
install_zig() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install zig
        else
            error "Please install Homebrew first: https://brew.sh"
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y zig
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y zig
        elif command -v pacman &> /dev/null; then
            sudo pacman -S zig
        else
            # Download Zig directly
            local platform
            platform=$(detect_platform)
            local zig_url="https://ziglang.org/download/0.13.0/zig-${platform}-0.13.0.tar.xz"

            local tmp_dir
            tmp_dir=$(mktemp -d)

            info "Downloading Zig..."
            download "$zig_url" "$tmp_dir/zig.tar.xz"
            tar -xf "$tmp_dir/zig.tar.xz" -C "$tmp_dir"

            mkdir -p "$HOME/.local/bin"
            cp "$tmp_dir/zig-${platform}-0.13.0/zig" "$HOME/.local/bin/"

            rm -rf "$tmp_dir"
        fi
    fi
}

# Get latest release tag
get_latest_version() {
    local latest
    latest=$(curl -fsSL "https://api.github.com/repos/darwin808/zprompt/releases/latest" 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    echo "${latest:-latest}"
}

# Main installation
install_zprompt() {
    local platform
    platform=$(detect_platform)

    info "Detected platform: $platform"
    info "Installing zprompt to: $INSTALL_DIR"

    mkdir -p "$INSTALL_DIR"

    # Get version
    local version="$ZPROMPT_VERSION"
    if [ "$version" = "latest" ]; then
        version=$(get_latest_version)
        info "Latest version: $version"
    fi

    # Map platform to artifact name
    local artifact_name
    case "$platform" in
        macos-aarch64) artifact_name="zprompt-macos-aarch64" ;;
        macos-x86_64)  artifact_name="zprompt-macos-x86_64" ;;
        linux-aarch64) artifact_name="zprompt-linux-aarch64" ;;
        linux-x86_64)  artifact_name="zprompt-linux-x86_64" ;;
        *) error "Unsupported platform: $platform" ;;
    esac

    # Try downloading prebuilt binary first
    local binary_url="${REPO_URL}/releases/download/${version}/${artifact_name}"
    info "Downloading from: $binary_url"

    if download "$binary_url" "$INSTALL_DIR/zprompt" 2>/dev/null; then
        chmod +x "$INSTALL_DIR/zprompt"
        success "Downloaded prebuilt binary"
    else
        warn "No prebuilt binary found, building from source..."
        build_from_source
    fi

    chmod +x "$INSTALL_DIR/zprompt"
    success "zprompt installed to $INSTALL_DIR/zprompt"
}

# Configure shell
configure_shell() {
    info "Configuring shell..."

    local shell_name
    shell_name=$(basename "$SHELL")

    case "$shell_name" in
        zsh)
            local zshrc="$HOME/.zshrc"
            local init_line='eval "$(zprompt init zsh)"'

            if ! grep -q "zprompt init" "$zshrc" 2>/dev/null; then
                echo "" >> "$zshrc"
                echo "# zprompt prompt" >> "$zshrc"
                echo "$init_line" >> "$zshrc"
                success "Added zprompt to ~/.zshrc"
            else
                warn "zprompt already configured in ~/.zshrc"
            fi
            ;;
        *)
            warn "Only zsh is supported. Please add to your shell config manually:"
            echo "  eval \"\$(zprompt init zsh)\""
            ;;
    esac
}

# Ensure INSTALL_DIR is in PATH
check_path() {
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        warn "$INSTALL_DIR is not in your PATH"
        echo ""
        echo "Add this to your shell config:"
        echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
        echo ""
    fi
}

# Main
main() {
    echo ""
    echo "  ╺━┓┏━┓┏━┓┏━┓┏┳┓┏━┓╺┳╸"
    echo "  ┏━┛┣━┛┣┳┛┃ ┃┃┃┃┣━┛ ┃ "
    echo "  ┗━╸╹  ╹┗╸┗━┛╹ ╹╹   ╹ "
    echo ""
    echo "  A minimal, fast shell prompt"
    echo ""

    check_dependencies
    install_zprompt
    configure_shell
    check_path

    echo ""
    success "Installation complete!"
    echo ""
    echo "Restart your shell or run:"
    echo "  source ~/.zshrc"
    echo ""
}

main "$@"
