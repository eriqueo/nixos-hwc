# Hyprland Monoliths Archive

## Purpose
This archive preserves the original working monolithic Hyprland configuration files that were refactored into the Charter v4 compliant parts-based structure.

## Files Archived

### hyprland.nix (430 lines)
- **Original location**: `/etc/nixos/hosts/laptop/modules/hyprland.nix`
- **Functionality**: Complete working Hyprland configuration with 139 keybindings
- **Contents**:
  - Monitor setup: `eDP-1,2560x1600@165,0x0,1` + `DP-1,1920x1080@60,2560x0,1`
  - 20 workspace assignments (1-8 → eDP-1, 11-18 → DP-1)
  - 39 windowrulev2 rules for browsers, dialogs, floating windows, opacity, PiP
  - Complete styling: gruvbox colors, blur, animations, decorations
  - All 139 keybindings across 10 categories
  - 2 embedded tools: `workspace-overview`, `monitor-toggle`
  - Hyprpaper wallpaper configuration

### startup.nix (320 lines)
- **Original location**: `/etc/nixos/hosts/laptop/modules/startup.nix`
- **Functionality**: Session startup orchestration and system management
- **Contents**:
  - `hypr-startup` script (application launching with workspace assignment)
  - `workspace-manager` script (enhanced workspace navigation)
  - `app-launcher` script (smart application launching)
  - `system-health-checker` script (resource monitoring)
  - SystemD service integration for health monitoring

## Refactor Details

### Date
2025-09-02

### Charter v4 Migration
These monoliths were decomposed following Charter v4 preserve-first principles:

**From**: 2 monolithic files (750 total lines)
**To**: Structured domain separation:
- **Infrastructure**: `modules/infrastructure/hyprland-tools.nix` (6 tools with dual naming)
- **Home UI**: `modules/home/hyprland/default.nix` + 6 parts files
- **Global theming**: `modules/home/theme/palettes/` + `adapters/`

### Functionality Preservation
- **100% keybinding preservation**: All 139 keybindings migrated exactly
- **Monitor layout**: Identical dual-monitor setup preserved
- **Window rules**: All 39 windowrulev2 rules preserved
- **Styling**: Exact gruvbox material theme colors preserved
- **Tool integration**: All embedded scripts extracted to infrastructure

### New Structure Benefits
- **User-tweakable**: Edit keybindings in `parts/keybindings.nix`
- **Theme system**: Global palette → adapter → UI settings
- **Charter compliant**: Clean domain boundaries (Home=UI, Infra=tools)
- **Single source of truth**: One place per UI aspect

## Tool Mapping
| Original Tool | Infrastructure Export | Usage |
|---------------|----------------------|-------|
| `workspace-overview` | `hyprland-workspace-overview` | Workspace selection with wofi |
| `monitor-toggle` | `hyprland-monitor-toggle` | External monitor positioning |
| `hypr-startup` | `hyprland-startup` | Session application launching |
| `workspace-manager` | `hyprland-workspace-manager` | Enhanced workspace navigation |
| `app-launcher` | `hyprland-app-launcher` | Smart app launching with focus |
| `system-health-checker` | `hyprland-system-health-checker` | Resource monitoring with notifications |

## Validation
The refactored structure was validated to ensure 100% functional parity with these archived monoliths. Any behavior differences from the original monoliths should be considered regressions and fixed.

## Recovery Instructions
If needed, these monoliths can be restored by:
1. Copying files back to their original locations
2. Updating profile imports to reference the monolith paths
3. Removing the parts-based structure

However, the Charter v4 compliant structure should be preferred for maintainability and domain separation.