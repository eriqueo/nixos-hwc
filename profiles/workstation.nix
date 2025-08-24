     { lib, ... }: {
       imports = [
         ../modules/infrastructure/gpu.nix
         ../modules/infrastructure/printing.nix
         ../modules/infrastructure/virtualization.nix
         ../modules/infrastructure/samba.nix
         ../modules/home/hyprland.nix
         ../modules/home/waybar.nix
         ../modules/home/apps.nix
         ../modules/home/cli.nix
         ../modules/home/development.nix
         ../modules/home/shell.nix
         ../modules/home/productivity.nix
         ../modules/home/login-manager.nix
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

         waybar = {
           enable = true;
           position = "top";
           modules = {
             showWorkspaces = true;
             showNetwork = true;
             showBattery = true;
           };
         };

         apps = {
           enable = true;
           browser = {
             firefox = true;
             chromium = false;
           };
           multimedia.enable = true;
           productivity.enable = true;
         };
       };

       # Workstation-specific user environment (extends base profile)
       hwc.home.groups.virtualization = true;  # Add virtualization access for VMs
       
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
       };

       # Infrastructure Services
       hwc.infrastructure = {
         printing.enable = true;
         virtualization.enable = true;
         samba.enableSketchupShare = true;
       };

       # Desktop Services  
       hwc.home.loginManager.enable = true;

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
     }
