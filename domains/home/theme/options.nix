# modules/home/theme/options.nix
{ lib, osConfig ? {}, ... }:

{
  options.hwc.home.theme = {
    palette = lib.mkOption {
      type = lib.types.enum [ "deep-nord" "gruv" ];
      default = "deep-nord";
      description = "Active theme palette (single source of truth).";
    };
    
    colors = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Materialized color tokens from selected palette.";
    };
  };
}