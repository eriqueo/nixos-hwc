# profiles/hm.nix (Corrected)
{ ... }:
{
  home-manager = {

    extraSpecialArgs = {
      kernelPackages = config.boot.kernelPackages;
    };

    useGlobalPkgs = true;
    useUserPackages = true;

    users.eric = { pkgs, lib, ... }: {
      imports = [ ../modules/home/index.nix ];

      # All assignments must go inside the 'config' block.
   

        # This sets the state version for Home Manager.
        home.stateVersion = "24.05";
    
        # NEW: use features.* toggles (no old deck)
        features = {
          hyprland.enable = true;
          waybar.enable   = true;
          kitty.enable    = true;
          thunar.enable   = true;
          # add more per-app toggles here as you migrate them
        };

        # your theme/shell toggles moved from the machine file
        hwc.home.theme.palette = "deep-nord";
        hwc.home.shell = {
          enable = true;
          modernUnix = true;
          git.enable = true;
          zsh = {
            enable = true;
            starship = true;
            autosuggestions = true;
            syntaxHighlighting = true;
          };
        };
      };
    };
  };
}
