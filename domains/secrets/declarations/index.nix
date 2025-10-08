# domains/secrets/declarations/index.nix
#
# Aggregates all domain secret declarations into a single import
# Each domain file contains only age.secrets declarations, no logic
# Organized by HWC domain structure: home, system, server, infrastructure
{ lib, ... }:
{
  imports = [
    ./home.nix
    ./system.nix
    ./server.nix
    ./infrastructure.nix
  ];
}