#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Claude Switch installer
# https://github.com/SaschaHeyer/claude-switch
# ─────────────────────────────────────────────────────────────────────────────

REPO="SaschaHeyer/claude-switch"
INSTALL_DIR="$HOME/.local/bin"
BINARY_NAME="claude-switch"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

info()    { printf "${CYAN}::${RESET} %s\n" "$1"; }
success() { printf "${GREEN}✔${RESET}  %s\n" "$1"; }
warn()    { printf "${YELLOW}!${RESET}  %s\n" "$1"; }
error()   { printf "${RED}✘${RESET}  %s\n" "$1"; exit 1; }

# ── Preflight checks ────────────────────────────────────────────────────────

check_deps() {
    if ! command -v claude >/dev/null 2>&1; then
        warn "Claude Code not found. Install it first:"
        printf "    ${DIM}https://docs.anthropic.com/en/docs/claude-code${RESET}\n"
        echo ""
    fi

    if ! command -v gum >/dev/null 2>&1; then
        info "Installing gum (interactive UI)..."
        if command -v brew >/dev/null 2>&1; then
            brew install gum
        else
            warn "gum not found. Install it for the best experience:"
            printf "    ${DIM}brew install gum${RESET}\n"
        fi
    fi
}

# ── Install ──────────────────────────────────────────────────────────────────

install() {
    echo ""
    printf "${BOLD}Claude Switch${RESET} — installer\n"
    echo ""

    # Create install directory
    mkdir -p "$INSTALL_DIR"

    # Download the script
    info "Downloading claude-switch..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "https://raw.githubusercontent.com/${REPO}/main/claude-switch" -o "${INSTALL_DIR}/${BINARY_NAME}"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "${INSTALL_DIR}/${BINARY_NAME}" "https://raw.githubusercontent.com/${REPO}/main/claude-switch"
    else
        error "curl or wget is required to install."
    fi

    chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
    success "Installed to ${INSTALL_DIR}/${BINARY_NAME}"

    # Check PATH
    if ! echo "$PATH" | tr ':' '\n' | grep -q "^${INSTALL_DIR}$"; then
        warn "${INSTALL_DIR} is not in your PATH."
        echo ""
        # Use the login shell: this script usually runs via `curl | bash`,
        # so BASH_VERSION is always set and says nothing about the user's shell.
        case "$(basename "${SHELL:-}")" in
            fish)
                info "Add it to your fish PATH (persists across sessions):"
                printf "    ${DIM}fish_add_path %s${RESET}\n" "$INSTALL_DIR"
                ;;
            *)
                local shell_config="$HOME/.zshrc"
                if [ "$(basename "${SHELL:-}")" = "bash" ]; then
                    shell_config="$HOME/.bashrc"
                fi
                info "Add it to your shell config:"
                printf "    ${DIM}echo 'export PATH=\"%s:\$PATH\"' >> %s${RESET}\n" "$INSTALL_DIR" "$shell_config"
                printf "    ${DIM}source %s${RESET}\n" "$shell_config"
                ;;
        esac
        echo ""
    fi

    # Install dependencies
    check_deps

    echo ""
    success "Installation complete!"
    echo ""
    printf "  Get started:\n"
    printf "    ${CYAN}claude-switch create work${RESET}       ${DIM}# create a profile${RESET}\n"
    printf "    ${CYAN}claude-switch work${RESET}              ${DIM}# launch it${RESET}\n"
    printf "    ${CYAN}claude-switch${RESET}                   ${DIM}# interactive menu${RESET}\n"
    echo ""
}

# ── Uninstall ────────────────────────────────────────────────────────────────

uninstall() {
    echo ""
    printf "${BOLD}Claude Switch${RESET} — uninstaller\n"
    echo ""

    if [ -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
        rm -f "${INSTALL_DIR}/${BINARY_NAME}"
        success "Removed ${INSTALL_DIR}/${BINARY_NAME}"
    else
        warn "claude-switch not found at ${INSTALL_DIR}/${BINARY_NAME}"
    fi

    echo ""
    info "Profile directories (~/.claude-*) and shell shortcuts were not removed."
    info "Run 'claude-switch delete <name>' first, or remove them manually:"
    printf "    ${DIM}~/.claude-*  ·  aliases in ~/.zshrc  ·  ~/.config/fish/functions/claude-*.fish${RESET}\n"
    echo ""
}

# ── Entry point ──────────────────────────────────────────────────────────────

case "${1:-}" in
    uninstall|--uninstall) uninstall ;;
    *)                     install ;;
esac
