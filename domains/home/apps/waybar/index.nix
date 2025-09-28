# modules/home/apps/waybar/index.nix

# This module uses a special feature of NixOS flakes to get the
# pkgs set that corresponds to the final system configuration.
{ config, lib, pkgs,  ... }:

let
  enabled = config.hwc.home.apps.waybar.enable or false;

  # This is the key. We get the pkgs for the specific host system.
  # This `pkgs` will have the correct overlays, including nvidiaPackages.
 

  # 1. Define all dependencies for the scripts in one place.
    scriptPkgs = with pkgs; [
      coreutils gnugrep gawk gnused procps util-linux
      kitty wofi jq curl
      networkmanager iw ethtool
      libnotify mesa-demos nvtopPackages.full lm_sensors acpi powertop
      speedtest-cli hyprland
      baobab btop
      linuxPackages.nvidiaPackages.stable  # Note: no need for pkgs. prefix inside 'with pkgs'
    ];

  # 2. Create the PATH string from the package list.
  scriptPathBin = lib.makeBinPath scriptPkgs;

  # Your parts imports are correct.
  cfg       = config.hwc.home.apps.waybar;
  theme     = import ./parts/theme.nix     { inherit config lib; };
  behavior  = import ./parts/behavior.nix  { inherit lib pkgs; };
  appearance= import ./parts/appearance.nix { inherit config lib pkgs; theme = theme; };
  packages  = import ./parts/packages.nix  { inherit lib pkgs; };
  scripts   = import ./parts/scripts.nix   { inherit pkgs lib; pathBin = scriptPathBin; };

in
{
  #==========================================================================
  # OPTIONS 
  #==========================================================================
  imports = [ ./options.nix ];
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {
    # Include both the script dependencies and the generated script bins.
    home.packages = scriptPkgs ++ (lib.attrValues scripts);

    programs.waybar = {
      enable = true;
      package = pkgs.waybar;
      settings = behavior;
      systemd.enable = true;
    };

    xdg.configFile."waybar/style.css".text = appearance;
  };
}

  #==========================================================================
  # VALIDATION
  #==========================================================================