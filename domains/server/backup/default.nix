# domains/server/backup/index.nix
#
# Backup subdomain aggregator
# Imports options and backup implementation

{ lib, config, pkgs, ... }:

{
  imports = [
    ./options.nix
    ./parts/user-backup.nix
  ];
}