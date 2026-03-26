#!/usr/bin/env bash
#
# Dotfiles Extractor
# Runs ON the NixOS machine to extract home-manager generated configs
# Creates a GNU Stow compatible directory structure
#
# Usage:
#   ./extract-dotfiles.sh \
#     --user eric \
#     --output ~/dotfiles-export
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
USER_NAME=""
OUTPUT_DIR=""
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Extract home-manager generated dotfiles and organize for GNU Stow.

OPTIONS:
    --user USERNAME      Username to extract dotfiles from
    --output PATH        Output directory for dotfiles
    --dry-run            Show what would be done without executing
    -h, --help           Show this help message

EXAMPLE:
    $0 \\
      --user eric \\
      --output ~/dotfiles-export

The output will be organized as Stow packages:
    dotfiles-export/
    ├── zsh/
    │   ├── .zshrc
    │   └── .config/starship.toml
    ├── neovim/
    │   └── .config/nvim/...
    └── hyprland/
        └── .config/hypr/...

To deploy on another machine:
    cd dotfiles-export && stow zsh neovim hyprland
EOF
    exit 1
}

log() {
    echo -e "${GREEN}[extract-dotfiles]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --user)
            USER_NAME="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Validate arguments
[[ -z "$USER_NAME" ]] && error "Missing required argument: --user"
[[ -z "$OUTPUT_DIR" ]] && error "Missing required argument: --output"

# Validate user exists
HOME_DIR=$(eval echo "~$USER_NAME")
[[ ! -d "$HOME_DIR" ]] && error "User home directory not found: $HOME_DIR"

log "User: $USER_NAME"
log "Home directory: $HOME_DIR"
log "Output directory: $OUTPUT_DIR"

if [[ "$DRY_RUN" == "true" ]]; then
    warn "DRY RUN MODE - No files will be copied"
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Define app configurations to extract
# Format: "package_name:config_paths:priority"
DOTFILE_APPS=(
    # Shell (priority: 100)
    "zsh:.zshrc,.zshenv,.config/zsh:100"
    "starship:.config/starship.toml:100"
    "tmux:.config/tmux,.tmux.conf:100"

    # Editor (priority: 100)
    "neovim:.config/nvim:100"

    # Terminal (priority: 90)
    "kitty:.config/kitty:90"

    # Desktop environment (priority: 90)
    "hyprland:.config/hypr,.local/state/hypr:90"
    "waybar:.config/waybar:90"
    "swaync:.config/swaync:90"

    # File managers (priority: 80)
    "yazi:.config/yazi:80"
    "thunar:.config/Thunar,.config/xfce4/helpers.rc:80"

    # Browsers (priority: 80)
    "chromium:.config/chromium:80"
    "librewolf:.librewolf:80"

    # Mail clients (priority: 80)
    "aerc:.config/aerc:80"
    "neomutt:.config/neomutt:80"
    "thunderbird:.thunderbird:80"
    "betterbird:.betterbird:80"

    # Productivity (priority: 70)
    "obsidian:.config/obsidian:70"

    # Security (priority: 90)
    "gpg:.gnupg:90"

    # Version control (priority: 100)
    "git:.gitconfig,.config/git:100"
)

TOTAL_APPS=${#DOTFILE_APPS[@]}
EXTRACTED_APPS=0
SKIPPED_APPS=0

log "Processing $TOTAL_APPS application configurations..."

for app_config in "${DOTFILE_APPS[@]}"; do
    IFS=':' read -r package_name config_paths priority <<< "$app_config"

    info "Processing: $package_name (priority: $priority)"

    # Create package directory
    package_dir="$OUTPUT_DIR/$package_name"

    # Check if any config paths exist
    found_any=false
    IFS=',' read -ra PATHS <<< "$config_paths"

    for rel_path in "${PATHS[@]}"; do
        source_path="$HOME_DIR/$rel_path"

        # Check if path exists (file or directory)
        if [[ -e "$source_path" || -L "$source_path" ]]; then
            found_any=true

            if [[ "$DRY_RUN" == "false" ]]; then
                # Create parent directory in package
                parent_dir=$(dirname "$rel_path")
                mkdir -p "$package_dir/$parent_dir"

                # Copy file/directory, following symlinks
                if [[ -L "$source_path" ]]; then
                    # Dereference symlink
                    real_path=$(readlink -f "$source_path")
                    if [[ -d "$real_path" ]]; then
                        cp -r "$real_path" "$package_dir/$rel_path"
                    else
                        cp "$real_path" "$package_dir/$rel_path"
                    fi
                    info "  Copied (dereferenced symlink): $rel_path"
                elif [[ -d "$source_path" ]]; then
                    cp -r "$source_path" "$package_dir/$rel_path"
                    info "  Copied directory: $rel_path"
                else
                    cp "$source_path" "$package_dir/$rel_path"
                    info "  Copied file: $rel_path"
                fi
            else
                echo "  Would copy: $source_path -> $package_dir/$rel_path"
            fi
        fi
    done

    if [[ "$found_any" == "true" ]]; then
        ((EXTRACTED_APPS++))
    else
        warn "  No configs found for $package_name, skipping"
        ((SKIPPED_APPS++))
    fi
done

log "Extraction complete!"
echo ""
echo "📦 Extracted: $EXTRACTED_APPS packages"
echo "⏭️  Skipped: $SKIPPED_APPS packages (no configs found)"
echo "📁 Output: $OUTPUT_DIR"

# Generate installation guide
INSTALL_GUIDE="$OUTPUT_DIR/INSTALL.md"

log "Generating installation guide: $INSTALL_GUIDE"

if [[ "$DRY_RUN" == "false" ]]; then
    cat > "$INSTALL_GUIDE" <<'INSTALL_HEADER'
# Dotfiles Installation Guide

This directory contains extracted home-manager configurations organized as GNU Stow packages.

## Prerequisites

```bash
# Install GNU Stow
sudo pacman -S stow  # Arch
sudo apt install stow  # Ubuntu/Debian
```

## Installation

### Quick Start (Install All)

```bash
cd dotfiles-export

# Stow all packages to $HOME
for package in */; do
  stow -v "$package"
done
```

### Selective Installation

```bash
# Install only specific packages
cd dotfiles-export

# Priority 1: Shell environment (install first!)
stow zsh starship tmux neovim git

# Priority 2: Desktop environment
stow hyprland waybar kitty swaync

# Priority 3: Applications
stow chromium librewolf aerc obsidian yazi
```

### Installation Order (Recommended)

1. **Shell** (highest priority, needed for terminal work):
   ```bash
   stow zsh starship tmux neovim git gpg
   ```

2. **Desktop** (if using graphical environment):
   ```bash
   stow hyprland waybar kitty swaync
   ```

3. **Applications** (as needed):
   ```bash
   stow chromium librewolf aerc neomutt yazi thunar obsidian
   ```

## How Stow Works

Stow creates symlinks from your `$HOME` directory to this dotfiles directory.

Example:
```bash
# Before stow
dotfiles-export/zsh/.zshrc

# After: stow zsh
~/.zshrc -> dotfiles-export/zsh/.zshrc
```

This allows you to:
- Keep dotfiles in version control
- Share dotfiles across machines
- Easily update configurations

## Verification

```bash
# Check what stow would do (dry run)
stow -n -v zsh

# Check existing symlinks
ls -la ~ | grep ' -> '
ls -la ~/.config | grep ' -> '
```

## Uninstallation

```bash
# Remove symlinks for a package
stow -D zsh

# Remove all packages
for package in */; do
  stow -D "$package"
done
```

## Package List

INSTALL_HEADER

    # List all packages sorted by priority
    for app_config in "${DOTFILE_APPS[@]}"; do
        IFS=':' read -r package_name config_paths priority <<< "$app_config"

        # Check if package was extracted
        if [[ -d "$OUTPUT_DIR/$package_name" ]]; then
            echo "- **$package_name** (priority: $priority)" >> "$INSTALL_GUIDE"
        fi
    done

    cat >> "$INSTALL_GUIDE" <<'INSTALL_FOOTER'

## Troubleshooting

### Conflict Error

If stow reports a conflict:
```
WARNING! stowing zsh would cause conflicts:
  * existing target is not owned by stow: .zshrc
```

**Solution:**
1. Back up the existing file:
   ```bash
   mv ~/.zshrc ~/.zshrc.backup
   ```

2. Run stow again:
   ```bash
   stow zsh
   ```

3. Merge any custom settings from the backup if needed.

### Broken Symlinks

```bash
# Find broken symlinks
find ~ -xtype l

# Remove broken symlinks
find ~ -xtype l -delete
```

### Re-stow All Packages

```bash
# This re-creates all symlinks
for package in */; do
  stow -R "$package"
done
```

## Version Control (Recommended)

```bash
# Initialize git repository
cd dotfiles-export
git init
git add .
git commit -m "Initial commit: Dotfiles from NixOS"

# Push to remote
git remote add origin <your-git-url>
git push -u origin main
```

## Machine-Specific Configurations

Some configurations may contain machine-specific paths or settings:
- Display names in Hyprland/Waybar
- Monitor configurations
- Hardware-specific keybindings

Review and adjust these after installation.

## Security Note

Some packages may contain sensitive information:
- **gpg**: Contains your GPG keys (handle with care!)
- **ssh**: If present, contains SSH keys
- **git**: May contain git credentials

Ensure proper file permissions:
```bash
chmod 700 ~/.gnupg
chmod 600 ~/.gnupg/*
```

INSTALL_FOOTER
fi

# Generate stow installation script
STOW_SCRIPT="$OUTPUT_DIR/stow-all.sh"

log "Generating stow installation script: $STOW_SCRIPT"

if [[ "$DRY_RUN" == "false" ]]; then
    cat > "$STOW_SCRIPT" <<'STOW_HEADER'
#!/usr/bin/env bash
#
# Stow All Dotfiles
# Installs all dotfile packages to $HOME using GNU Stow
#

set -euo pipefail

cd "$(dirname "$0")"

echo "Installing dotfiles to: $HOME"

# Priority 1: Shell environment
echo "==> Installing shell environment..."
for pkg in zsh starship tmux neovim git gpg; do
  if [[ -d "$pkg" ]]; then
    echo "  - $pkg"
    stow -v "$pkg"
  fi
done

# Priority 2: Desktop environment
echo "==> Installing desktop environment..."
for pkg in hyprland waybar kitty swaync; do
  if [[ -d "$pkg" ]]; then
    echo "  - $pkg"
    stow -v "$pkg"
  fi
done

# Priority 3: Applications
echo "==> Installing applications..."
for pkg in */; do
  pkg_name="${pkg%/}"

  # Skip if already installed
  if [[ "$pkg_name" =~ ^(zsh|starship|tmux|neovim|git|gpg|hyprland|waybar|kitty|swaync)$ ]]; then
    continue
  fi

  echo "  - $pkg_name"
  stow -v "$pkg_name"
done

echo "✅ Dotfiles installation complete!"
echo "Verify with: ls -la ~ | grep ' -> '"
STOW_HEADER

    chmod +x "$STOW_SCRIPT"
fi

echo ""
echo "📖 Installation guide: $INSTALL_GUIDE"
echo "🚀 Quick install script: $STOW_SCRIPT"
echo ""
log "Done! Transfer this directory to your Arch machine and run: ./stow-all.sh"
