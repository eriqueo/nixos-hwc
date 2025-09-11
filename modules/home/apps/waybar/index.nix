# modules/home/apps/waybar/index.nix

# The function signature is `{ config, lib, pkgs, ... }`.
# We will access the special arguments via `config._module.args`.
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
    # THIS IS THE CORRECT, FINAL SYNTAX.
    # We access the special arguments passed to the module via `config._module.args`.
   nvidiaPackage
  ];

  # 2. Create the PATH string from the package list.
  scriptPathBin = lib.makeBinPath scriptPkgs;

  # These are your existing parts. This logic is correct.
  cfg       = config.features.waybar;
  theme     = import ./parts/theme.nix     { inherit config lib; };
  behavior  = import ./parts/behavior.nix  { inherit lib pkgs; };
  appearance= import ./parts/appearance.nix { inherit config lib pkgs; };
  packages  = import ./parts/packages.nix  { inherit lib pkgs; };
  scripts   = import ./parts/scripts.nix   { inherit pkgs lib; pathBin = scriptPathBin; };

in
{
  options.features.waybar.enable =
    lib.mkEnableOption "Enable Waybar";

  config = lib.mkIf enabled {
    # Include both the script dependencies and the generated script bins.
    home.packages = scriptPkgs ++ (lib.attrValues scripts);

    programs.waybar = {
      enable = true;
      package = pkgs.waybar;
      settings = behavior;
    };

    xdg.configFile."waybar/style.css".text = appearance;
  };
}
