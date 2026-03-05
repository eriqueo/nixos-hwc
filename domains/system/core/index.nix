# modules/system/core/index.nix — aggregates core system functionality
{ ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./identity/index.nix  # System identity (puid/pgid/user/group) - Law 4
    ./packages.nix
    # paths.nix moved to domains/paths/paths.nix (Primitive Module)
    ../../paths/paths.nix
    ./filesystem.nix
    ./thermal.nix
    ./validation.nix
    ./polkit/index.nix    # MOVED from domains/system/services/polkit
    ./session/index.nix   # MOVED from domains/system/services/session
    ./shell/index.nix     # MOVED from domains/system/services/shell
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};
}
