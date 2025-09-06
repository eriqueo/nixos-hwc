# Waybar Part: Packages
# Defines all package dependencies for Waybar and its custom scripts.
{ lib, pkgs, ... }:

with pkgs; [
  # Core Waybar package
  waybar

  # Dependencies for Waybar modules
  pavucontrol
  swaynotificationcenter
  wlogout
  baobab
  networkmanagerapplet
  blueman
  nvtopPackages.full
  mission-center
  btop
  lm_sensors
  ethtool
  iw
  mesa-demos

  # Portal packages (often needed for DE features)
  xdg-desktop-portal-gtk
  xdg-desktop-portal-hyprland
]
