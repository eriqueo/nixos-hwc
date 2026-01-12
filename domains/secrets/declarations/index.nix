# domains/secrets/declarations/index.nix
#
# Aggregates all domain secret declarations into a single import
# Each domain file contains only age.secrets declarations, no logic
# Organized by HWC domain structure: home, system, server, infrastructure, apps
{ config, lib, ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./caddy.nix
    ../parts/caddy.nix
    ./home.nix
    ./system.nix
    ./server.nix
    ./infrastructure.nix
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
