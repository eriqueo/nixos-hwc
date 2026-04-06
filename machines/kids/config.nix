# machines/kids/config.nix
#
# MACHINE: HWC-KIDS — Retro gaming station for kids (old MacBook Pros)
# Lean setup: browser, eXoDOS, RetroArch, Hyprland. No dev/AI/work bloat.

{ lib, pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./home.nix
    ../../profiles/gaming.nix
  ];

  networking.hostName = "hwc-kids";
  system.stateVersion = "24.05";

  hwc.system.apps.hyprland.enable = true;
  hwc.system.apps.waybar.enable = true;

  # Flatpak: required for eXoDOS emulator bundles (DOSBox, ScummVM, etc.)
  services.flatpak.enable = true;
  environment.sessionVariables.XDG_DATA_DIRS = [
    "/var/lib/flatpak/exports/share"
    "$HOME/.local/share/flatpak/exports/share"
  ];

  # nix-ld: allows pre-compiled binaries (exogui Electron frontend)
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    glib glibc gtk3 pango cairo gdk-pixbuf atk
    nss nspr dbus expat libdrm mesa
    alsa-lib cups libpulseaudio
    libX11 libXcomposite libXcursor libXdamage libXext libXfixes
    libXi libXrandr libXrender libXtst libxcb libxscrnsaver
    at-spi2-atk at-spi2-core
    libgbm libxkbcommon
  ];
}
