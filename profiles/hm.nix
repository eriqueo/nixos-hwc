# profiles/hm.nix
{ ... }:
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.eric = { pkgs, lib, config, ... }: {
      imports = [
          
        ../modules/home/index.nix
      ];

      # carry over the machine’s HM specifics here
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
}
