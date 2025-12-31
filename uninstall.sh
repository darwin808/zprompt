#!/bin/bash
# zprompt uninstaller

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

main() {
    echo ""
    echo "Uninstalling zprompt..."
    echo ""

    # Remove binary
    if [ -f "$INSTALL_DIR/zprompt" ]; then
        rm "$INSTALL_DIR/zprompt"
        success "Removed $INSTALL_DIR/zprompt"
    else
        info "Binary not found at $INSTALL_DIR/zprompt"
    fi

    # Remove from .zshrc
    if [ -f "$HOME/.zshrc" ]; then
        if grep -q "zprompt init" "$HOME/.zshrc"; then
            # Create backup
            cp "$HOME/.zshrc" "$HOME/.zshrc.bak"
            # Remove zprompt lines
            sed -i.tmp '/# zprompt prompt/d' "$HOME/.zshrc"
            sed -i.tmp '/zprompt init/d' "$HOME/.zshrc"
            rm -f "$HOME/.zshrc.tmp"
            success "Removed zprompt from ~/.zshrc (backup: ~/.zshrc.bak)"
        fi
    fi

    echo ""
    success "zprompt has been uninstalled"
    echo ""
    echo "Restart your shell or run: source ~/.zshrc"
    echo ""
}

main "$@"
