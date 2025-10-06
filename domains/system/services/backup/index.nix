# NEW, CORRECT file: domains/system/services/backup/index.nix
#
# BACKUP - System-wide backup service and tools.
# This file aggregates the module's components and defines its core packages.

{ config, lib, pkgs, ... }:

let
  # This now correctly points to the API defined in options.nix
  cfg = config.hwc.system.services.backup;
in
{
  #=========================================================================
  # MODULE AGGREGATION
  #=========================================================================
  # This file assembles the backup module by importing its API (options)
  # and its implementation logic (parts).
  imports = [
    ./options.nix
    ./parts/scripts.nix
    ./parts/services.nix
  ];

  #=========================================================================
  # CO-LOCATED PACKAGES
  #=========================================================================
  # This is the single source of truth for all packages required by this module.
  # The parts files can then assume these packages are available.
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      # Core backup tools
      rclone
      rsync
      gnutar
      gzip
      p7zip
      logrotate
    ]
    # Add any extra tools defined on a per-machine basis.
    ++ cfg.extraTools;
  };
}
