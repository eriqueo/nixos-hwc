# Waybar Tool Mapping - Complete Reference

## Custom Block → Binary Mapping

| Custom Block | UI Command | Infrastructure Binary | Wrapper Binary | Function |
|--------------|------------|---------------------|----------------|-----------|
| `custom/gpu` | `gpu-status` | `waybar-gpu-status` | `gpu-status` | GPU monitoring with power/temp |
| `custom/gpu` (click) | `gpu-toggle` | `waybar-gpu-toggle` | `gpu-toggle` | GPU mode switching |  
| `custom/gpu` (right-click) | `gpu-menu` | `waybar-gpu-menu` | `gpu-menu` | GPU options menu |
| `custom/disk` (click) | `disk-usage-gui` | `waybar-disk-usage-gui` | `disk-usage-gui` | Launch baobab disk analyzer |
| `custom/network` | `network-status` | `waybar-network-status` | `network-status` | WiFi/ethernet status with quality |
| `custom/network` (click) | `network-settings` | `waybar-network-settings` | `network-settings` | Network management menu |
| `custom/battery` | `battery-health` | `waybar-battery-health` | `battery-health` | Battery status with health info |
| `custom/battery` (click) | `power-settings` | `waybar-power-settings` | `power-settings` | Power management GUI |
| `memory` (click) | `system-monitor` | `waybar-system-monitor` | `system-monitor` | Launch btop in terminal |
| `cpu` (click) | `system-monitor` | `waybar-system-monitor` | `system-monitor` | Launch btop in terminal |
| `temperature` (click) | `sensor-viewer` | `waybar-sensor-viewer` | `sensor-viewer` | Launch sensor monitoring |
| `hyprland/workspaces` (nav) | `workspace-switcher` | `waybar-workspace-switcher` | `workspace-switcher` | Enhanced workspace navigation |
| (Background) | `resource-monitor` | `waybar-resource-monitor` | `resource-monitor` | System resource monitoring |
| (Background) | `gpu-launch` | `waybar-gpu-launch` | `gpu-launch` | GPU-aware application launcher |

## Tool Count Summary
- **Total Infrastructure Tools**: 13 binaries (all prefixed `waybar-*`)
- **Total Wrapper Tools**: 13 binaries (unprefixed for UI compatibility)  
- **Custom Blocks with Actions**: 8 interactive blocks
- **Background/Helper Tools**: 2 utilities

## Naming Convention
- **Canonical**: `waybar-<tool-name>` (infrastructure domain)
- **Wrapper**: `<tool-name>` (temporary compatibility shim)
- **Zero drift**: UI commands exactly match wrapper names

## Migration Strategy
1. **Current phase**: UI uses unprefixed commands, infrastructure provides both
2. **Post-acceptance**: Remove wrappers, update UI to canonical `waybar-*` names
3. **Validation**: All 13 tools callable from UI, zero name mismatches