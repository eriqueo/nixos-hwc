# domains/system/core/polkit/index.nix
# PolicyKit configuration and directory management
{ config, lib, ... }:

let
  cfg = config.hwc.system.core.polkit;
in {
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.system.core.polkit = {
    enable = lib.mkEnableOption "polkit directory management";
    createMissingDirectories = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create missing polkit rule directories to silence warnings";
    };
  };

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
