# Template for HWC Charter-compliant options.nix files
# This template follows the HWC Charter v5 requirements:
# - Namespace matches directory structure (domains/path/to/module → hwc.path.to.module.*)
# - Uses proper lib conventions
# - Provides enable option as minimum requirement

{ lib, ... }:

{
  options.hwc.{{NAMESPACE_PATH}} = {
    enable = lib.mkEnableOption "{{MODULE_DESCRIPTION}}";

    # Add additional options specific to this module as needed
    # Example options patterns:
    # package = lib.mkOption { type = lib.types.package; default = pkgs.{{MODULE_NAME}}; };
    # configFile = lib.mkOption { type = lib.types.str; default = ""; };
    # extraArgs = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    # environment = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = {}; };
  };
}