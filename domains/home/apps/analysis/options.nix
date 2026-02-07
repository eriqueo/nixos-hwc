{ lib, ... }:

let
  inherit (lib) types mkOption;
in {
  options.hwc.home.apps.analysis = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Polars-based data analysis tool (JupyterLab with extensions).";
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Additional Python packages to include.";
    };
  };
}
