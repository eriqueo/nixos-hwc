# DataX Time Tracker — Integration Reference
# These snippets go into your existing Waybar and Hyprland configs.

## ── Waybar (add to waybar/config.jsonc) ──────────────────

# Add "custom/dt" to your bar modules array, e.g.:
# "modules-right": ["custom/dt", "clock", "tray"]

# Then add this block:
#
# "custom/dt": {
#     "exec": "dt status --waybar",
#     "return-type": "json",
#     "interval": 30,
#     "on-click": "kitty --class dt-tui -e dt tui",
#     "tooltip": true
# }

## ── Waybar CSS (add to waybar/style.css) ─────────────────

# #custom-dt.active {
#     color: #a9b665;
#     font-weight: bold;
# }
# #custom-dt.idle {
#     color: #928374;
# }
# #custom-dt.stale {
#     color: #ea6962;
#     animation: blink 1s ease-in-out infinite;
# }
# @keyframes blink {
#     50% { opacity: 0.5; }
# }

## ── Hyprland (add to hyprland.conf) ──────────────────────

# Keybind to open TUI:
# bind = $mainMod, T, exec, kitty --class dt-tui -e dt tui

# Optional: window rule to float the TUI at a fixed size
# windowrulev2 = float, class:^(dt-tui)$
# windowrulev2 = size 800 500, class:^(dt-tui)$
# windowrulev2 = center, class:^(dt-tui)$

## ── NixOS module usage ───────────────────────────────────

# In your nixos-hwc configuration:
#
# imports = [ ./path/to/dt/nix/module.nix ];
#
# programs.dt = {
#   enable = true;
#   settings = {
#     name = "Eric O'Keefe";
#     rate = 40;
#     maxSessionHours = 10;
#   };
#   staleCheck.enable = true;
# };
