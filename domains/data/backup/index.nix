# domains/server/backup/index.nix
#
# Backup subdomain aggregator
# Imports options and backup implementation

{ lib, config, pkgs, ... }:

{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./parts/user-backup.nix
    ./parts/server-backup-scripts.nix
  ];
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};

  #==========================================================================
  # VALIDATION
  #==========================================================================
    config.assertions = lib.mkIf (config ? enable && config.enable) [];

}