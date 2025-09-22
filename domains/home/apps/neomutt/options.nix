{ lib, ... }:

{
  options.features.neomutt = {
    enable = lib.mkEnableOption "Enable NeoMutt and related mail tooling";

    materials = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Resolved security/materials view from system lane.";
    };
    #-------------------------------------------------------------------------
                                # color themeing
    #-------------------------------------------------------------------------
    theme = {
      # null → use global config.hwc.home.theme.name
      palette = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Per-app palette override for NeoMutt (e.g. \"gruv\" | \"deep-nord\").";
      };
    };


  };
}
