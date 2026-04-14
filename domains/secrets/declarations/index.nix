# domains/secrets/declarations/index.nix
#
# Aggregates all domain secret declarations into a single import
# Each domain file contains only age.secrets declarations, no logic
{ config, lib, ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.secrets.declarations = {
    enable = lib.mkEnableOption "secret declarations aggregation" // {
      default = true;
    };
  };

  imports = [
    ./caddy.nix
    ../parts/caddy.nix
    ./home.nix
    ./system.nix
    ./services.nix
    ./infrastructure.nix
  ];
}
