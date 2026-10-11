# domains/home/apps/tether/sys.nix
# System half of Tether: the upstream NixOS module (BlueZ experimental bearer
# API, the Class-of-Device oneshot per adapter, native-messaging hosts) behind
# the HWC system-app toggle. The Home Manager half (index.nix) runs the daemon
# and never imports this file; it checks the toggle through the osConfig
# handshake (CHARTER sys.nix pattern, domains/lib/hm.nix).
#
# The package is built from the pinned `tether` flake input with THIS repo's
# nixpkgs (the flake's own overlay does the same callPackage), so no second
# nixpkgs is evaluated.

{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.hwc.system.apps.tether;
  package = pkgs.callPackage "${inputs.tether}/nix/package.nix" {
    npmConfigHook = pkgs.npmHooks.npmConfigHook;
  };
in
{
  imports = [ inputs.tether.nixosModules.default ];

  #============================================================================
  # OPTIONS - System-lane API
  #============================================================================
  options.hwc.system.apps.tether = {
    enable = lib.mkEnableOption "Tether system half: BlueZ bearer API and Class-of-Device for iPhone messages";

    adapters = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "hci[0-9]+");
      default = [ "hci0" ];
      description = "Bluetooth adapters Tether sets to the A/V Hands-Free class so iOS offers the Messages and Contacts toggles.";
    };

    wifi.enable = lib.mkEnableOption ''
      the Wi-Fi half (clipboard, files, OTP) used by the free iPhone companion
      app: Avahi publishing plus TCP 5134 and mDNS through the firewall. Off by
      default; messages and notifications are Bluetooth-only and need none of it'';

    extensions = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [ "firefox" "chromium" "thunderbird" ]);
      default = [ ];
      description = "Browser or mail extensions registered as native-messaging hosts for OTP autofill.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      defaultText = lib.literalExpression ''pkgs.callPackage "''${inputs.tether}/nix/package.nix" { }'';
      readOnly = true;
      description = "The Tether package the Home Manager half runs (one producer for both lanes).";
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    programs.tether = {
      enable = true;
      package = cfg.package;
      bluetooth = {
        enable = true;
        adapters = cfg.adapters;
      };
      wifi = {
        enable = cfg.wifi.enable;
        openFirewall = cfg.wifi.enable;
      };
      extensions = cfg.extensions;
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = config.hwc.system.hardware.bluetooth.enable;
        message = "hwc.system.apps.tether needs hwc.system.hardware.bluetooth.enable = true (the phone link is Bluetooth MAP/PBAP/ANCS).";
      }
    ];
  };
}
