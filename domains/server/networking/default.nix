# domains/server/networking/index.nix
#
# Server networking subdomain aggregator
# Imports options and networking implementation files

{ lib, config, pkgs, ... }:

{
  imports = [
    ./options.nix
    ./parts/vpn.nix
    ./parts/ntfy.nix
    ./parts/transcript-api.nix
    ./parts/databases.nix
    ./parts/networking.nix
  ];
}