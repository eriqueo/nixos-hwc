{ config, pkgs, lib, ... }:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.eric = {
      imports = [
        ../../domains/home
      ];

      home.stateVersion = "24.05";

      # Minimal app selection - gaming focused
      hwc.home = {
        # Core utilities
        shell.enable = true;
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
        apps.hyprland = {
          enable = true;
          # Custom config will auto-launch RetroArch when module is integrated
          # For now, just minimal Hyprland setup
          extraConfig = ''
            # Minimal keybinds (troubleshooting only)
            bind = SUPER, Q, killactive
            bind = SUPER, M, exit
            bind = SUPER, Return, exec, kitty

            # Single workspace
            workspace = 1

            # TODO: Add when retroarch module is integrated:
            # exec-once = retroarch --menu-driver=ozone
          '';
        };
      };

      # Explicitly disable all non-gaming apps
      hwc.home.apps = {
        # Browsers
        chromium.enable = false;
        librewolf.enable = false;

        # Mail
        aerc.enable = false;
        betterbird.enable = false;
        neomutt.enable = false;
        proton-mail.enable = false;

        # Productivity
        obsidian.enable = false;
        onlyoffice-desktopeditors.enable = false;
        slack.enable = false;

        # Heavy desktop components
        waybar.enable = false;
        swaync.enable = false;

        # Development tools
        codex.enable = false;
        gemini-cli.enable = false;
        google-cloud-sdk.enable = false;
        opencode.enable = false;

        # Utilities
        bottles-unwrapped.enable = false;
        localsend.enable = false;
        wasistlos.enable = false;
        ipcalc.enable = false;
        thunar.enable = false;

        # Security
        gpg.enable = false;
        proton-authenticator.enable = false;
        proton-pass.enable = false;

        # Automation
        n8n.enable = false;
      };
    };
  };
}
