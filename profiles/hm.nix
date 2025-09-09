# profiles/hm.nix - Home Manager lane
# Charter v7: Only imports Home Manager scope
{ ... }: {
  imports = [ ../modules/home/index.nix ];
}