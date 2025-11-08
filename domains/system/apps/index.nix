# domains/system/apps/index.nix
#
# Aggregates all system-level app façades
{ ... }:
{
  imports = [
    # TODO: Re-enable fabric when upstream darwin SDK issue is resolved
    # ./fabric/index.nix
  ];
}
