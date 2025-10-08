{ config, lib, pkgs, ... }:
let
  on =
    (config.hwc.home.mail.enable or true) &&
    ((lib.attrValues (config.hwc.home.mail.accounts or {})) != []);

  render = import ./parts/render.nix { inherit lib pkgs config; };
in
{
  #==========================================================================
  # OPTIONS 
  #==========================================================================
  imports = [ ./options.nix ];
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