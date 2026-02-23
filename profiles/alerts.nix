# profiles/alerts.nix
#
# Alerts Profile - Centralized alert routing to Slack via n8n
#
# DEPENDENCIES:
#   - domains/alerts (alert implementation)
#   - hwc.server.native.n8n (webhook receiver)
#
# USED BY:
#   - machines/server/config.nix

{ lib, config, ... }:

{
  #==========================================================================
  # BASE - Domain imports
  #==========================================================================
  imports = [
    ../domains/alerts/index.nix
  ];

  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================
  hwc.alerts = {
    # Enable alerts system by default
    enable = lib.mkDefault true;

    # Alert sources - all enabled by default for server
    sources = {
      # SMART disk monitoring (requires services.smartd.enable)
      smartd.enable = lib.mkDefault true;

      # Backup notifications
      backup = {
        enable = lib.mkDefault true;
        onSuccess = lib.mkDefault false;  # Don't spam on success
        onFailure = lib.mkDefault true;   # Always alert on failure
      };

      # Disk space monitoring
      diskSpace = {
        enable = lib.mkDefault true;
        criticalThreshold = lib.mkDefault 95;  # P5 alert at 95%
        warningThreshold = lib.mkDefault 80;   # P4 alert at 80%
        frequency = lib.mkDefault "hourly";
        # Default filesystems - machine can override
        filesystems = lib.mkDefault [ "/" "/home" ];
      };

      # Service failure monitoring
      serviceFailures = {
        enable = lib.mkDefault true;
        autoDetect = lib.mkDefault true;  # Auto-detect critical services
        # Empty = auto-detect, or specify explicit list
        services = lib.mkDefault [];
      };
    };

    # CLI tool enabled by default
    cli.enable = lib.mkDefault true;
  };
}
