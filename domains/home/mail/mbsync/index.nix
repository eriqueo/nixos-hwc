{ config, lib, pkgs, ... }:
let
  on =
    (config.hwc.home.mail.enable or true) &&
    ((lib.attrValues (config.hwc.home.mail.accounts or {})) != []);

  render = import ./parts/render.nix { inherit lib pkgs config; };
  svc    = import ./parts/service.nix { inherit lib pkgs; haveProton = render.haveProton; };
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
    { home.file.".mbsyncrc".text = render.mbsyncrc; }
    svc
  ]);
}

  #==========================================================================
  # VALIDATION
  #==========================================================================