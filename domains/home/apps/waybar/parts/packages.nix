{ lib, pkgs, ... }:
{
  runtime = with pkgs; [
    coreutils gnugrep gawk gnused procps util-linux
    kitty wofi jq curl
    networkmanager iw ethtool
    libnotify mesa-demos nvtopPackages.full lm_sensors acpi powertop
    speedtest-cli hyprland
    baobab btop brightnessctl
    power-profiles-daemon
  ];

  interactive = with pkgs; [
    pavucontrol swaynotificationcenter wlogout blueman
    networkmanagerapplet mission-center
  ] ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
    pkgs.linuxPackages.nvidia_x11.settings
  ];
}
