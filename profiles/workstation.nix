     { lib, ... }: {
       imports = [
         ../modules/infrastructure/gpu.nix
         ../modules/desktop/hyprland.nix
         ../modules/desktop/waybar.nix
         ../modules/desktop/apps.nix
         ../modules/home/cli.nix
         ../modules/home/development.nix
         ../modules/home/shell.nix
         ../modules/home/productivity.nix
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

       # Enable home environment
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


       # Sound
       security.rtkit.enable = true;
       services.pipewire = {
         enable = true;
         alsa.enable = true;
         alsa.support32Bit = true;
         pulse.enable = true;
       };

       # Networking
       networking.networkmanager.enable = true;
     }
