# profiles/hm.nix (Final, Corrected Version with Function Signature)

# This is a NixOS module, so it must be a function that accepts arguments.
# The `config` argument here is the top-level NixOS system configuration.
{ config, pkgs, lib, ... }:

{
  # This is the top-level `home-manager` attribute for your NixOS configuration.
  home-manager = {
 

    useGlobalPkgs = true;
    useUserPackages = true;

    # This defines the configuration for the user 'eric'.
    users.eric = {
      # This block now only contains settings specific to the user 'eric'.
      imports = [ ../modules/home/index.nix ];

      home.stateVersion = "24.05";

      features = {
        hyprland.enable     = true;
        waybar.enable       = true;
        kitty.enable        = true;
        thunar.enable       = true;
        betterbird.enable   = true;
        chromium.enable     = true;
        librewolf.enable    = true;
        protonBridge.enable = true;
        obsidian.enable     = true;
        dunst.enable        = true;
        neomutt = {
            enable = true;
            accounts = {
              proton = {
                realName = "Eric";
                email = "eriqueo@proton.me";
                bridgeUsername = "eriqueo@proton.me";
                useAgenixPassword = true;
              };
              gmail-personal = {
                realName = "Eric O'Keefe";
                email = "eriqueokeefe@gmail.com";
                bridgeUsername = "eriqueokeefe@gmail.com";
                useAgenixPassword = false;
                bridgePasswordCommand = "cat /run/agenix/gmail-personal-password | tr -d '\\n'";
              };
              gmail-business = {
                realName = "Eric O'Keefe";
                email = "heartwoodcraftmt@gmail.com";
                bridgeUsername = "heartwoodcraftmt@gmail.com";
                useAgenixPassword = false;
                bridgePasswordCommand = "cat /run/agenix/gmail-business-password | tr -d '\\n'";
              };
            };
          };
      };

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
