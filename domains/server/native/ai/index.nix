# domains/server/native/ai/index.nix
#
# AI services aggregator — explicit imports (avoid auto-discovery pulling
# in ai/mcp which references pkgs.mcp-proxy not in nixpkgs-stable)
{ ... }:
{
  imports = [
    ./jobber-mcp/index.nix
  ];
}
