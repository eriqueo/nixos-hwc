     { config, lib, ... }: {
       imports = [
         # System foundation modules (Charter v4 compliant)
         ../modules/system/users.nix
         ../modules/system/security/sudo.nix
         ../modules/system/base-packages.nix
         
         # Infrastructure capabilities
         ../modules/infrastructure/gpu.nix
         ../modules/infrastructure/waybar-hardware-tools.nix
         # ../modules/infrastructure/waybar-system-tools.nix (consolidated)
         ../modules/infrastructure/user-services.nix
         ../modules/infrastructure/user-hardware-access.nix
         ../modules/infrastructure/printing.nix
         ../modules/infrastructure/virtualization.nix
         ../modules/infrastructure/samba.nix

         # System packages
         ../modules/system/desktop-packages.nix  # Desktop system packages
         ../modules/system/audio.nix             # Audio system

         # NixOS-level home modules (SSH, etc.)
         ../modules/home/core/login-manager.nix
         ../modules/home/apps/apps.nix        # Apps uses environment.systemPackages - NixOS level
         # ../modules/home/development.nix # Development now handled in Home Manager section
         ../modules/home/core/input.nix       # Input config for keyboards - NixOS level
         
         # Hyprland system tools for cross-stream integration
         ../modules/home/apps/hyprland/parts/system.nix
       ];

       # Phase 3: Centralized Home-Manager configuration
       home-manager = {
         useGlobalPkgs = true;
         extraSpecialArgs = { nixosConfig = config; };
         # Prevent activation failures from file conflicts
         backupFileExtension = "hm-bak";
         users.eric = {
           imports = [
             # True Home-Manager modules (use home.packages, programs.*, etc.)
             ../modules/home/apps/hyprland/default.nix
             ../modules/home/apps/betterbird/default.nix  # Charter v5 email client
             ../modules/home/environment/shell.nix
             ../modules/home/environment/productivity.nix
             ../modules/home/environment/development.nix
            ../modules/home/apps/kitty.nix
            ../modules/home/apps/thunar.nix
             ../modules/schema/home/waybar.nix
             # Waybar with all tools - Charter v4 compliant
             ../modules/home/apps/waybar/default.nix
           ];
           
           # Hyprland configuration now handled by direct module import
           
           # Productivity configuration (pure Home-Manager)
           hwc.home.productivity = {
             enable = true;
             notes.obsidian = true;
             browsers.firefox = true;
             office.libreoffice = true;
             # communication.thunderbird = true;  # Now managed by betterbird module
           };
           
           # Shell configuration (consolidated shell + CLI)
           hwc.home.shell = {
             enable = true;
             modernUnix = true;
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
           
           # Development configuration (enhanced with git and tools)
           hwc.home.development = {
             enable = true;
             git = {
               enable = true;
               userName = "Eric";
               userEmail = "eric@hwc.moe";
             };
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
           
           # Waybar configuration (pure Home-Manager)
           hwc.home.waybar = {
             enable = true;
             position = "top";
             modules = {
               workspaces.enable = true;
               network.enable = true;
               battery.enable = true;
             };
           };
           
           home.stateVersion = "24.05";
         };
       };

       # Hyprland system tools configuration
       hwc.infrastructure.hyprlandTools = {
         enable = true;
         notifications = true;
       };

       # Consolidated hwc.home configuration
       hwc.home = {
         # Desktop applications (NixOS level)
         apps = {
           enable = true;
           browser = {
             firefox = true;
             chromium = true;
           };
           multimedia.enable = true;
           productivity.enable = true;
         };

         # Input device configuration
         input = {
           enable = true;
           keyboard = {
             enable = true;
             universalFunctionKeys = true;  # Consistent F-keys across all keyboards
           };
         };
         
         # Login manager configuration
         loginManager.enable = true;
         # homeManager configuration now handled centrally via HM imports above

         # Development configuration moved to Home Manager section above
         # This ensures proper integration with user environment



       };

       # Infrastructure Services
       hwc.infrastructure = {
         printing.enable = true;
         virtualization.enable = true;
         samba.enableSketchupShare = true;
         # Waybar infrastructure tools
         waybarHardwareTools.enable = true;
         # waybarSystemTools.enable = true; (consolidated into waybarHardwareTools)
         
         # Hyprland tools now integrated into home domain parts
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

       # System configuration (Charter v4 foundation modules)
       hwc.system.users.enable = true;
       hwc.system.security.sudo.enable = true;
       hwc.system.basePackages.enable = true;
       hwc.system.desktop.enable = true;        # Enable desktop system packages
       
       # XDG Portal configuration moved to modules/system/audio.nix

       # Workstation filesystem structure
       hwc.filesystem.userDirectories.enable = true;  # PARA structure for productivity

       # Sound - moved to modules/system/audio.nix
       hwc.system.audio.enable = true;

       # Workstation-specific networking (SSH X11 forwarding for remote development)
       hwc.networking.ssh.x11Forwarding = true;

       # Home-Manager configuration now centralized above
}
