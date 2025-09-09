# Co-located system lane for Hyprland (temporary compat options)
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.infrastructure.hyprlandTools;
in {
  # Provide the options that profiles/workstation.nix currently sets.
  options.hwc.infrastructure.hyprlandTools = {
    enable = lib.mkEnableOption "Hyprland system helper tools (compat)";
    notifications = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show notifications for Hyprland tool actions (compat).";
    };
  };

  # No-op implementation for now; we’re just keeping evaluation green.
  config = lib.mkIf cfg.enable {
    # later you can add environment.systemPackages, services, etc.
  };
}
