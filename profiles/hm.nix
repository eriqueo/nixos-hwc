# profiles/hm.nix - Home Manager lane
# Charter v7: Only imports Home Manager scope
{ ... }:
{
  home-manager.users.eric.imports = [
    ../modules/home/index.nix
  ];
}
