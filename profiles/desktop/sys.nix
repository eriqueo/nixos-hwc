# profiles/desktop/sys.nix — desktop role, NixOS lane
#
# Cross-domain bundle: system-level GUI support (audio, display, session).
# For machines with a screen and human interaction.
#
# REPLACES: profiles/session.nix
# USED BY: see the machines table in flake.nix

{ config, pkgs, lib, options, ... }:

{
  #==========================================================================
  # SYSTEM-LEVEL GUI SUPPORT — Audio, Display, Session
  # (HM wiring is flake-glue machinery, not menu — see mkNixos in flake.nix)
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

  # Thunar's admin:// backend needs system D-Bus/polkit registration and
  # GIO modules in the session environment, beyond the HM package install.
  services.gvfs.enable = true;
  # Permanent by design: stable already installs this wrapper with polkit;
  # newer NixOS modules expose a separate opt-in. Keep both role consumers valid.
  security.polkit = lib.optionalAttrs (options.security.polkit ? enablePkexecWrapper) {
    enablePkexecWrapper = true;
  };

  # nix-ld GUI libs (extends base role set for graphical machines)
  hwc.system.core.nixld.guiLibs.enable = true;
}
