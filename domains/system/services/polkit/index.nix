# POLKIT - PolicyKit configuration and directory management
{ config, lib, ... }:

let
  cfg = config.hwc.system.services.polkit;
in {
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ../options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = lib.mkIf cfg.createMissingDirectories [
      "d /usr/local/share/polkit-1/rules.d 0755 root root -"
      "d /run/polkit-1/rules.d             0755 root root -"
    ];

    security.polkit.enable = true;
  };
}
