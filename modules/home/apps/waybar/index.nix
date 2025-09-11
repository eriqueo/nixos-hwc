# modules/home/apps/waybar/index.nix
{ config, lib, pkgs, ... }:
let
  enabled = config.features.waybar.enable or false;

  # 1. Define all dependencies for the scripts in one place.
  scriptPkgs = with pkgs; [
    coreutils gnugrep gawk gnused procps util-linux
    kitty wofi jq curl
    networkmanager iw ethtool
    libnotify mesa-demos nvtopPackages.full lm_sensors acpi powertop
    speedtest-cli hyprland 
    baobab btop
  ] ++ [
    # This is the special sauce: get the NVIDIA package from the NixOS config.
    # This requires Step 3 below.
    kernelPackages.nvidiaPackages.stable  
  ];

  # 2. Create the PATH string from the package list.
  scriptPathBin = lib.makeBinPath scriptPkgs;
  cfg       = config.features.waybar;
  theme     = import ./parts/theme.nix     {inherit config lib; };
  behavior  = import ./parts/behavior.nix  { inherit lib pkgs; };
  appearance= import ./parts/appearance.nix { inherit config lib pkgs; };
  packages  = import ./parts/packages.nix  { inherit lib pkgs; };
  scripts   = import ./parts/scripts.nix   { inherit  pkgs lib; pathBin = scriptPathBin; };  # <— NEW: list of bins
in
{
  options.features.waybar.enable =
    lib.mkEnableOption "Enable Waybar";

  # remove: imports = [ ./parts/scripts.nix ... ];

  config = lib.mkIf enabled {
    # Include both regular packages and the generated script bins
    home.packages = scriptPkgs ++ (lib.attrValues scripts);

    programs.waybar = {
      enable = true;
      package = pkgs.waybar;
      settings = behavior;
    };

    xdg.configFile."waybar/style.css".text = appearance;
  };
}
