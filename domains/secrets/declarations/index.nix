# domains/secrets/declarations/index.nix
#
# Aggregates all domain secret declarations into a single import
# Each domain file contains only age.secrets declarations, no logic
{ config, lib, ... }:
{
  imports = [
    ./options.nix
    ./caddy.nix
    ../parts/caddy.nix
    ./home.nix
    ./system.nix
    ./services.nix
    ./infrastructure.nix
  ];
}
