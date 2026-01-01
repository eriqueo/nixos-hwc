{ config, pkgs, lib, ... }:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.eric = {
      imports = [
        ../../domains/home/index.nix
      ];

      home.stateVersion = "24.05";

      # Minimal app selection - gaming focused
      hwc.home = {
        # Core utilities
        environment.shell.enable = true;
        apps.kitty.enable = true;      # Terminal for troubleshooting
        apps.yazi.enable = true;       # File browser for ROM management

        # Gaming apps - COMMENTED OUT until modules are integrated
        # Will be enabled once retroarch, 86box, and mpv modules are added
        # apps.retroarch = {
        #   enable = true;
        #   cores = [
        #     "snes9x"           # Super Nintendo
        #     "genesis-plus-gx"  # Genesis/Mega Drive
        #     "beetle-psx-hw"    # PlayStation
        #     "mupen64plus"      # Nintendo 64
        #     "mame"             # Arcade
        #   ];
        #   theme = "ozone";     # Controller-friendly UI
        #   fullscreen = true;
        #   videoDriver = "vulkan";  # Or "gl" depending on SBC GPU
        # };
        #
        # apps."86box" = {
        #   enable = true;
        #   enableNetworking = false;  # PCap not needed initially
        # };
        #
        # # Media playback
        # apps.mpv.enable = true;

        # Minimal desktop environment
        apps.hyprland.enable = true;
        # NOTE: Hyprland config is managed by the hyprland module itself
        # Auto-launch of retroarch will be configured when that module is integrated
        # via parts/session.nix in the hyprland module
      };

      # Override profile defaults - disable unwanted apps
      # Note: Hyprland forces waybar and swaync, we'll allow that dependency
      hwc.home = {
        # Disable mail (all apps)
        mail.enable = false;

        # Disable development tools
        development.enable = false;
      };

      hwc.home.apps = {
        # Explicitly disable browsers (keep lightweight terminal-based tools)
        chromium.enable = false;
        librewolf.enable = false;
      };
    };
  };
}
