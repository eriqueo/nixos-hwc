# modules/home/apps/hyprland/default.nix
# TEMP COMPAT: forward old entrypoint → new index.nix
{ ... }: { imports = [ ./index.nix ]; }
