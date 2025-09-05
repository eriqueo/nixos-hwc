# nixos-hwc/modules/home/betterbird/parts/session.nix
#
# Betterbird Session: Services & Lifecycle Management
# Charter v5 compliant - Universal session domain for email services and startup
#
# DEPENDENCIES (Upstream):
#   - systemPackages for protonmail-bridge
#
# USED BY (Downstream):
#   - modules/home/betterbird/default.nix
#
# USAGE:
#   let session = import ./parts/session.nix { inherit lib pkgs; };
#   in { systemd.user.services = session.services; }
#

{ lib, pkgs, ... }:

{
  #============================================================================
  # SYSTEMD SERVICES - Email-related background services
  #============================================================================
  services = {
    # ProtonMail Bridge - maintains stable connection to ProtonMail servers
    protonmail-bridge = {
      Unit = {
        Description = "ProtonMail Bridge";
        After = [ "network.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.protonmail-bridge}/bin/protonmail-bridge --noninteractive";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}