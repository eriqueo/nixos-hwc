{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.sabnzbd;
in
{
  # Charter v6 migration: Container implementation moved to parts/config.nix
  # This sys.nix file is preserved for Charter compliance but implementation is disabled
  # to avoid conflicts with the proper Charter-compliant implementation
  config = lib.mkIf false { };
}
