# domains/home/apps/wayvnc/index.nix
# Wayland VNC server with optional virtual output for second-screen setups.

{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.wayvnc;

  # Feature Detection: Check if we're on a NixOS host with HWC system config
  isNixOSHost = osConfig ? hwc;

  baseSettings =
    {
      address = cfg.network.address;
      port = cfg.network.port;
    };

  # Create (or find) a headless output in Hyprland and configure it.
  ensureVirtualOutput = pkgs.writeShellScript "wayvnc-ensure-virtual-output" ''
    set -euo pipefail
    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"

    OUT="${cfg.virtualOutput.name}"
    MODE="${cfg.virtualOutput.mode}"
    POS="${cfg.virtualOutput.position}"
    # Create a headless output (Hyprland names it HEADLESS-1, HEADLESS-2, ...)
    "$HYPRCTL" output create headless >/dev/null 2>&1 || true
    # Configure resolution/position on the requested name
    "$HYPRCTL" keyword monitor "''${OUT},''${MODE},''${POS},1"
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
    home.packages = [ pkgs.hyprland ];

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
      # Override the HM module's single ExecStart with one line
      Service.ExecStart = lib.mkForce "${pkgs.wayvnc}/bin/wayvnc --output ${cfg.virtualOutput.name}";
    };

    #======================================================================
    # VALIDATION
    #======================================================================
    assertions = [
      # Cross-lane consistency: check if system-lane hyprland is enabled (NixOS only)
      # Feature Detection: Only enforce on NixOS hosts where system config is available
      # On non-NixOS hosts, user is responsible for Wayland session dependencies
      {
        assertion = !isNixOSHost || (osConfig.hwc.system.apps.hyprland.enable or false);
        message = "hwc.home.apps.wayvnc requires hwc.system.apps.hyprland enabled to ensure the Wayland session and helpers.";
      }
      {
        assertion = cfg.virtualOutput.mode != "";
        message = "hwc.home.apps.wayvnc.virtualOutput.mode cannot be empty.";
      }
    ];
  };
}
