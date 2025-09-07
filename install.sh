#!/bin/bash
# OpenFortiVPN macOS Installation Script
set -e

# Path variables
MAIN_SCRIPT_PATH="/usr/local/bin/openfortivpn-macosx"
LIB_DIR="/usr/local/lib/openfortivpn-macosx"
LIB_FUNCTIONS_PATH="$LIB_DIR/functions.sh"
PPP_IP_UP_PATH="/etc/ppp/ip-up"
PPP_IP_DOWN_PATH="/etc/ppp/ip-down"
CONFIG_DIR="/usr/local/etc/openfortivpn-macosx"
CONFIG_PATH="$CONFIG_DIR/config.sh"
EXAMPLE_CONFIG="config.sh.example"
SUDOERS_PATH="/etc/sudoers.d/openfortivpn-macosx"
ZSHRC_PATH="~/.zshrc"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

echo -e "${BLUE}🚀 Installing OpenFortiVPN for macOS...${NC}\n"

# 1. Copy the main script
print_info "Installing main script..."
sudo cp openfortivpn-macosx "$MAIN_SCRIPT_PATH"
sudo chmod 755 "$MAIN_SCRIPT_PATH"
print_success "Main script installed"

# 2. Install the library
print_info "Installing library..."
sudo mkdir -p "$LIB_DIR"
sudo cp lib/functions.sh "$LIB_FUNCTIONS_PATH"
print_success "Library installed"

# 3. Install PPP scripts (backup existing ones first)
print_info "Installing PPP scripts..."
if [[ -f "$PPP_IP_UP_PATH" ]]; then
    sudo cp "$PPP_IP_UP_PATH" "${PPP_IP_UP_PATH}.bak_$(date +%s)"
    print_warning "Backed up existing $PPP_IP_UP_PATH"
fi
if [[ -f "$PPP_IP_DOWN_PATH" ]]; then
    sudo cp "$PPP_IP_DOWN_PATH" "${PPP_IP_DOWN_PATH}.bak_$(date +%s)"
    print_warning "Backed up existing $PPP_IP_DOWN_PATH"
fi
sudo cp ppp/ip-up "$PPP_IP_UP_PATH"
sudo cp ppp/ip-down "$PPP_IP_DOWN_PATH"
sudo chmod 755 "$PPP_IP_UP_PATH" "$PPP_IP_DOWN_PATH"
print_success "PPP scripts installed"

# 4. Install configuration
print_info "Installing configuration..."
sudo mkdir -p "$CONFIG_DIR"

# Check if configuration already exists
if [[ -f "$CONFIG_PATH" ]]; then
    print_warning "Configuration file already exists!"
    read -p "$(echo -e "${YELLOW}Do you want to overwrite the existing configuration? (y/N): ${NC}")" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo cp "$CONFIG_PATH" "${CONFIG_PATH}.bak_$(date +%s)"
        sudo cp "$EXAMPLE_CONFIG" "$CONFIG_PATH"
        print_warning "Existing configuration backed up to ${CONFIG_PATH}.bak_$(date +%s)"
        print_success "Configuration overwritten"
    else
        print_info "Configuration file not changed"
    fi
else
    sudo cp "$EXAMPLE_CONFIG" "$CONFIG_PATH"
    print_success "Configuration installed"
fi

# 5. Install sudoers file
print_info "Installing sudoers file..."
CURRENT_USER=$(sudo stat -f "%Su" ~/)
sudo sed "s/jseifeddine/$CURRENT_USER/g" sudoers.d/openfortivpn-macosx | sudo tee "$SUDOERS_PATH" > /dev/null
sudo chmod 440 "$SUDOERS_PATH"
print_success "Sudoers file installed"

# 6. Add shell alias to ~/.zshrc
print_info "Adding shell alias..."
ALIAS_ADDED=false

# Array of common zsh alias file locations
ZSH_ALIAS_FILES=(
    "$HOME/.zshrc"                          # Standard zsh config
    "$HOME/.zsh_aliases"                    # Common alias file
    "$HOME/.aliases"                        # Generic alias file
    "$HOME/.local/.zshrc"                   # Local zsh config
    "$HOME/.config/zsh/.zshrc"              # XDG config directory
    "$HOME/.config/zsh/aliases"             # XDG config aliases
    "$HOME/.config/aliases"                 # XDG generic aliases
    "$HOME/.zsh/.zshrc"                     # Zsh subdirectory config
    "$HOME/.zsh/aliases"                    # Zsh subdirectory aliases
    "$HOME/.zsh/aliases.zsh"                # Zsh aliases with extension
    "$HOME/.oh-my-zsh/custom/aliases.zsh"   # Oh-My-Zsh custom aliases
    "$HOME/.local/share/zsh/.zshrc"         # XDG local share
    "$HOME/.local/share/zsh/aliases"        # XDG local share aliases
    "$HOME/.zsh_profile"                    # Alternative profile file
)

# Check if alias exists in any of the files
ALIAS_FOUND=false
FOUND_IN=""
ALIAS_EXISTS=false

for file in "${ZSH_ALIAS_FILES[@]}"; do
    if [[ -f "$file" ]] && grep -q "^alias vpn=" "$file" 2>/dev/null; then
        ALIAS_FOUND=true
        FOUND_IN="$file"
        # Check if the alias starts with 'sudo openfortivpn-macosx'
        if grep -q "^alias vpn='sudo openfortivpn-macosx" "$file" 2>/dev/null; then
            ALIAS_EXISTS=true
        fi
        break
    fi
done

# Also check if vpn command exists (could be a binary or function)
if command -v vpn > /dev/null 2>&1; then
    COMMAND_FOUND=true
    FOUND_IN="$(command -v vpn)"
    # Check if it's an alias that starts with 'sudo openfortivpn-macosx'
    if alias vpn 2>/dev/null | grep -q "sudo openfortivpn-macosx"; then
        ALIAS_EXISTS=true
    fi
fi

if $ALIAS_FOUND; then
    print_warning "VPN alias/command already exists in: $FOUND_IN"
elif $COMMAND_FOUND; then
    print_warning "VPN command already exists: $FOUND_IN"
else
    echo "alias vpn='sudo openfortivpn-macosx'" >> ~/.zshrc
    print_success "Alias added to ~/.zshrc"
    ALIAS_ADDED=true
fi

echo -e "\n${GREEN}🎉 Installation complete!${NC}"
echo -e "${BLUE}Next steps:${NC}"
echo -e " • Edit ${YELLOW}'$CONFIG_PATH'${NC} with your VPN settings"

# Reload shell and show help if alias was added or already exists
if [[ "$ALIAS_ADDED" == true ]] || [[ "$ALIAS_EXISTS" == true ]]; then
    echo -e "\n${BLUE}VPN Help:${NC}"
    exec zsh -l -c "$MAIN_SCRIPT_PATH --help"
else
    echo -e " • Use ${YELLOW}'sudo openfortivpn-macosx'${NC} command to connect"
fi