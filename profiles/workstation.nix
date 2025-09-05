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

       # Home-Manager configuration now handled in machines/laptop/home.nix

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
