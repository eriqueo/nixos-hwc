{ config, lib, pkgs, ... }:
let
  mail = config.hwc.home.mail or {};
  vals = lib.attrValues (mail.accounts or {});
  needs = lib.any (a: a.type == "proton-bridge") vals;
  enabled = (mail.enable or false) && needs;

  br = mail.bridge or {};
  runtime = import ./parts/runtime.nix { inherit lib pkgs br; };
  files = import ./parts/files.nix { inherit lib br; };
  service = import ./parts/service.nix { inherit lib pkgs br runtime; };
in
{
  imports = [ ./options.nix ];
  config = lib.mkIf enabled (lib.mkMerge [
    { home.packages = [ (br.package or pkgs.protonmail-bridge) ]; }
    files
    service
  ]);
}
