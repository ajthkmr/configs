#!/usr/bin/env bash

# VS Code Setup Automation Script
# Detects VS Code forks and applies extensions and settings from extensionlist.txt

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTENSION_FILE="${SCRIPT_DIR}/extensionlist.txt"

# Global arrays for detected editors
declare -a DETECTED_EDITORS=()
declare -a DETECTED_NAMES=()

# Extensions list
declare -a EXTENSIONS=(
    "donjayamanne.python-extension-pack"
    "aaron-bond.better-comments"
    "charliermarsh.ruff"
    "PKief.material-icon-theme"
    "jdinhlife.gruvbox"
)

# Function to print colored messages
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_header() { echo -e "\n${MAGENTA}━━━ $1 ━━━${NC}\n"; }

# Function to detect installed editors
detect_editors() {
    print_header "Detecting VS Code Editors"

    # Check for each editor
    if command -v code &> /dev/null; then
        DETECTED_EDITORS+=("code")
        DETECTED_NAMES+=("Visual Studio Code")
        print_success "Found: Visual Studio Code (code)"
    fi

    if command -v code-insiders &> /dev/null; then
        DETECTED_EDITORS+=("code-insiders")
        DETECTED_NAMES+=("Visual Studio Code Insiders")
        print_success "Found: VS Code Insiders (code-insiders)"
    fi

    if command -v codium &> /dev/null; then
        DETECTED_EDITORS+=("codium")
        DETECTED_NAMES+=("VSCodium")
        print_success "Found: VSCodium (codium)"
    fi

    if command -v code-oss &> /dev/null; then
        DETECTED_EDITORS+=("code-oss")
        DETECTED_NAMES+=("Code-OSS")
        print_success "Found: Code-OSS (code-oss)"
    fi

    if command -v cursor &> /dev/null; then
        DETECTED_EDITORS+=("cursor")
        DETECTED_NAMES+=("Cursor")
        print_success "Found: Cursor (cursor)"
    fi

    if [ ${#DETECTED_EDITORS[@]} -eq 0 ]; then
        print_error "No VS Code editors found!"
        echo "Please install one of: code, code-insiders, codium, code-oss, or cursor"
        exit 1
    fi

    echo ""
}

# Function to get config directory for editor
get_config_dir() {
    local editor="$1"
    local config_base

    if [[ "$OSTYPE" == "darwin"* ]]; then
        config_base="$HOME/Library/Application Support"
    else
        config_base="$HOME/.config"
    fi

    case "$editor" in
        code)
            echo "$config_base/Code/User"
            ;;
        code-insiders)
            echo "$config_base/Code - Insiders/User"
            ;;
        codium)
            echo "$config_base/VSCodium/User"
            ;;
        code-oss)
            echo "$config_base/Code - OSS/User"
            ;;
        cursor)
            echo "$config_base/Cursor/User"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Function to detect package manager
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v brew &> /dev/null; then
        echo "brew"
    else
        echo "unknown"
    fi
}

# Function to install jq
install_jq() {
    local pkg_manager="$1"

    print_info "Installing jq temporarily..."

    case "$pkg_manager" in
        apt)
            sudo apt-get install -y -qq jq > /dev/null 2>&1
            ;;
        pacman)
            sudo pacman -Sy --noconfirm jq > /dev/null 2>&1
            ;;
        dnf)
            sudo dnf install -y -q jq > /dev/null 2>&1
            ;;
        yum)
            sudo yum install -y -q jq > /dev/null 2>&1
            ;;
        brew)
            brew install jq > /dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        print_success "jq installed successfully"
        return 0
    else
        print_error "Failed to install jq"
        return 1
    fi
}

# Function to uninstall jq
uninstall_jq() {
    local pkg_manager="$1"

    print_info "Removing temporarily installed jq..."

    case "$pkg_manager" in
        apt)
            sudo apt-get remove -y -qq jq > /dev/null 2>&1
            sudo apt-get autoremove -y -qq > /dev/null 2>&1
            ;;
        pacman)
            sudo pacman -Rns --noconfirm jq > /dev/null 2>&1
            ;;
        dnf)
            sudo dnf remove -y -q jq > /dev/null 2>&1
            ;;
        yum)
            sudo yum remove -y -q jq > /dev/null 2>&1
            ;;
        brew)
            brew uninstall jq > /dev/null 2>&1
            ;;
    esac

    if [ $? -eq 0 ]; then
        print_success "jq removed successfully"
    fi
}

# Function to install a single extension (used for parallel execution)
install_single_extension() {
    local editor="$1"
    local ext="$2"
    local installed_list="$3"

    # Check if already installed
    if echo "$installed_list" | grep -qi "^$ext$"; then
        echo "skipped:$ext"
        return 0
    fi

    # Try to install
    if $editor --install-extension "$ext" &> /dev/null; then
        echo "installed:$ext"
        return 0
    else
        echo "failed:$ext"
        return 1
    fi
}

