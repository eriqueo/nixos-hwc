# FINAL, CORRECT file: domains/system/services/vpn/index.nix
#
# VPN - Manages ProtonVPN connectivity using the official CLI and existing secrets.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.vpn;

  usernameFile = config.hwc.security.materials.vpnUsernameFile;
  passwordFile = config.hwc.security.materials.vpnPasswordFile;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf (cfg.enable && cfg.protonvpn.enable) {

    #=========================================================================
    # PROTONVPN CLI SERVICE
    #=========================================================================
    # This service ensures you are logged in and connected on boot.
    systemd.services.protonvpn-connect = {
      description = "ProtonVPN CLI Connect Service";
      # We want this to start after the network is fully online.
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # This is a 'oneshot' service because it runs a command and then exits.
      # The VPN connection itself is managed by the system's networking stack.
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;

        # The magic happens here. We run a script that uses the secret files.
        ExecStart = pkgs.writeScript "protonvpn-login-script" ''
          #!${pkgs.bash}/bin/bash
          set -e
          # First, log in using the username and password from the secret files.
          ${pkgs.protonvpn-cli}/bin/protonvpn-cli login --username "$(cat ${usernameFile})" --password "$(cat ${passwordFile})"
          # Then, connect to the fastest server.
          ${pkgs.protonvpn-cli}/bin/protonvpn-cli connect --fastest
        '';

        # The corresponding stop command.
        ExecStop = "${pkgs.protonvpn-cli}/bin/protonvpn-cli disconnect";
      };

      # We want this service to be enabled on boot.
      wantedBy = [ "multi-user.target" ];
    };

    #=========================================================================
    # CO-LOCATED PACKAGES
    #=========================================================================
    # The module now provides the official CLI tool.
    environment.systemPackages = with pkgs; [
      protonvpn-cli
    ];

    #=========================================================================
    # VALIDATION
    #=========================================================================
    assertions = [
      {
        assertion = usernameFile != null;
        message = "ProtonVPN is enabled, but the 'vpnUsernameFile' secret is not available.";
      }
      {
        assertion = passwordFile != null;
        message = "ProtonVPN is enabled, but the 'vpnPasswordFile' secret is not available.";
      }
    ];
  };

}
