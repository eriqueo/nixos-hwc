# profiles/desktop/sys.nix — desktop role, NixOS lane
#
# Cross-domain bundle: system-level GUI support (audio, display, session).
# For machines with a screen and human interaction.
#
# REPLACES: profiles/session.nix
# USED BY: laptop, xps (role list in flake.nix machines table)

{ config, pkgs, lib, ... }:

{
  #==========================================================================
  # HOME MANAGER — TRANSITIONAL (Phase B moves this bootstrap to flake glue)
  #==========================================================================
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = lib.mkDefault "hm-bak";
    users.eric.imports = [ ../base/home.nix ./home.nix ];
  };

  #==========================================================================
  # SYSTEM-LEVEL GUI SUPPORT — Audio, Display, Session
  #==========================================================================

  # Hardware services — audio, keyboard, bluetooth for interactive use
  hwc.system.hardware.enable = true;
  hwc.system.hardware.mouse.enable = true;

  # Session — display manager, sudo, lingering
  hwc.system.core.session = {
    enable = true;
    loginManager.enable = lib.mkDefault true;
    loginManager.autoLoginUser = lib.mkDefault "eric";
    sudo.enable = true;
    sudo.wheelNeedsPassword = false;
    linger.users = [ "eric" ];
  };

  # dconf required for GTK applications
  programs.dconf.enable = true;

  # nix-ld GUI libs (extends base role set for graphical machines)
  programs.nix-ld.libraries = with pkgs; [
    gtk3 pango cairo gdk-pixbuf atk
    libdrm mesa alsa-lib cups libpulseaudio
    libx11 libxcomposite libxcursor libxdamage libxext libxfixes
    libxi libxrandr libxrender libxtst libxcb libxscrnsaver
    at-spi2-atk at-spi2-core
    libgbm libxkbcommon
  ];
}
