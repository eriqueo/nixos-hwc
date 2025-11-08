# domains/system/apps/index.nix
#
# Aggregates all system-level app façades
{ ... }:
{
  imports = [
    # TODO: Re-enable Fabric when Go 1.25 / nixpkgs compatibility is resolved
    # ./fabric/index.nix
  ];
}
