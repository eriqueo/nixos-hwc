{ config, lib, pkgs, osConfig ? {}, ...}:
let
  on =
    (config.hwc.mail.enable or true) &&
    ((lib.attrValues (config.hwc.mail.accounts or {})) != []);

  render = import ./parts/render.nix { inherit lib pkgs config; };
in
{
  #==========================================================================
  # OPTIONS 
  #==========================================================================
  # Options: none (uses parent hwc.mail.accounts)
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf on (lib.mkMerge [
    { home.packages = render.packages; }
    { home.file = render.files; }
  ]);
}

  #==========================================================================
  # VALIDATION
  #==========================================================================