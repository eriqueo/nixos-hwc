# profiles/session.nix — Human-facing workstation profile
#
# Cross-domain bundle: home (GUI) + audio + display + theme
# For machines with a screen and human interaction.
#
# REPLACES: home.nix
# USED BY: laptop, xps (full workstations)
# NOT USED BY: server (headless), firestick/gaming (custom HM in machine config)

{ config, pkgs, lib, ... }:

{
  #==========================================================================
  # HOME MANAGER — Full GUI workstation setup
  #==========================================================================
  # HM config extracted to profiles/home-session.nix (shared with standalone homeConfigurations)
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = lib.mkDefault "hm-bak";
    users.eric = import ./home-session.nix;
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
}
