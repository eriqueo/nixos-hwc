# modules/security/secrets/index.nix
#
# Aggregates all domain secret files into a single import
# Each domain file contains only age.secrets declarations, no logic
{ lib, ... }:
{
  imports = [
    ./system.nix
    ./services.nix
    ./infrastructure.nix
    ./networking.nix
  ];
}