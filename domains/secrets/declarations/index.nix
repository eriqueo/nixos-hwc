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
    ./caddy.nix          # caddy-cert/caddy-key OPTIONS
    ../parts/caddy.nix   # caddy-cert/caddy-key MOUNTS (runtime hostname selection)
    ./generated.nix      # all other age.secrets, generated from parts/**.age
  ];
}
