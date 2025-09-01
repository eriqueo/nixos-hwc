     { lib, ... }: {
       imports = [
         # Infrastructure capabilities
         ../modules/infrastructure/gpu.nix
         ../modules/infrastructure/waybar-gpu-tools.nix
         ../modules/infrastructure/waybar-system-tools.nix
         ../modules/infrastructure/user-services.nix
         ../modules/infrastructure/user-hardware-access.nix
         ../modules/infrastructure/printing.nix
         ../modules/infrastructure/virtualization.nix
         ../modules/infrastructure/samba.nix

         # System packages
         ../modules/system/desktop-packages.nix  # Desktop system packages

         # Home environment (NixOS-level modules)
         ../modules/home/hyprland.nix
         ../modules/home/apps.nix
         ../modules/home/cli.nix
         ../modules/home/development.nix
         ../modules/home/shell.nix
         ../modules/home/productivity.nix
         ../modules/home/login-manager.nix
         ../modules/home/input.nix  # Universal input device configuration
         
         # Schema modules (define options)
         ../modules/schema/home/waybar.nix
       ];

       # Enable desktop environment
       hwc.desktop = {
         hyprland = {
           enable = true;
           nvidia = true;  # Enable NVIDIA optimizations
           keybinds.modifier = "SUPER";
           monitor = {
             primary = "eDP-1,2560x1600@165,0x0,1.566667";
             external = "DP-1,3840x2160@60,1638x0,2";
           };
           startup = [
             "waybar"
             "hyprpaper"
             "hypridle"
           ];
         };

         apps = {
           enable = true;
           browser = {
             firefox = true;
             chromium = true;
           };
           multimedia.enable = true;
           productivity.enable = true;
         };
       };

       # Workstation-specific user environment (extends base profile)
       hwc.home.groups.virtualization = true;  # Add virtualization access for VMs

       # Universal input device configuration
       hwc.home.input = {
         enable = true;
         keyboard = {
           enable = true;
           universalFunctionKeys = true;  # Consistent F-keys across all keyboards
         };
       };

       # Enable CLI tools
       hwc.home = {
         cli = {
           enable = true;
           modernUnix = true;
           git = {
             enable = true;
             userName = "Eric";
             userEmail = "eric@hwc.moe";
           };
         };

         development = {
           enable = true;
           editors = {
             neovim = true;
             micro = true;
           };
           languages = {
             nix = true;
             python = true;
             rust = false;
             javascript = false;
           };
           containers = true;
         };

         shell = {
           enable = true;
           zsh = {
             enable = true;
             starship = true;
             plugins = {
               autosuggestions = true;
               syntaxHighlighting = true;
             };
           };
           tmux.enable = true;
         };

         productivity = {
           enable = true;
           notes.obsidian = true;
           browsers.firefox = true;
           office.libreoffice = true;
           communication.thunderbird = true;
         };

         # Waybar configuration (home environment)
         waybar = {
           enable = true;
           position = "top";
           modules = {
             workspaces.enable = true;
             network.enable = true;
             battery.enable = true;
           };
         };
       };

       # Infrastructure Services
       hwc.infrastructure = {
         printing.enable = true;
         virtualization.enable = true;
         samba.enableSketchupShare = true;
         # Waybar infrastructure tools
         waybarGpuTools.enable = true;
         waybarSystemTools.enable = true;
         # User system services  
         userServices.enable = true;
         
         # User hardware access (based on workstation needs)
         userHardwareAccess = {
           enable = true;
           groups = {
             media = true;          # Desktop workstation needs video/audio/render
             development = true;    # Docker/Podman for containerized development
             virtualization = true; # VMs enabled for workstation
             hardware = true;       # Input devices and serial access
           };
         };
       };

       hwc.home.loginManager.enable = true;  # Desktop Services
       hwc.system.desktop.enable = true;        # Enable desktop system packages


       # Workstation filesystem structure
       hwc.filesystem.userDirectories.enable = true;  # PARA structure for productivity

       # Sound
       security.rtkit.enable = true;
       services.pipewire = {
         enable = true;
         alsa.enable = true;
         alsa.support32Bit = true;
         pulse.enable = true;
       };

       # Workstation-specific networking (SSH X11 forwarding for remote development)
       hwc.networking.ssh.x11Forwarding = true;

       #============================================================================
       # HOME-MANAGER SYSTEM-LEVEL CONFIGURATION
       # This is the root fix. It activates Home Manager for the specified user.
       #============================================================================
       home-manager.useGlobalPkgs = true;
       home-manager.users.eric = {
          imports = [
            # Waybar with all tools - Charter v4 compliant
            ../modules/home/waybar/default.nix
          ];

          home.stateVersion = "24.05";

        };
}
