# domains/home/apps/wayvnc/index.nix
# Wayland VNC server with optional virtual output for second-screen setups.

{ config, lib, pkgs, osConfig, ... }:

let
  cfg = config.hwc.home.apps.wayvnc;

  baseSettings =
    {
      address = cfg.network.address;
      port = cfg.network.port;
    }
    // (lib.optionalAttrs cfg.virtualOutput.enable { output = cfg.virtualOutput.name; });

  # Create a headless output in Hyprland if missing, then set its mode/position.
  ensureVirtualOutput = pkgs.writeShellScript "wayvnc-ensure-virtual-output" ''
    set -euo pipefail
    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"

    OUT="${cfg.virtualOutput.name}"
    MODE="${cfg.virtualOutput.mode}"
    POS="${cfg.virtualOutput.position}"

    # Create headless output if not present
    if ! "$HYPRCTL" -j monitors | "$JQ" -e ".[] | select(.name == \"$OUT\")" >/dev/null 2>&1; then
      "$HYPRCTL" output create headless
    fi

    # Configure resolution/position
    "$HYPRCTL" keyword monitor "${cfg.virtualOutput.name},$MODE,$POS,1"
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.jq pkgs.hyprland ];

    services.wayvnc = {
      enable = true;
      autoStart = cfg.autoStart;
      settings = lib.mkMerge [
        baseSettings
        cfg.settings
      ];
    };

    systemd.user.services.wayvnc = lib.mkIf cfg.virtualOutput.enable {
      Service.ExecStartPre = [ ensureVirtualOutput ];
    };

    #======================================================================
    # VALIDATION
    #======================================================================
    assertions = [
      {
        assertion = osConfig.hwc.system.apps.hyprland.enable or false;
        message = "hwc.home.apps.wayvnc requires hwc.system.apps.hyprland enabled to ensure the Wayland session and helpers.";
      }
      {
        assertion = cfg.virtualOutput.mode != "";
        message = "hwc.home.apps.wayvnc.virtualOutput.mode cannot be empty.";
      }
    ];
  };
}
