# domains/system/apps/index.nix
#
# Aggregates all system-level app façades
{ ... }:
{
  imports = [
    ./fabric/index.nix
  ];
}
