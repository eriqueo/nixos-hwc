# modules/home/apps/chromium/options.nix
{ lib, ... }:

{
  options.features.chromium = {
    enable = lib.mkEnableOption "Chromium browser (user-scoped package)";
  };
}