# Function to install extensions
install_extensions() {
    local editor="$1"
    local editor_name="$2"

    print_header "Installing Extensions for $editor_name"

    # Cache installed extensions list (single call instead of one per extension)
    print_info "Checking currently installed extensions..."
    local installed_list=$($editor --list-extensions 2>/dev/null || echo "")

    # Create temp directory for parallel job results
    local temp_dir=$(mktemp -d)
    local pids=()

    # Start parallel installation
    print_info "Installing extensions in parallel..."
    for ext in "${EXTENSIONS[@]}"; do
        (install_single_extension "$editor" "$ext" "$installed_list" > "$temp_dir/$ext.result") &
        pids+=($!)
    done

    # Wait for all background jobs to complete
    for pid in "${pids[@]}"; do
        wait $pid 2>/dev/null || true
    done

    # Collect and display results
    local installed=0
    local skipped=0
    local failed=0

    for ext in "${EXTENSIONS[@]}"; do
        local result=$(cat "$temp_dir/$ext.result" 2>/dev/null || echo "failed:$ext")
        local status="${result%%:*}"

        echo -n "$ext... "
        case "$status" in
            installed)
                print_success "installed"
                installed=$((installed + 1))
                ;;
            skipped)
                print_warning "already installed"
                skipped=$((skipped + 1))
                ;;
            failed)
                print_error "failed"
                failed=$((failed + 1))
                ;;
        esac
    done

    # Cleanup temp directory
    rm -rf "$temp_dir"

    echo ""
    print_info "Summary: ${GREEN}$installed${NC} installed, ${YELLOW}$skipped${NC} skipped, ${RED}$failed${NC} failed"
}

# Function to configure settings
configure_settings() {
    local editor="$1"
    local editor_name="$2"
    local config_dir="$(get_config_dir "$editor")"
    local settings_file="$config_dir/settings.json"

    print_header "Configuring Settings for $editor_name"

    # Create config directory if it doesn't exist
    if [ ! -d "$config_dir" ]; then
        print_info "Creating config directory: $config_dir"
        mkdir -p "$config_dir"
    fi

    # Settings to apply
    local settings_json=$(cat <<'EOF'
{
  "workbench.colorTheme": "Gruvbox Dark Hard",
  "workbench.iconTheme": "material-icon-theme",
  "material-icon-theme.folders.associations": {
    "venv": "environment",
    "references": "docs",
    "modeling": "generator"
  },
  "editor.formatOnSave": true,
  "[python]": {
    "editor.formatOnType": true,
    "editor.defaultFormatter": "charliermarsh.ruff"
  },
  "jupyter.interactiveWindow.textEditor.executeSelection": true
}
EOF
)

    # Check if settings file exists
    if [ -f "$settings_file" ]; then
        print_info "Existing settings.json found"

        # Backup existing settings
        cp "$settings_file" "${settings_file}.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "Backup created"

        # Check if jq is available for JSON merging
        local jq_was_installed=false
        local jq_temp_installed=false

        if command -v jq &> /dev/null; then
            jq_was_installed=true
            print_info "Using existing jq installation"
        else
            # jq not found, try to install it temporarily
            local pkg_manager=$(detect_package_manager)

            if [ "$pkg_manager" != "unknown" ]; then
                if install_jq "$pkg_manager"; then
                    jq_temp_installed=true
                else
                    print_error "Could not install jq automatically"
                    print_warning "Settings merge skipped"
                    return 1
                fi
            else
                print_error "No supported package manager found"
                print_warning "Settings merge skipped"
                return 1
            fi
        fi

        # Merge settings
        print_info "Merging with existing settings..."
        local merged_json=$(jq -s '.[0] * .[1]' "$settings_file" <(echo "$settings_json"))
        echo "$merged_json" > "$settings_file"
        print_success "Settings merged successfully"

        # Uninstall jq if we installed it temporarily
        if [ "$jq_temp_installed" = true ]; then
            uninstall_jq "$pkg_manager"
        fi
    else
        print_info "Creating new settings.json"
        echo "$settings_json" > "$settings_file"
        print_success "Settings file created"
    fi
}

# Main function
main() {
    print_header "VS Code Setup Automation"

    # Check if extension file exists
    if [ ! -f "$EXTENSION_FILE" ]; then
        print_error "Extension list file not found: $EXTENSION_FILE"
        exit 1
    fi

    # Detect editors
    detect_editors

    local num_editors=${#DETECTED_EDITORS[@]}

    # If only one editor, use it automatically
    if [ $num_editors -eq 1 ]; then
        selected_editor="${DETECTED_EDITORS[0]}"
        selected_name="${DETECTED_NAMES[0]}"
        print_info "Automatically selecting: $selected_name"
    else
        # Show selection menu
        echo -e "${CYAN}Select an editor:${NC}"
        for i in "${!DETECTED_EDITORS[@]}"; do
            echo "  $((i+1)). ${DETECTED_NAMES[$i]}"
        done
        echo ""

        # Get user selection
        while true; do
            read -p "Enter selection (1-$num_editors): " selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "$num_editors" ]; then
                break
            else
                print_error "Invalid selection. Please enter a number between 1 and $num_editors"
            fi
        done

        selected_editor="${DETECTED_EDITORS[$((selection-1))]}"
        selected_name="${DETECTED_NAMES[$((selection-1))]}"
        print_success "Selected: $selected_name"
    fi

    echo ""

    # Install extensions
    install_extensions "$selected_editor" "$selected_name"

    echo ""

    # Configure settings
    configure_settings "$selected_editor" "$selected_name"

    # Final summary
    print_header "Setup Complete!"
    print_success "Extensions have been installed"
    print_success "Settings have been configured"
    print_info "You may need to restart $selected_name for all changes to take effect"

    echo ""
}

# Run main function
main "$@"
