# Waybar Part: Packages (Expanded)
# Defines all package dependencies for Waybar, its modules, and all helper scripts.
{ lib, pkgs, ... }:

with pkgs; [
  # Core Waybar package
  waybar

  # Dependencies for built-in modules
  pavucontrol
  swaynotificationcenter
  wlogout
  blueman
  networkmanagerapplet
  lm_sensors

  # Dependencies for custom script modules
  jq
  procps
  coreutils
  gawk
  ethtool
  iw
  mesa-demos
  acpi
  powertop
  speedtest-cli
  curl

  # GUI apps launched by scripts
  baobab
  kitty
  btop
  mission-center
  nvtopPackages.full
] ++ lib.optionals (pkgs.system == "x86_64-linux") [
  linuxPackages.nvidia_x11.settings
]
